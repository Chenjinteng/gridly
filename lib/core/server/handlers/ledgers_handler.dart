// lib/core/server/handlers/ledgers_handler.dart
// LAN_WEB v2.0.0 P2 流水 CRUD API
//
// - GET    /api/ledgers               列表(支持过滤 + 分页)
// - GET    /api/ledgers/:id           单笔
// - POST   /api/ledgers               新增
// - PUT    /api/ledgers/:id           修改
// - DELETE /api/ledgers/:id           删除
//
// 全部需 cookie(authMiddleware 已守卫)
// 详细:docs/LAN_WEB.md
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart';
import 'json_helpers.dart';

/// 流水 endpoint 注册入口(gridly_server 用)
void registerLedgersHandlers(RouterPlus app, AppDatabase db) {
  // GET /api/ledgers?from&to&type&category&keyword&page&pageSize
  app.get('/api/ledgers', (Request request) async {
    final p = request.url.queryParameters;
    final from = p['from'];
    final to = p['to'];
    final type = p['type'];
    final categoryId = int.tryParse(p['category'] ?? '');
    final keyword = p['keyword'];
    final page = int.tryParse(p['page'] ?? '1') ?? 1;
    final pageSize = int.tryParse(p['pageSize'] ?? '50') ?? 50;

    final query = db.select(db.transactions);

    if (from != null) {
      final fromDate = DateTime.tryParse(from);
      if (fromDate != null) {
        query.where((t) => t.occurredAt.isBiggerOrEqualValue(fromDate));
      }
    }
    if (to != null) {
      final toDate = DateTime.tryParse(to);
      if (toDate != null) {
        query.where((t) => t.occurredAt.isSmallerOrEqualValue(toDate));
      }
    }
    if (type != null && type.isNotEmpty) {
      query.where((t) => t.type.equals(type));
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (keyword != null && keyword.isNotEmpty) {
      query.where((t) => t.note.like('%$keyword%'));
    }

    query
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(pageSize, offset: (page - 1) * pageSize);

    final ledgers = await query.get();
    return jsonOk({
      'ledgers': ledgers.map(ledgerToJson).toList(),
      'page': page,
      'pageSize': pageSize,
    });
  });

  // GET /api/ledgers/:id
  app.get('/api/ledgers/<id>', (Request request, String id) async {
    final tid = int.tryParse(id);
    if (tid == null) return jsonError(400, 'invalid_id');
    final t = await (db.select(db.transactions)..where((tx) => tx.id.equals(tid)))
        .getSingleOrNull();
    if (t == null) return jsonError(404, 'ledger_not_found');
    return jsonOk({'ledger': ledgerToJson(t)});
  });

  // POST /api/ledgers
  app.post('/api/ledgers', (Request request) async {
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) return jsonError(400, 'invalid_body');

    final amount = (body['amount'] as num?)?.toDouble();
    final type = body['type'] as String?;
    final categoryId = body['categoryId'] as int?;
    final occurredAtStr = body['occurredAt'] as String?;
    final note = body['note'] as String?;
    final accountId = body['accountId'] as int?;
    final destAccountId = body['destinationAccountId'] as int?;

    if (amount == null) return jsonError(400, 'missing_amount');
    if (type == null || !['expense', 'income', 'balance'].contains(type)) {
      return jsonError(400, 'invalid_type');
    }
    if (categoryId == null) return jsonError(400, 'missing_categoryId');
    final occurredAt = occurredAtStr == null
        ? null
        : DateTime.tryParse(occurredAtStr);
    if (occurredAt == null) return jsonError(400, 'missing_or_invalid_occurredAt');

    // accountId 缺省 fallback 到第一个 cash_flow 账户(跟 UI 一致)
    final effectiveAccountId =
        accountId ?? await _firstCashAssetId(db);

    final id = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amount: amount,
            type: type,
            categoryId: categoryId,
            occurredAt: occurredAt,
            note: Value(note),
            accountId: Value(effectiveAccountId),
            destinationAccountId: Value(destAccountId),
          ),
        );
    final t = await (db.select(db.transactions)..where((tx) => tx.id.equals(id)))
        .getSingle();
    return jsonCreated({'ledger': ledgerToJson(t)});
  });

  // PUT /api/ledgers/:id
  app.put('/api/ledgers/<id>', (Request request, String id) async {
    final tid = int.tryParse(id);
    if (tid == null) return jsonError(400, 'invalid_id');
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) return jsonError(400, 'invalid_body');

    final existing = await (db.select(db.transactions)
          ..where((tx) => tx.id.equals(tid)))
        .getSingleOrNull();
    if (existing == null) return jsonError(404, 'ledger_not_found');

    final updated = await (db.update(db.transactions)
          ..where((tx) => tx.id.equals(tid)))
        .writeReturning(
      TransactionsCompanion(
        amount: Value(
            (body['amount'] as num?)?.toDouble() ?? existing.amount),
        type: Value(body['type'] as String? ?? existing.type),
        categoryId: Value(body['categoryId'] as int? ?? existing.categoryId),
        occurredAt: Value(body['occurredAt'] != null
            ? DateTime.parse(body['occurredAt'] as String)
            : existing.occurredAt),
        note: Value(
            body.containsKey('note') ? body['note'] as String? : existing.note),
        accountId: Value(body['accountId'] as int? ?? existing.accountId),
        destinationAccountId: Value(body.containsKey('destinationAccountId')
            ? body['destinationAccountId'] as int?
            : existing.destinationAccountId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return jsonOk({'ledger': ledgerToJson(updated.first)});
  });

  // DELETE /api/ledgers/:id
  app.delete('/api/ledgers/<id>', (Request request, String id) async {
    final tid = int.tryParse(id);
    if (tid == null) return jsonError(400, 'invalid_id');
    final count = await (db.delete(db.transactions)
          ..where((tx) => tx.id.equals(tid)))
        .go();
    if (count == 0) return jsonError(404, 'ledger_not_found');
    return jsonOk({'ok': true});
  });
}

Future<int> _firstCashAssetId(AppDatabase db) async {
  final a = await (db.select(db.assets)
        ..where((a) => a.type.equals('cash_flow'))
        ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)])
        ..limit(1))
      .getSingleOrNull();
  if (a == null) {
    throw StateError('assets 表无 cash_flow 账户,App 启动应已 seed 兜底');
  }
  return a.id;
}