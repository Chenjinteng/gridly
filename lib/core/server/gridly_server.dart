// lib/core/server/gridly_server.dart
// LAN_WEB v2.0.0 P1 HTTP server skeleton
//
// 跑在 flutter_foreground_task 的 isolate 里
// (锁屏 server 仍活,Android 14+ 用 dataSync type)
// 详细:docs/LAN_WEB.md
import 'dart:io';

import 'package:shelf/shelf_io.dart'; // shelf_plus 不 re-export shelf_io,显式 import 拿 serve()
import 'package:shelf_plus/shelf_plus.dart';

import 'handlers/health_handler.dart';

/// LAN_WEB 服务端口(LAN_WEB.md 钉死:8123,避开 80/8080 高占用)
const int kLanWebPort = 8123;

/// HTTP server 实例,foreground service 持有它用于停止
/// - 不暴露给 main isolate:避免两个 isolate 同时操作 server 句柄
HttpServer? _server;

/// 当前 server 是否在运行(供 TaskHandler / controller 查询)
bool get isGridlyServerRunning => _server != null;

/// 启动 HTTP server,绑 0.0.0.0:8123(同 WiFi 设备可访问,不是 localhost)
/// P1 只 / 健康检查接口;P2 加 ledgers / categories / stats / budget
///
/// 由 [LanWebTaskHandler.onStart] 在 foreground service isolate 里调用
Future<HttpServer> startGridlyServer() async {
  if (_server != null) return _server!;
  final app = Router().plus;
  app.get('/', () => healthHandler());
  // InternetAddress.anyIPv4 == '0.0.0.0',监听所有网卡(同 WiFi 设备可访问)
  _server = await serve(app.call, InternetAddress.anyIPv4, kLanWebPort);
  return _server!;
}

/// 停止 HTTP server(foreground service 关闭时调)
Future<void> stopGridlyServer() async {
  await _server?.close(force: true);
  _server = null;
}