// lib/web_main.dart
// LAN_WEB v2.0.0 P3 web 端独立入口
//
// 与 lib/main.dart(macOS / Android / iOS 入口)的区别:
// - 不调 FlutterForegroundTask.initCommunicationPort()(没 fg_service)
// - 不 seed 分类 / 资产(server 端已 seed,web 端只读 API)
// - 入口是 WebApp 而不是 LedgerlyApp(独立 UI,跟 mobile 壳不一样)
//
// 跑法(从 gridly 项目根):
//   flutter build web --target=lib/web_main.dart
//   flutter run -d macos   # server 跑 main isolate,Chrome 访问 http://localhost:8123/
import 'package:flutter/material.dart';

import 'web/web_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GridlyWebApp());
}
