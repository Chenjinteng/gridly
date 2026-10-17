// lib/core/server/gridly_server.dart
// LAN_WEB v2.0.0 P3 HTTP server
//
// 跑在 main isolate(P2 commit 1 后的架构,直接 DB 访问无 IPC 复杂度)
// fg_service 改成 keep-alive 心跳保活进程,不影响 server 启动逻辑
// 详细:docs/LAN_WEB.md
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart'; // shelf_plus 不 re-export shelf_io,显式 import 拿 serve()
import 'package:shelf_plus/shelf_plus.dart'; // re-exports shelf_static

import '../database/app_database.dart';
import 'auth.dart';
import 'handlers/auth_handler.dart';
import 'handlers/budget_handler.dart';
import 'handlers/categories_handler.dart';
import 'handlers/health_handler.dart';
import 'handlers/ledgers_handler.dart';
import 'handlers/stats_handler.dart';
import 'middleware.dart';

// 暴露给测试用:setUp 里清 rate limit 滑窗,避免跨测试污染
export 'middleware.dart' show clearRateLimiter;

/// LAN_WEB 服务端口(LAN_WEB.md 钉死:8123,避开 80/8080 高占用)
const int kLanWebPort = 8123;

/// P3 commit 1:Flutter web build 产物路径
/// - dev:跑 `flutter build web` 后这个目录才有内容
/// - dev 期间目录不存在 → / 返 404 提示让 user 跑 build web(API 仍正常)
/// - prod:macOS app 打 release 包时,build/web 应该在 build 阶段生成
const String kWebBuildDir = 'build/web';

/// HTTP server 实例
/// - 不暴露给 fg_service isolate(避免两个 isolate 同时操作 server 句柄)
HttpServer? _server;

/// server 启动时间(健康检查算 uptime 用)
DateTime? _serverStartedAt;

/// 当前 server 是否在运行(供 controller 查询)
bool get isGridlyServerRunning => _server != null;

/// 配对码存储(in-memory,5 分钟有效)
/// - 暴露给 controller 让 UI 展示当前码
final PairingCodeStore pairingCodeStore = PairingCodeStore();

/// Session 存储(SharedPreferences 持久化,7 天有效)
final SessionStore sessionStore = SessionStore();

/// 解析 webDir 真实路径 —— 处理 macOS dev (`flutter run -d macos`) 的 cwd 偏移
///
/// `flutter run -d macos` 启动的 app cwd 是 `.app/Contents/MacOS/`,不是项目根。
/// 相对路径 `build/web` 解析不到项目根的 `build/web/`。
/// 试多路径 fallback + log resolved path(debug 期能立刻看到为什么找不到)
String _resolveWebDir(String webDir) {
  // 已经存在 → 直接返
  if (Directory(webDir).existsSync()) return webDir;

  // 常见 macOS / iOS dev 偏移路径(.app/Contents/MacOS/ → project root)
  final candidates = <String>[
    webDir,
    '../../../../$webDir',  // macOS dev:cwd 是 .app/Contents/MacOS
    '../../../$webDir',     // iOS / 其它平台
    '../../$webDir',        // 浅一层
  ];
  for (final c in candidates) {
    if (Directory(c).existsSync()) {
      debugPrint('[lan_web] webDir fallback: $webDir → $c');
      return c;
    }
  }
  debugPrint(
      '[lan_web] webDir 解析失败:尝试过 ${candidates.join(", ")} 都不存在');
  return webDir; // give up,返 404 web_ui_not_built
}

/// P3 commit 1:Web 静态文件 handler
///
/// - [webDir] 存在 → createStaticHandler 正常服务
/// - [webDir] 不存在(刚 git clone / 还没 build web)→ 返 404 + 提示,避免整个 / 路由 500
/// - SPA 路由 fallback:任意 <非 /api/* 路径> 找不到文件 → 返 index.html 让 Flutter router 处理
Handler _buildWebStaticHandler(String webDir) {
  final resolvedDir = _resolveWebDir(webDir);
  final dir = Directory(resolvedDir);
  if (!dir.existsSync()) {
    debugPrint(
        '[lan_web] $resolvedDir 不存在;Flutter web 未 build。\n'
        '请先跑 `flutter build web --target=lib/web_main.dart` 再启动,或访问 /api/* 用 API。');
    return (Request request) {
      return Response(
        404,
        body: jsonEncode(<String, dynamic>{
          'error': 'web_ui_not_built',
          'message':
              'Flutter web 未 build。请跑 `flutter build web` 然后重启 server。',
          'buildDir': webDir,
          'resolvedDir': resolvedDir,
          'apiOk': 'GET /api/health 仍可访问',
        }),
        headers: <String, String>{'Content-Type': 'application/json'},
      );
    };
  }
  // shelf_static 的 defaultDocument 只在 / fallthrough,不对其它路径做 SPA fallback
  // 所以包一层:static 返 404 时如果不像静态资源文件 → 自己读 index.html 返
  final inner = createStaticHandler(
    resolvedDir,
    defaultDocument: 'index.html',
    listDirectories: false,
  );
  return (Request request) async {
    final resp = await inner(request);
    if (resp.statusCode == 404) {
      final reqPath = request.url.path;
      // 文件请求(带扩展名)真 404;其它没扩展名的当 SPA 路径 → index.html
      // 也跳过 flutter 资源目录避免 fallback 到 html
      final looksLikeFile = reqPath.contains('.');
      final isFlutterAsset = reqPath.startsWith('assets/') ||
          reqPath.startsWith('canvaskit/') ||
          reqPath.startsWith('icons/') ||
          reqPath == 'flutter.js' ||
          reqPath == 'flutter_bootstrap.js' ||
          reqPath == 'flutter_service_worker.js' ||
          reqPath == 'favicon.png' ||
          reqPath == 'manifest.json' ||
          reqPath == 'version.json' ||
          reqPath == 'main.dart.js';
      if (!looksLikeFile && !isFlutterAsset) {
        // SPA fallback:直接读 index.html 文件,不走 static handler
        //   (Request.change 要求新 path 是 handler path 的前缀,绕过)
        final indexFile = File(p.join(resolvedDir, 'index.html'));
        if (indexFile.existsSync()) {
          return Response.ok(
            indexFile.readAsBytesSync(),
            headers: <String, String>{'Content-Type': 'text/html'},
          );
        }
      }
    }
    return resp;
  };
}

/// 启动 HTTP server,绑 0.0.0.0:8123(同 WiFi 设备可访问,不是 localhost)
/// P1:GET /api/health 健康检查
/// P2:+ 鉴权路由 /api/auth/* + 流水 / 分类 / 报表 / 预算
/// P3:+ GET / 服务 Flutter web build(同端口 SPA + API)
///
/// [db] 注入:数据 API 直接 query Drift,无 IPC 复杂度
/// [port] 测试时传 0 让系统分配随机端口,避开 8123 占用冲突
/// [webDir] 测试可指 temp dir(避免污染项目 build/web);默认 'build/web'
/// 由 [LanWebController.setEnabled] 在 main isolate 调(dev mode + Android 都走这条)
Future<HttpServer> startGridlyServer({
  required AppDatabase db,
  int port = kLanWebPort,
  String webDir = kWebBuildDir,
}) async {
  if (_server != null) return _server!;
  // 先加载持久化的 sessions(in-memory cache 准备好)
  await sessionStore.load();

  final app = Router().plus;

  // 健康检查(P3 commit 1:从 / 移到 /api/health,/ 留给 web SPA)
  _serverStartedAt = DateTime.now();
  app.get('/api/health',
      () async => healthHandler(db: db, startedAt: _serverStartedAt!));

  // P2 鉴权路由(/api/auth/*,内部 public 不需 cookie)
  registerAuthHandlers(app, pairingCodeStore, sessionStore);

  // P2 数据 API(protected,middleware 校验 cookie)
  registerLedgersHandlers(app, db);
  registerCategoriesHandlers(app, db);
  registerStatsHandlers(app, db);
  registerBudgetHandlers(app, db);

  // P3 commit 1:API 404 catch-all(/api/<未匹配> 返 JSON 404,先注册让具体路由优先)
  app.all('/api/<ignored|.*>', (Request request) => catchAllHandler()(request));

  // P3 commit 1:静态文件兜底(/<非 api 路径> 走 Flutter web build)
  //  - build/web 存在 → createStaticHandler(找不到文件 fallthrough 到 index.html 给 SPA)
  //  - 不存在 → _buildWebStaticHandler 返 404 + 提示
  app.all('/<ignored|.*>', _buildWebStaticHandler(webDir));

  // 鉴权 middleware(自动跳过 /api/auth/* + /api/health)
  // + errorHandler(任何 throw → 500 JSON,不漏 stack)
  // + securityHeaders(防 MIME 嗅探 / clickjacking / referrer 泄露 / 中间缓存)
  // + bodySizeLimit(> 1MB 早返 413,防 OOM)
  // + cors(OPTIONS 预检 204;其它响应 echo Origin 让 P3 web UI 跨源)
  // + rateLimit(每 session token 60 req/sec;超返 429 带 Retry-After:1)
  //   顺序:rateLimit 在 auth 之后,这样 key 是 session token(更准);
  //   但 401/404 等错误也会消耗 1 次额度(可接受,反正超 60/s 才会限)
  //   securityHeaders 在最外层(errorHandler 之后),保证所有响应都带
  final handler = const Pipeline()
      .addMiddleware(errorHandler())
      .addMiddleware(securityHeaders())
      .addMiddleware(cors())
      .addMiddleware(bodySizeLimit())
      .addMiddleware(authMiddleware(sessionStore))
      .addMiddleware(rateLimit())
      .addHandler(app.call);

  // InternetAddress.anyIPv4 == '0.0.0.0',监听所有网卡(同 WiFi 设备可访问)
  _server = await serve(handler, InternetAddress.anyIPv4, port);
  return _server!;
}

/// 停止 HTTP server(用户切 toggle OFF / app 退出时调)
Future<void> stopGridlyServer() async {
  await _server?.close(force: true);
  _server = null;
  _serverStartedAt = null;
}