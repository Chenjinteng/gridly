// lib/core/server/handlers/stats_handler.dart
// LAN_WEB v2.0.0 P2 报表 API
//
// - GET /api/stats/monthly?year&month         月度汇总(收入/支出/结余/笔数)
// - GET /api/stats/categories?from&to         期间分类饼图(支出 only)
// - GET /api/stats/top?from&to&limit          期间 Top 支出
//
// 全部需 cookie,跟 home / stats 页口径一致(D62 收紧:cash_flow 收支 only)
import 'package:drift/drift.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart';
import 'json_helpers.dart';

void registerStatsHandlers(RouterPlus app, AppDatabase db) {
  // GET /api/stats/monthly?year=YYYY&month=MM
  app.get('/api/stats/monthly', (Request request) async {
    final p = request.url.queryParameters;
    final year = int.tryParse(p['year'] ?? '');
    final month = int.tryParse(p['month'] ?? '');
    if (year == null || month == null) {
      return jsonError(400, 'missing_year_or_month');
    }
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    // D62 口径:income/expense 只算 cash_flow 段 — 即 transaction.type 是 income/expense,
    // 投资/福利/债务/其它段的 transaction.type 是别的值,自然不算
    final typeCol = db.transactions.type;

    final joined = db.select(db.transactions).join([
      innerJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.occurredAt.isBiggerOrEqualValue(start) &
          db.transactions.occurredAt.isSmallerThanValue(end) &
          typeCol.isIn(['income', 'expense']));

    final rows = await joined.get();
    double income = 0;
    double expense = 0;
    int txCount = 0;
    for (final row in rows) {
      final t = row.readTable(db.transactions);
      if (t.type == 'income') income += t.amount;
      if (t.type == 'expense') expense += t.amount;
      txCount++;
    }
    return jsonOk({
      'year': year,
      'month': month,
      'income': income,
      'expense': expense,
      'balance': income - expense,
      'transactionCount': txCount,
    });
  });

  // GET /api/stats/categories?from=YYYY-MM-DD&to=YYYY-MM-DD
  // 返回支出按 categoryId 分组的金额 + 百分比
  app.get('/api/stats/categories', (Request request) async {
    final p = request.url.queryParameters;
    final from = p['from'] != null ? DateTime.tryParse(p['from']!) : null;
    final to = p['to'] != null ? DateTime.tryParse(p['to']!) : null;
    if (from == null || to == null) {
      return jsonError(400, 'missing_from_or_to');
    }

    final joined = db.select(db.transactions).join([
      innerJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.occurredAt.isBiggerOrEqualValue(from) &
          db.transactions.occurredAt.isSmallerOrEqualValue(to) &
          db.transactions.type.equals('expense'));

    final rows = await joined.get();
    final byCategory = <int, _CatAgg>{};
    double total = 0;
    for (final row in rows) {
      final t = row.readTable(db.transactions);
      final c = row.readTable(db.categories);
      final agg = byCategory.putIfAbsent(
          c.id, () => _CatAgg(category: c, amount: 0));
      agg.amount += t.amount;
      total += t.amount;
    }
    final items = byCategory.values
        .map((a) => <String, dynamic>{
              'categoryId': a.category.id,
              'categoryName': a.category.name,
              'color': a.category.color,
              'amount': a.amount,
              'percentage': total > 0 ? a.amount / total : 0,
            })
        .toList()
      ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return jsonOk({
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'total': total,
      'items': items,
    });
  });

  // GET /api/stats/top?from&to&limit=10
  app.get('/api/stats/top', (Request request) async {
    final p = request.url.queryParameters;
    final from = p['from'] != null ? DateTime.tryParse(p['from']!) : null;
    final to = p['to'] != null ? DateTime.tryParse(p['to']!) : null;
    final limit = int.tryParse(p['limit'] ?? '10') ?? 10;
    if (from == null || to == null) {
      return jsonError(400, 'missing_from_or_to');
    }

    final joined = db.select(db.transactions).join([
      innerJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
    ])
      ..where(db.transactions.occurredAt.isBiggerOrEqualValue(from) &
          db.transactions.occurredAt.isSmallerOrEqualValue(to) &
          db.transactions.type.equals('expense'));

    final rows = await joined.get();
    final byCategory = <int, _CatAgg>{};
    for (final row in rows) {
      final t = row.readTable(db.transactions);
      final c = row.readTable(db.categories);
      final agg = byCategory.putIfAbsent(
          c.id, () => _CatAgg(category: c, amount: 0));
      agg.amount += t.amount;
    }
    final items = byCategory.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top = items.take(limit).map((a) => <String, dynamic>{
          'categoryId': a.category.id,
          'categoryName': a.category.name,
          'color': a.category.color,
          'amount': a.amount,
        }).toList();
    return jsonOk({
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'items': top,
    });
  });
}

class _CatAgg {
  _CatAgg({required this.category, required this.amount});
  final dynamic category; // Category
  double amount;
}