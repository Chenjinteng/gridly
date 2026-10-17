// lib/core/server/handlers/health_handler.dart
// LAN_WEB v2.0.0 P2 健康检查接口(P2 commit 16 增强)
//
// 浏览器访问 http://192.168.x.x:8123/ 看到的 JSON
// P1:hardcode placeholder;P2:从 AppDatabase 实时查 + server uptime
//
// 跑在 foreground service isolate 里,刻意避免依赖 plugin
// (package_info_plus 等 plugin 在 background isolate 不可靠,
//  避免 plugin 平台通道找不到的踩坑)。版本号 hardcode 在编译时常量,
// 跟 pubspec.yaml 的 version 字段保持一致(由 CI / commit hook 检查)。

import 'package:drift/drift.dart';

import '../../database/app_database.dart';

/// 跟 pubspec.yaml version 同步
const String kGridlyWebVersion = '2.0.0';
const int kGridlyWebBuild = 131; // 跟 pubspec.yaml version 2.0.0+131 同步(P2 commit 16)

/// P2 健康检查响应
///
/// 返回示例:
/// ```json
/// {
///   "name": "gridly web",
///   "version": "2.0.0",
///   "build": 131,
///   "phase": "P2 API ready",
///   "dbSchemaVersion": 9,
///   "transactions": 42,
///   "categories": 12,
///   "assets": 5,
///   "uptimeSeconds": 360,
///   "serverTime": "2026-10-17T12:30:00.000Z"
/// }
/// ```
///
/// 用途:
/// - P3 web UI 显示"连接到 gridly v2.0.0+131"
/// - dev 工具看 server uptime / 数据量
/// - 客户端对服务器时间(用于时钟同步)
/// - 不暴露 activeSessions(避免泄露配对设备数)
Future<Map<String, dynamic>> healthHandler({
  required AppDatabase db,
  required DateTime startedAt,
}) async {
  // 3 个 count 并行查
  final results = await Future.wait([
    (db.selectOnly(db.transactions)..addColumns([db.transactions.id.count()]))
        .map((row) => row.read(db.transactions.id.count()) ?? 0)
        .getSingle(),
    (db.selectOnly(db.categories)..addColumns([db.categories.id.count()]))
        .map((row) => row.read(db.categories.id.count()) ?? 0)
        .getSingle(),
    (db.selectOnly(db.assets)..addColumns([db.assets.id.count()]))
        .map((row) => row.read(db.assets.id.count()) ?? 0)
        .getSingle(),
  ]);
  final txCount = results[0];
  final catCount = results[1];
  final assetCount = results[2];

  return <String, dynamic>{
    'name': 'gridly web',
    'version': kGridlyWebVersion,
    'build': kGridlyWebBuild,
    'phase': 'P2 API ready',
    'dbSchemaVersion': db.schemaVersion,
    'transactions': txCount,
    'categories': catCount,
    'assets': assetCount,
    'uptimeSeconds':
        DateTime.now().difference(startedAt).inSeconds,
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  };
}