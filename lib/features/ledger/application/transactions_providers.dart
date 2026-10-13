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
    end: DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(seconds: 1)),
  );
});

/// 当前月份的所有流水(按时间倒序)
final monthTransactionsProvider = FutureProvider<List<Transaction>>((
  ref,
) async {
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
final categoriesByTypeProvider = FutureProvider.family<List<Category>, String>((
  ref,
  type,
) async {
  return ref.watch(categoryRepositoryProvider).byType(type);
});

/// 所有流水按日分组
final allTransactionsByDayProvider =
    FutureProvider<Map<DateTime, List<Transaction>>>((ref) async {
      return ref.watch(transactionRepositoryProvider).groupedByDay();
    });

/// 按 id 取单笔流水(2026-10-11 新增:EditTransactionPage 全屏编辑路由用)
/// 找不到返回 null(被删除 / id 错误 / DB 异常),UI 层处理 fallback
final transactionByIdProvider = FutureProvider.family<Transaction?, int>((
  ref,
  id,
) async {
  return ref.watch(transactionRepositoryProvider).byId(id);
});

/// 当前左滑开着的 tile id(2026-10-11 UAT 加):
/// null = 没有 tile 开着,任何 tile 都关着
/// 非 null = 只有 id 对应的那个 tile 是开的,其它都得收回
///
/// LedgerPage 的全局 tap handler 会把它清成 null,
/// 实现"点屏幕任何地方,正在开的 tile 自动收回"。
/// 保证同时只有一个 tile 开着(避免视觉混乱)。
final openSwipeTileIdProvider = StateProvider<int?>((ref) => null);

// ============================================================
// 流水筛选(流水页用)—— 类型 / 月份 / 分类 / 搜索关键字
// ============================================================

/// 类型筛选:空 Set = 全部,非空 = 仅命中任一 type 的流水(多选 OR 关系)
/// 2026-10-13 改:从 `String`('all'/'expense'/'income') 改成 `Set<String>`,
///   支持高级筛选全屏 inline 多选(in-page _FilterBar 单选 picker 仍走单选,
///   提交时设成单元素 Set 或空 Set)。
final ledgerTypeFilterProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// 月份筛选:空 Set = 全部,非空 = 仅命中任一月份的流水(多选 OR 关系)
/// 2026-10-13 改:从 `int?` 改成 `Set<int>`(key 仍是 year*100+month)
final ledgerMonthFilterProvider = StateProvider<Set<int>>((ref) => <int>{});

/// 分类筛选:空 Set = 全部,非空 = 仅命中任一 id 的分类(多选 OR 关系)
final ledgerCategoryFilterProvider = StateProvider<Set<int>>((ref) => <int>{});

/// 2026-10-12 P3 commit 加(后续被 P3 follow-up 删掉,P5 follow-up 重新加回):
///   资产 filter 入口在 AppBar 右上角 filter_alt 图标 → 推入 AdvancedFilterPage
///   高级筛选全屏页 + 4 条件 inline 多选
final ledgerAssetFilterProvider = StateProvider<Set<int>>((ref) => <int>{});

// 2026-10-12 P3 加的 ledgerAssetFilterProvider 在 P3 follow-up commit 删掉:
//   user 反馈"4 个筛选太多长了,按之前的来只占一行就行"
//   filter bar 回到 3 dropdown 单行布局(类型/月份/分类),资产 filter 不上 UI
//   资产显示仍通过 transaction_tile._AccountBadge(transaction 内 accountId 字段)

/// 搜索关键字:匹配 note(备注)和分类名
final ledgerSearchQueryProvider = StateProvider<String>((ref) => '');

/// 流水 / 月度汇总 / 报表 + 分类管理 等所有"依赖流水"的 provider 一起 invalidate
/// 写新流水 / 删流水 / 用户下拉刷新都调用这个,保证全 App 数据同步
/// 实现见 lib/core/utils/refresh_providers.dart 的 refreshAllData()
/// (为避免 ledger 模块反向依赖 stats 模块,helper 放在 core/utils/)

/// 应用所有筛选后按日分组的结果
/// 一次取所有流水,在内存里过滤 + 重新分组(数据量小,响应快)
/// 一次取所有流水,在内存里过滤 + 重新分组(数据量小,响应快)
final filteredTransactionsByDayProvider =
    FutureProvider<Map<DateTime, List<Transaction>>>((ref) async {
      final typeFilter = ref.watch(ledgerTypeFilterProvider);
      final monthFilter = ref.watch(ledgerMonthFilterProvider);
      final categoryFilter = ref.watch(ledgerCategoryFilterProvider);
      // 2026-10-12 P5 follow-up 加回:资产 filter
      final assetFilter = ref.watch(ledgerAssetFilterProvider);
      final query = ref.watch(ledgerSearchQueryProvider).trim().toLowerCase();

      // 取分类一次,用来按分类名匹配搜索关键字
      final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
      final queryCatIds = query.isEmpty
          ? <int>{}
          : allCats
                .where((c) => c.name.toLowerCase().contains(query))
                .map((c) => c.id)
                .toSet();
      // 2026-10-14 P18 修正:投资 record 默认在流水页面显示
      //   - user:"这些不计入流水的行为只是不计算,但是在流水页面还是要显示,
      //     不然就会无法对这些记录进行管理"
      //   - 之前 commit 4 默认隐藏 → 撤销,投资 record 正常显示在流水 tile 里
      //   - 不计入月度/日结汇总的过滤移到 monthSummaryProvider 和 _DaySection
      //     (基于 category.type='investment' 排除)

      final all = await ref.watch(transactionRepositoryProvider).all();
      final filtered = all.where((t) {
        // 类型(多选 OR:空 = 全部,非空 = 命中任一选中的 type)
        if (typeFilter.isNotEmpty && !typeFilter.contains(t.type)) {
          return false;
        }
        // 月份(多选 OR:空 = 全部,非空 = 命中任一选中的月份)
        if (monthFilter.isNotEmpty) {
          final dt = t.occurredAt;
          if (!monthFilter.contains(dt.year * 100 + dt.month)) return false;
        }
        // 分类(多选 OR:命中任一选中的 id)
        if (categoryFilter.isNotEmpty &&
            !categoryFilter.contains(t.categoryId)) {
          return false;
        }
        // 2026-10-12 P5 follow-up 加回:资产(多选 OR)
        if (assetFilter.isNotEmpty && !assetFilter.contains(t.accountId)) {
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
        final day = DateTime(
          t.occurredAt.year,
          t.occurredAt.month,
          t.occurredAt.day,
        );
        map.putIfAbsent(day, () => []).add(t);
      }
      return map;
    });

/// 2026-10-12 P3 加:按 id 取单个资产(给 transaction_tile 显示资产 icon 用)
///   family provider,assetId 作 key
final assetByIdProvider = FutureProvider.family<Asset?, int>((ref, id) async {
  return ref.watch(assetRepositoryProvider).byId(id);
});
