// lib/features/stats/application/stats_providers.dart
// 报表数据 Provider:时间范围 / 分类支出汇总 / 12 月趋势
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../ledger/application/transactions_providers.dart';

/// 2026-10-11 redesign:去 "全部" 段(默认行为 = 本月,无需"全部"显式选择)
enum StatsRange { thisMonth, thisYear }

/// 报表的"视角"——按内容维度切,跟时间维度 (StatsRange) 正交
///   expense → 收支视角(CategoryPie + TopExpenses + MonthlyTrend + BudgetOverview)
///   assets  → 资产视角(2026-10-11 预留;页面内容先留空等后续)
/// 2026-10-12 P5 commit 简化:删 income 段(收入结构简单,不需要独立视角;收入分布
/// 跟支出视角合在一起,通过分类饼图 type filter 区分)。
enum StatsView { expense, assets }

final statsRangeProvider = StateProvider<StatsRange>(
  (_) => StatsRange.thisMonth,
);

/// 当前报表视角(收支 / 资产)
final statsViewProvider = StateProvider<StatsView>((_) => StatsView.expense);

/// 自定义月份(仅 StatsRange.thisMonth 时生效)
/// null = 本月,有值 = 选中的具体某月(年-月);等于当前年+月时也归一为"本月"
final statsCustomMonthProvider = StateProvider<({int year, int month})?>(
  (_) => null,
);

/// 自定义年份(仅 StatsRange.thisYear 时生效)
/// null = 本年,有值 = 选中的某年;等于当前年时归一为"本年"
final statsCustomYearProvider = StateProvider<int?>((_) => null);

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
      final m = ref.watch(statsCustomMonthProvider);
      final year = m?.year ?? now.year;
      final month = m?.month ?? now.month;
      return StatsTimeWindow(
        DateTime(year, month, 1),
        DateTime(year, month + 1, 1).subtract(const Duration(seconds: 1)),
      );
    case StatsRange.thisYear:
      final y = ref.watch(statsCustomYearProvider) ?? now.year;
      return StatsTimeWindow(
        DateTime(y, 1, 1),
        DateTime(y + 1, 1, 1).subtract(const Duration(seconds: 1)),
      );
  }
});

/// 当前时间窗内的全部流水
final statsTransactionsProvider = FutureProvider<List<Transaction>>((
  ref,
) async {
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
final expenseByCategoryProvider = FutureProvider<List<CategoryExpense>>((
  ref,
) async {
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
    out.add(
      CategoryExpense(
        categoryId: e.key,
        name: c?.name ?? '未分类',
        color: c?.color ?? 0xFFA1A1AA,
        amount: e.value,
      ),
    );
  }
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
});

/// Top 10 支出单笔(从大到小,按当前时间窗)
final topExpensesProvider = FutureProvider<List<Transaction>>((ref) async {
  final w = ref.watch(statsWindowProvider);
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
        ..where(
          (t) =>
              t.occurredAt.isBetweenValues(w.start, w.end) &
              t.type.equals('expense'),
        )
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

/// 每日支出聚合(用于本月维度的"按天柱状图")
/// 2026-10-12 加(commit 73 配套):
///   statsRange = thisMonth 时,MonthlyTrendChart 内部改用这个 provider 看 daily bar。
///   范围:statsWindowProvider.start 至 statsWindowProvider.end 之间所有支出,
///   按 day-of-month 聚合成 `List<DailyExpense>`,day 从 1 到当月最后一天。
///   当月有支出(days 1..today)直接算;未来天(days today+1..lastDay)默认 0。
class DailyExpense {
  const DailyExpense({required this.day, required this.expense});
  final int day;
  final double expense;
}

final dailyExpenseTrendProvider = FutureProvider<List<DailyExpense>>((
  ref,
) async {
  final w = ref.watch(statsWindowProvider);
  final db = ref.watch(databaseProvider);
  final txs =
      await (db.select(db.transactions)..where(
            (t) =>
                t.occurredAt.isBetweenValues(w.start, w.end) &
                t.type.equals('expense'),
          ))
          .get();

  // 按 day-of-month 聚合(假设 statsWindowProvider 在 thisMonth 模式时
  // w.start.month == w.end.month,所有 tx 同月,day 取 occurredAt.day)
  final byDay = <int, double>{};
  for (final t in txs) {
    byDay[t.occurredAt.day] = (byDay[t.occurredAt.day] ?? 0) + t.amount;
  }

  // 当月总天数:DateTime(y, m+1, 0).day 是 month m 的最后一天
  final lastDay = DateTime(w.start.year, w.start.month + 1, 0).day;

  final out = <DailyExpense>[];
  for (var i = 1; i <= lastDay; i++) {
    out.add(DailyExpense(day: i, expense: byDay[i] ?? 0));
  }
  return out;
});

/// 过去 12 个月(含本月)的收入/支出趋势
final monthlyTrendProvider = FutureProvider<List<MonthlyTrend>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 11, 1);
  final txs = await (db.select(
    db.transactions,
  )..where((t) => t.occurredAt.isBiggerOrEqualValue(start))).get();

  final byMonth = <String, MonthlyTrend>{};
  for (final t in txs) {
    final key = '${t.occurredAt.year}-${t.occurredAt.month}';
    final cur =
        byMonth[key] ??
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
    out.add(
      byMonth[key] ??
          MonthlyTrend(year: m.year, month: m.month, income: 0, expense: 0),
    );
  }
  return out;
});

/// 当年 1-12 月的支出趋势(本年维度柱状图用)
/// 2026-10-12 加(commit 78):user 反馈"本年不要近 12 个月,只要当年 1-12 月"
/// + "只需要支出,为什么还会有红黄两条柱子的"
///   - 之前 monthlyTrendProvider 返 12 月数据但含 income,本年维度 BarChart 显示
///     grouped 双柱(红支出 + 金收入)
///   - 改为只算支出,返 12 行(1..12 月),不再有 income 维度
class YearlyExpense {
  const YearlyExpense({required this.month, required this.expense});
  final int month;
  final double expense;
}

final yearlyExpenseTrendProvider = FutureProvider<List<YearlyExpense>>((
  ref,
) async {
  // 取本年的"自定义年份"(statsCustomYearProvider)或当前年
  final year = ref.watch(statsCustomYearProvider) ?? DateTime.now().year;
  final db = ref.watch(databaseProvider);
  final start = DateTime(year, 1, 1);
  final end = DateTime(year + 1, 1, 1).subtract(const Duration(seconds: 1));

  final txs =
      await (db.select(db.transactions)..where(
            (t) =>
                t.occurredAt.isBetweenValues(start, end) &
                t.type.equals('expense'),
          ))
          .get();

  final byMonth = <int, double>{};
  for (final t in txs) {
    byMonth[t.occurredAt.month] = (byMonth[t.occurredAt.month] ?? 0) + t.amount;
  }

  // 强制 12 行(1..12 月),没数据的月 expense = 0
  return List.generate(
    12,
    (i) => YearlyExpense(month: i + 1, expense: byMonth[i + 1] ?? 0),
  );
});

/// 2026-10-12 P5 commit 加:同比箭头 + 百分比(本月 vs 上月)
///   - 只在 StatsRange.thisMonth 时计算,本年维度 return MonthlyYoY.empty()
///   - 3 个字段(收入/支出/结余)各自 null = 不显示同比(curr / prev 都为 0)
///   - 上月为 0 时用绝对值(±¥X.XX),不为零时用百分比(+X.X%)
///
/// 边界:
///   - 本月 1 月 → 上月 = 去年 12 月(DateTime(y, m-1, 1) 自动跨年)
///   - 上月 0 + 本月 0 → null(全 0 没意义)
///   - 上月 0 + 本月非 0 → 绝对值 ±¥X.XX,isUp 按本月正负
class YoYDelta {
  const YoYDelta({required this.isUp, required this.text});

  /// 趋势方向:true = 上升(本月上月多 / 绝对值正),false = 下降
  final bool isUp;

  /// 显示文本:百分比("+12.5%"/"-3.2%")或绝对值("±¥100")
  final String text;
}

class MonthlyYoY {
  const MonthlyYoY({this.income, this.expense, this.balance});
  final YoYDelta? income;
  final YoYDelta? expense;
  final YoYDelta? balance;

  static const empty = MonthlyYoY();
}

final monthlyYoYProvider = FutureProvider<MonthlyYoY>((ref) async {
  final range = ref.watch(statsRangeProvider);
  if (range != StatsRange.thisMonth) {
    // 本年维度没有"同比上一整年"概念(commit 73 已弃用 yearly YoY)
    return MonthlyYoY.empty;
  }
  final w = ref.watch(statsWindowProvider);
  // 上月窗口:本月 1 日前推 1 秒 → 上月最后一天 → 推到上月 1 日
  final prevEnd = w.start.subtract(const Duration(seconds: 1));
  final prevStart = DateTime(prevEnd.year, prevEnd.month, 1);

  final db = ref.watch(databaseProvider);
  Future<StatsSummary> summary(DateTime start, DateTime end) async {
    final txs = await (db.select(
      db.transactions,
    )..where((t) => t.occurredAt.isBetweenValues(start, end))).get();
    double income = 0, expense = 0;
    for (final t in txs) {
      if (t.type == 'income') income += t.amount;
      if (t.type == 'expense') expense += t.amount;
    }
    return StatsSummary(income: income, expense: expense);
  }

  final curr = await summary(w.start, w.end);
  final prev = await summary(prevStart, prevEnd);

  YoYDelta? yoy(double a, double b) {
    if (a == 0 && b == 0) return null;
    if (b == 0) {
      // 上月 0 → 绝对值差(走百分比会让显示 "Infinity%",不可读)
      final diff = a.abs();
      return YoYDelta(
        isUp: a > 0,
        text: '±¥${Formatters.amount(diff, withUnit: false)}',
      );
    }
    final pct = (a - b) / b * 100;
    return YoYDelta(
      isUp: pct > 0,
      text: '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
    );
  }

  return MonthlyYoY(
    income: yoy(curr.income, prev.income),
    expense: yoy(curr.expense, prev.expense),
    balance: yoy(curr.balance, prev.balance),
  );
});
