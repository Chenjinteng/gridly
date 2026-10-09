// lib/features/ledger/application/transactions_providers.dart
// 流水 / 分类 相关 Riverpod Provider(被首页 / 流水 / 记一笔三处复用)
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';

/// 当前月份的时间区间
final monthRangeProvider = Provider<({DateTime start, DateTime end})>((ref) {
  final now = DateTime.now();
  return (
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1)),
  );
});

/// 当前月份的所有流水(按时间倒序)
final monthTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final range = ref.watch(monthRangeProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..where((t) => t.occurredAt.isBetweenValues(range.start, range.end))
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .get();
});

/// 本月汇总(收入 / 支出)
class MonthSummary {
  const MonthSummary({required this.income, required this.expense});
  final double income;
  final double expense;
  double get balance => income - expense;
}

final monthSummaryProvider = Provider<MonthSummary>((ref) {
  final txs = ref.watch(monthTransactionsProvider).valueOrNull ?? const [];
  double income = 0, expense = 0;
  for (final t in txs) {
    if (t.type == 'income') {
      income += t.amount;
    } else {
      expense += t.amount;
    }
  }
  return MonthSummary(income: income, expense: expense);
});

/// 全部分类(按 sortOrder 升序)
final allCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.watch(categoryRepositoryProvider).all();
});

/// 按 type 取分类
final categoriesByTypeProvider =
    FutureProvider.family<List<Category>, String>((ref, type) async {
  return ref.watch(categoryRepositoryProvider).byType(type);
});

/// 所有流水按日分组
final allTransactionsByDayProvider =
    FutureProvider<Map<DateTime, List<Transaction>>>((ref) async {
  return ref.watch(transactionRepositoryProvider).groupedByDay();
});
