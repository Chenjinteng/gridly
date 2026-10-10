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

// ============================================================
// 流水筛选(流水页用)—— 类型 / 月份 / 分类 / 搜索关键字
// ============================================================

/// 类型筛选:'all' / 'expense' / 'income'
final ledgerTypeFilterProvider = StateProvider<String>((ref) => 'all');

/// 月份筛选:null = 全部,否则用 `year*100 + month` 做 key(如 202610 = 2026 年 10 月)
final ledgerMonthFilterProvider = StateProvider<int?>((ref) => null);

/// 分类筛选:空 Set = 全部,非空 = 仅命中任一 id 的分类(多选 OR 关系)
final ledgerCategoryFilterProvider = StateProvider<Set<int>>((ref) => <int>{});

/// 搜索关键字:匹配 note(备注)和分类名
final ledgerSearchQueryProvider = StateProvider<String>((ref) => '');

/// 应用所有筛选后按日分组的结果
/// 一次取所有流水,在内存里过滤 + 重新分组(数据量小,响应快)
final filteredTransactionsByDayProvider =
    FutureProvider<Map<DateTime, List<Transaction>>>((ref) async {
  final typeFilter = ref.watch(ledgerTypeFilterProvider);
  final monthFilter = ref.watch(ledgerMonthFilterProvider);
  final categoryFilter = ref.watch(ledgerCategoryFilterProvider);
  final query = ref.watch(ledgerSearchQueryProvider).trim().toLowerCase();

  // 取分类一次,用来按分类名匹配搜索关键字
  final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
  final queryCatIds = query.isEmpty
      ? <int>{}
      : allCats
          .where((c) => c.name.toLowerCase().contains(query))
          .map((c) => c.id)
          .toSet();

  final all = await ref.watch(transactionRepositoryProvider).all();
  final filtered = all.where((t) {
    // 类型
    if (typeFilter != 'all' && t.type != typeFilter) return false;
    // 月份
    if (monthFilter != null) {
      final dt = t.occurredAt;
      if (dt.year * 100 + dt.month != monthFilter) return false;
    }
    // 分类(多选 OR:命中任一选中的 id)
    if (categoryFilter.isNotEmpty && !categoryFilter.contains(t.categoryId)) {
      return false;
    }
    // 搜索关键字(note 命中 或 分类名命中)
    if (query.isNotEmpty) {
      final noteHit = (t.note ?? '').toLowerCase().contains(query);
      final catHit = queryCatIds.contains(t.categoryId);
      if (!noteHit && !catHit) return false;
    }
    return true;
  });

  final map = <DateTime, List<Transaction>>{};
  for (final t in filtered) {
    final day = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
    map.putIfAbsent(day, () => []).add(t);
  }
  return map;
});
