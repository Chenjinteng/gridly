// lib/core/server/handlers/budget_handler.dart
// LAN_WEB v2.0.0 P2 月度预算 API
//
// - GET /api/budget?year=YYYY&month=MM
//   → { year, month, total, spent, categoryBudgets: [{categoryId, name, color, amount, spent, remaining}] }
// - PUT /api/budget
//   body: { year, month, total, categoryBudgets?: [{categoryId, amount}] }
//
// 全部需 cookie
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart';
import 'json_helpers.dart';

void registerBudgetHandlers(RouterPlus app, AppDatabase db) {
  // GET /api/budget?year&month
  app.get('/api/budget', (Request request) async {
    final p = request.url.queryParameters;
    final year = int.tryParse(p['year'] ?? '');
    final month = int.tryParse(p['month'] ?? '');
    if (year == null || month == null) {
      return jsonError(400, 'missing_year_or_month');
    }

    // 总额度
    final totalRow = await (db.select(db.monthlyBudgets)
          ..where((m) => m.year.equals(year) & m.month.equals(month)))
        .getSingleOrNull();
    final total = totalRow?.amount ?? 0;

    // 分类子额度
    final cbRows = await (db.select(db.categoryBudgets).join([
      innerJoin(
        db.categories,
        db.categories.id.equalsExp(db.categoryBudgets.categoryId),
      ),
    ])
          ..where(db.categoryBudgets.year.equals(year) &
              db.categoryBudgets.month.equals(month)))
        .get();

    // 同期实际支出(按 categoryId)
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final txRows = await (db.select(db.transactions)
          ..where((t) => t.occurredAt.isBiggerOrEqualValue(start) &
              t.occurredAt.isSmallerThanValue(end) &
              t.type.equals('expense')))
        .get();
    final spentByCategory = <int, double>{};
    for (final t in txRows) {
      spentByCategory[t.categoryId] =
          (spentByCategory[t.categoryId] ?? 0) + t.amount;
    }

    final items = cbRows.map((row) {
      final cb = row.readTable(db.categoryBudgets);
      final c = row.readTable(db.categories);
      final spent = spentByCategory[c.id] ?? 0;
      return <String, dynamic>{
        'categoryId': c.id,
        'categoryName': c.name,
        'color': c.color,
        'amount': cb.amount,
        'spent': spent,
        'remaining': cb.amount - spent,
      };
    }).toList();

    return jsonOk({
      'year': year,
      'month': month,
      'total': total,
      'spent': txRows.fold<double>(0, (s, t) => s + t.amount),
      'categoryBudgets': items,
    });
  });

  // PUT /api/budget
  app.put('/api/budget', (Request request) async {
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) return jsonError(400, 'invalid_body');
    final year = body['year'] as int?;
    final month = body['month'] as int?;
    final total = (body['total'] as num?)?.toDouble();
    final cbList = body['categoryBudgets'] as List<dynamic>?;
    if (year == null || month == null || total == null) {
      return jsonError(400, 'missing_year_month_or_total');
    }

    // upsert 总额度(monthly_budgets 联合唯一: year+month)
    final existingTotal = await (db.select(db.monthlyBudgets)
          ..where((m) => m.year.equals(year) & m.month.equals(month)))
        .getSingleOrNull();
    if (existingTotal == null) {
      await db.into(db.monthlyBudgets).insert(
            MonthlyBudgetsCompanion.insert(
              year: year,
              month: month,
              amount: total,
              updatedAt: Value(DateTime.now()),
            ),
          );
    } else {
      await (db.update(db.monthlyBudgets)
            ..where((m) => m.id.equals(existingTotal.id)))
          .write(MonthlyBudgetsCompanion(
        amount: Value(total),
        updatedAt: Value(DateTime.now()),
      ));
    }

    // upsert 分类子额度(覆盖式:传了的就 update/insert,没传的保留不变)
    if (cbList != null) {
      for (final raw in cbList) {
        if (raw is! Map<String, dynamic>) continue;
        final cid = raw['categoryId'] as int?;
        final amount = (raw['amount'] as num?)?.toDouble();
        if (cid == null || amount == null) continue;

        final existing = await (db.select(db.categoryBudgets)
              ..where((c) => c.categoryId.equals(cid) &
                  c.year.equals(year) &
                  c.month.equals(month)))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.categoryBudgets).insert(
                CategoryBudgetsCompanion.insert(
                  categoryId: cid,
                  year: year,
                  month: month,
                  amount: amount,
                ),
              );
        } else {
          await (db.update(db.categoryBudgets)
                ..where((c) => c.id.equals(existing.id)))
              .write(CategoryBudgetsCompanion(
            amount: Value(amount),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }
    }

    return jsonOk({'ok': true, 'year': year, 'month': month, 'total': total});
  });
}