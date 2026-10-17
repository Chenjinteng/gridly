// lib/core/server/gridly_server.dart
// LAN_WEB v2.0.0 P2 HTTP server
//
// 跑在 main isolate(P2 commit 1 后的架构,直接 DB 访问无 IPC 复杂度)
// fg_service 改成 keep-alive 心跳保活进程,不影响 server 启动逻辑
// 详细:docs/LAN_WEB.md
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart'; // shelf_plus 不 re-export shelf_io,显式 import 拿 serve()
import 'package:shelf_plus/shelf_plus.dart';

import 'auth.dart';
import 'handlers/auth_handler.dart';
import 'handlers/health_handler.dart';

/// LAN_WEB 服务端口(LAN_WEB.md 钉死:8123,避开 80/8080 高占用)
const int kLanWebPort = 8123;

/// HTTP server 实例
/// - 不暴露给 fg_service isolate(避免两个 isolate 同时操作 server 句柄)
HttpServer? _server;

/// 当前 server 是否在运行(供 controller 查询)
bool get isGridlyServerRunning => _server != null;

/// 配对码存储(in-memory,5 分钟有效)
/// - 暴露给 controller 让 UI 展示当前码
final PairingCodeStore pairingCodeStore = PairingCodeStore();

/// Session 存储(SharedPreferences 持久化,7 天有效)
final SessionStore sessionStore = SessionStore();

/// 启动 HTTP server,绑 0.0.0.0:8123(同 WiFi 设备可访问,不是 localhost)
/// P1:GET / 健康检查
/// P2:+ 鉴权路由 /api/auth/* + 流水 / 分类 / 报表 / 预算
///
/// 由 [LanWebController.setEnabled] 在 main isolate 调(dev mode + Android 都走这条)
Future<HttpServer> startGridlyServer() async {
  if (_server != null) return _server!;
  // 先加载持久化的 sessions(in-memory cache 准备好)
  await sessionStore.load();

  final app = Router().plus;

  // P1 健康检查
  app.get('/', () => healthHandler());

  // P2 鉴权路由(/api/auth/*)
  registerAuthHandlers(app, pairingCodeStore, sessionStore);

  // P2 数据 API(/api/ledgers /api/categories /api/stats /api/budget)
  // 后续 commit 3-6 加

  // 鉴权 middleware(自动跳过 /api/auth/* + /api/health)
  final handler = const Pipeline()
      .addMiddleware(authMiddleware(sessionStore))
      .addHandler(app.call);

  // InternetAddress.anyIPv4 == '0.0.0.0',监听所有网卡(同 WiFi 设备可访问)
  _server = await serve(handler, InternetAddress.anyIPv4, kLanWebPort);
  return _server!;
}

/// 停止 HTTP server(用户切 toggle OFF / app 退出时调)
Future<void> stopGridlyServer() async {
  await _server?.close(force: true);
  _server = null;
}