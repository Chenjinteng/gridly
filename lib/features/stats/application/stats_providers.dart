// lib/features/stats/application/stats_providers.dart
// 报表数据 Provider:时间范围 / 分类支出汇总 / 12 月趋势
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../ledger/application/transactions_providers.dart';

enum StatsRange { thisMonth, thisYear, all }

final statsRangeProvider =
    StateProvider<StatsRange>((_) => StatsRange.thisMonth);

class StatsTimeWindow {
  const StatsTimeWindow(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

final statsWindowProvider = Provider<StatsTimeWindow>((ref) {
  final range = ref.watch(statsRangeProvider);
  final now = DateTime.now();
  switch (range) {
    case StatsRange.thisMonth:
      return StatsTimeWindow(
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 1)
            .subtract(const Duration(seconds: 1)),
      );
    case StatsRange.thisYear:
      return StatsTimeWindow(
        DateTime(now.year, 1, 1),
        DateTime(now.year + 1, 1, 1)
            .subtract(const Duration(seconds: 1)),
      );
    case StatsRange.all:
      return StatsTimeWindow(
        DateTime(2000),
        DateTime(now.year + 1, 1, 1),
      );
  }
});

/// 当前时间窗内的全部流水
final statsTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final w = ref.watch(statsWindowProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..where((t) => t.occurredAt.isBetweenValues(w.start, w.end))
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .get();
});

/// 当前时间窗内的汇总(收入/支出)
class StatsSummary {
  const StatsSummary({required this.income, required this.expense});
  final double income;
  final double expense;
  double get balance => income - expense;
}

final statsSummaryProvider = Provider<StatsSummary>((ref) {
  final txs = ref.watch(statsTransactionsProvider).valueOrNull ?? const [];
  double income = 0, expense = 0;
  for (final t in txs) {
    if (t.type == 'income') {
      income += t.amount;
    } else {
      expense += t.amount;
    }
  }
  return StatsSummary(income: income, expense: expense);
});

class CategoryExpense {
  const CategoryExpense({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amount,
  });
  final int categoryId;
  final String name;
  final int color;
  final double amount;
}

/// 支出按分类汇总(从大到小)
final expenseByCategoryProvider =
    FutureProvider<List<CategoryExpense>>((ref) async {
  final txs = await ref.watch(statsTransactionsProvider.future);
  final cats = await ref.watch(allCategoriesProvider.future);
  if (cats.isEmpty) return const [];
  final byCat = <int, double>{};
  for (final t in txs) {
    if (t.type == 'expense') {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
  }
  final out = <CategoryExpense>[];
  for (final e in byCat.entries) {
    Category? c;
    for (final cc in cats) {
      if (cc.id == e.key) {
        c = cc;
        break;
      }
    }
    out.add(CategoryExpense(
      categoryId: e.key,
      name: c?.name ?? '未分类',
      color: c?.color ?? 0xFFA1A1AA,
      amount: e.value,
    ));
  }
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
});

/// Top 10 支出单笔(从大到小,按当前时间窗)
final topExpensesProvider = FutureProvider<List<Transaction>>((ref) async {
  final w = ref.watch(statsWindowProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..where((t) =>
            t.occurredAt.isBetweenValues(w.start, w.end) &
            t.type.equals('expense'))
        ..orderBy([(t) => OrderingTerm.desc(t.amount)])
        ..limit(10))
      .get();
});

class MonthlyTrend {
  const MonthlyTrend({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });
  final int year;
  final int month;
  final double income;
  final double expense;
}

/// 过去 12 个月(含本月)的收入/支出趋势
final monthlyTrendProvider = FutureProvider<List<MonthlyTrend>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 11, 1);
  final txs = await (db.select(db.transactions)
        ..where((t) => t.occurredAt.isBiggerOrEqualValue(start)))
      .get();

  final byMonth = <String, MonthlyTrend>{};
  for (final t in txs) {
    final key = '${t.occurredAt.year}-${t.occurredAt.month}';
    final cur = byMonth[key] ??
        MonthlyTrend(
          year: t.occurredAt.year,
          month: t.occurredAt.month,
          income: 0,
          expense: 0,
        );
    final income = cur.income + (t.type == 'income' ? t.amount : 0);
    final expense = cur.expense + (t.type == 'expense' ? t.amount : 0);
    byMonth[key] = MonthlyTrend(
      year: cur.year,
      month: cur.month,
      income: income,
      expense: expense,
    );
  }

  final out = <MonthlyTrend>[];
  for (int i = 0; i < 12; i++) {
    final m = DateTime(now.year, now.month - 11 + i, 1);
    final key = '${m.year}-${m.month}';
    out.add(byMonth[key] ??
        MonthlyTrend(year: m.year, month: m.month, income: 0, expense: 0));
  }
  return out;
});
