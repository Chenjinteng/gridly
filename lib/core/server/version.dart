// lib/core/server/version.dart
// LAN_WEB 服务端 + web 端共享版本常量
//
// 跟 pubspec.yaml version 字段保持一致(由 CI / commit hook 检查)。
// 抽到独立文件是因为 web 端也要显示版本,但 web 不能 import app_database.dart
// (含 dart:ffi 在 web 平台不可用,见 P3 commit 2 build 失败原因)。
library;

const String kGridlyWebVersion = '2.0.0';
const int kGridlyWebBuild = 135; // 跟 pubspec.yaml version 2.0.0+135 同步
