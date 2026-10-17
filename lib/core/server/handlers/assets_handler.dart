// lib/core/server/handlers/assets_handler.dart
// LAN_WEB v2.0.0 P2 资产(账户)列表 API
//
// - GET /api/assets               列出所有账户(按 displayOrder 排序)
//
// React web 用这个填 记一笔 modal 的账户下拉 + 配对设备的资产选择
// 全部需 cookie(authMiddleware 已守卫)
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart';
import 'json_helpers.dart';

void registerAssetsHandlers(RouterPlus app, AppDatabase db) {
  app.get('/api/assets', (Request request) async {
    final assets = await (db.select(db.assets)
          ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
        .get();
    return jsonOk({
      'assets': assets.map(assetToJson).toList(),
    });
  });
}