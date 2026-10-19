// lib/core/utils/excluded_from_totals.dart
// 流水"不计入汇总"判断 + id 集合 provider
//
// 2026-10-16 D64.78 抽:同一规则"投资 cat + source asset includeInTransactions=false
//   → 不计入月度"在 3 处复制(monthSummaryProvider / transaction_tile
//   isExcludeFromTotals / _DaySection),改一处必漏改其它处,
//   抽此 helper + provider 3 处共用
//
// 设计要点:
//   - id 集合预计算(provider 一次算,3 处 watch 同一份),流水 1k+ 笔时不重复 filter
//   - 纯函数 isExcludedFromTotals(Transaction, ids) 给 UI / 汇总 provider 用
//   - 业务规则只此 1 处定义,跟 memory "D18 '不计入汇总' ≠ '隐藏'" 一致:
//     流水页面仍显示所有 record(可编辑/删除),只是不进月度统计
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ledger/application/transactions_providers.dart';
import '../database/app_database.dart';
import 'asset_balance_provider.dart';

/// 不计入月度/日结汇总的 id 集合(投资 cat id + 排除账户 id + 余额调整 cat id)
///   - 投资 record(cat.type='investment')→ 永远不计入(P18 user 决定)
///   - 余额调整 record(cat.type='adjust')→ 不计入(D74 — D73 把 type 改成
///     'income' 让 delta 公式方向对了,但 income 默认会被 monthSummaryProvider
///     算入月度收入,所以这里把"余额调整"cat 也加进排除集合,跟 D18 "不计入汇总
///     ≠ 隐藏" 原则一致:流水 tile 仍显示可管理,只是不进月度)
///   - source asset.includeInTransactions=false → 不计入(user 在资产页关开关)
///   - 跟 D18 "不计入汇总 ≠ 隐藏" 一致,流水 tile 仍显示
class ExcludedFromTotalsIds {
  const ExcludedFromTotalsIds({
    required this.investmentCategoryIds,
    required this.adjustCategoryIds,
    required this.excludeAccountIds,
  });
  final Set<int> investmentCategoryIds;
  final Set<int> adjustCategoryIds;
  final Set<int> excludeAccountIds;

  static const empty = ExcludedFromTotalsIds(
    investmentCategoryIds: <int>{},
    adjustCategoryIds: <int>{},
    excludeAccountIds: <int>{},
  );
}

final excludedFromTotalsIdsProvider =
    Provider<ExcludedFromTotalsIds>((ref) {
  final cats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
  final assets = ref.watch(allAssetsProvider).valueOrNull ?? const [];
  return ExcludedFromTotalsIds(
    investmentCategoryIds: cats
        .where((c) => c.type == 'investment')
        .map((c) => c.id)
        .toSet(),
    adjustCategoryIds: cats
        .where((c) => c.type == 'adjust')
        .map((c) => c.id)
        .toSet(),
    excludeAccountIds: assets
        .where((a) => !a.includeInTransactions)
        .map((a) => a.id)
        .toSet(),
  );
});

/// 纯函数:判断单笔流水是否不计入月度/日结汇总
///   - 用法:UI / 汇总 provider 都调此 1 处,改口径只改这里
///   - 1k 笔流水下 O(1) per-record,3 处共用避免各自 filter
bool isExcludedFromTotals(Transaction t, ExcludedFromTotalsIds ids) {
  if (ids.investmentCategoryIds.contains(t.categoryId)) return true;
  if (ids.adjustCategoryIds.contains(t.categoryId)) return true; // D74 加
  if (ids.excludeAccountIds.contains(t.accountId)) return true;
  return false;
}
