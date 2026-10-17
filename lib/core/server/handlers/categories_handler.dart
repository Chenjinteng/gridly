// lib/core/server/handlers/categories_handler.dart
// LAN_WEB v2.0.0 P2 分类 CRUD API
//
// - GET    /api/categories             全部(可按 type 过滤)
// - POST   /api/categories             新增自定义分类
// - PUT    /api/categories/:id         修改
// - DELETE /api/categories/:id         P2 不删(LAN_WEB.md 没列),P3 再加
//
// 全部需 cookie(authMiddleware 守卫)
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart';
import 'json_helpers.dart';

void registerCategoriesHandlers(RouterPlus app, AppDatabase db) {
  // GET /api/categories?type=expense|income|investment|benefit|liability|other
  app.get('/api/categories', (Request request) async {
    final type = request.url.queryParameters['type'];
    final query = db.select(db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    if (type != null && type.isNotEmpty) {
      query.where((c) => c.type.equals(type));
    }
    final categories = await query.get();
    return jsonOk({
      'categories': categories.map(categoryToJson).toList(),
    });
  });

  // POST /api/categories
  app.post('/api/categories', (Request request) async {
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) return jsonError(400, 'invalid_body');

    final name = body['name'] as String?;
    final type = body['type'] as String?;
    final color = body['color'] as String?;
    final icon = body['icon'] as String?;
    final sortOrder = body['sortOrder'] as int?;

    if (name == null || name.isEmpty) return jsonError(400, 'missing_name');
    if (type == null ||
        ![
          'expense',
          'income',
          'investment',
          'benefit',
          'liability',
          'other',
        ].contains(type)) {
      return jsonError(400, 'invalid_type');
    }
    // 缺省 color/icon 跟系统默认走
    final effectiveColor = color ?? '#94A3B8';
    final effectiveIcon = icon ?? 'category_outlined';

    // 缺省 sortOrder = 当前 type 已有最大 sortOrder + 10
    int effectiveSortOrder = sortOrder ?? 0;
    if (sortOrder == null) {
      final maxRow = await (db.selectOnly(db.categories)
            ..addColumns([db.categories.sortOrder.max()])
            ..where(db.categories.type.equals(type)))
          .getSingle();
      effectiveSortOrder = (maxRow.read(db.categories.sortOrder.max()) ?? 0) + 10;
    }

    final id = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            type: type,
            color: effectiveColor,
            icon: effectiveIcon,
            sortOrder: effectiveSortOrder,
            isDefault: const Value(false),
          ),
        );
    final c = await (db.select(db.categories)..where((c) => c.id.equals(id)))
        .getSingle();
    return jsonCreated({'category': categoryToJson(c)});
  });

  // PUT /api/categories/:id
  app.put('/api/categories/<id>', (Request request, String id) async {
    final cid = int.tryParse(id);
    if (cid == null) return jsonError(400, 'invalid_id');
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) return jsonError(400, 'invalid_body');

    final existing = await (db.select(db.categories)
          ..where((c) => c.id.equals(cid)))
        .getSingleOrNull();
    if (existing == null) return jsonError(404, 'category_not_found');

    final updated = await (db.update(db.categories)
          ..where((c) => c.id.equals(cid)))
        .writeReturning(
      CategoriesCompanion(
        name: Value(body['name'] as String? ?? existing.name),
        color: Value(body['color'] as String? ?? existing.color),
        icon: Value(body['icon'] as String? ?? existing.icon),
        sortOrder: Value(body['sortOrder'] as int? ?? existing.sortOrder),
      ),
    );
    return jsonOk({'category': categoryToJson(updated.first)});
  });
}