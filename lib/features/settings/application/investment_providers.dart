// lib/features/settings/application/investment_providers.dart
// 资产页"投资情况"dashboard 数据 providers
//
// 2026-10-16 D64.68 加:
//   - user 反馈"资产页面开始增加投资的投入和收益情况的图"
//   - 数据源:transactions JOIN categories,filter
//     cat.type='investment'(投资投入 / 投资收益两个系统分类)
//   - 投入 = tx.type='balance' + cat.type='investment'(现金 → 投资账户的调拨,
//     或投资账户之间的调拨,都算"钱流入投资生态")
//   - 收益 = tx.type='income'  + cat.type='investment'(投资账户自身收入)
//
// 累计净收益 = sum(收益) - sum(投入) — 反映"投资活动整体盈亏"
//
// 本年按月:12 行(year 0-11 month 1-12),missing 月补 0
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/providers.dart';
import '../../ledger/application/transactions_providers.dart';

/// 单月投资数据(投入 + 收益,本年 12 月)
class MonthlyInvestment {
  const MonthlyInvestment({
    required this.year,
    required this.month,
    required this.invested,
    required this.returned,
  });
  final int year;
  final int month;
  final double invested;
  final double returned;

  double get net => returned - invested;
}

/// 2026-10-16 D64.88 加:本年投资活动汇总(返回 widget 一次拿全 4 个聚合)
///   - monthly:12 月(给 _YearlyBars 12 柱)
///   - investedYTD / returnedYTD:本年累计投入 / 收益(给 _YearTotals 底部合计)
///   - maxMonthlyValue:12 月 max(invested, returned)(给 _YearlyBars Y 轴 scale)
///   - 一次 fold 算 3 个聚合(之前 _YearTotals 跟 _YearlyBars 各 fold 一次,O(N) 重复)
///   - 之前 _YearTotals 算 invested/returned/net,_YearlyBars 算 maxVal,各 fold 一次
///     → 改汇总后 1 次 fold,3 个 widget 读字段 0 额外算
///
/// 2026-10-16 D65.3 加:`minMonthlyValue`(12 月 min(invested, returned),可负)
///   - 投资亏损 record 出现时,returned < 0,需要负轴才能完整显示柱条
///   - 跟 AnimatedBarChart.minVal(D64.21c)配套:传 < 0 启用 0 线突出 + 圆角方向
class InvestmentYearSummary {
  const InvestmentYearSummary({
    required this.monthly,
    required this.investedYTD,
    required this.returnedYTD,
    required this.maxMonthlyValue,
    required this.minMonthlyValue,
  });
  final List<MonthlyInvestment> monthly;
  final double investedYTD;
  final double returnedYTD;
  double get netYTD => returnedYTD - investedYTD;
  final double maxMonthlyValue; // 12 月 max(invested, returned),Y 轴 scale
  final double minMonthlyValue; // 12 月 min(invested, returned),Y 轴 scale,可负
}

/// 本年(过去 12 月)投资数据
///   - 横轴:月 1-12
///   - 双柱:invested(投入) + returned(收益)
/// 2026-10-16 D64.88 改:返 InvestmentYearSummary 元组,3 个 widget 一次拿全聚合
final investmentMonthlyProvider =
    FutureProvider<InvestmentYearSummary>((ref) async {
  final now = DateTime.now();
  final year = now.year;
  // 起始:本年 1 月 1 日 00:00:00
  final start = DateTime(year, 1, 1);
  // 结束:下年 1 月 1 日 00:00:00(下年的 1 月 1 日 = 本年 12 月 31 日 + 1 天)
  final end = DateTime(year + 1, 1, 1);

  final db = ref.watch(databaseProvider);
  // 只拉 cat.type='investment' 的 tx(投资投入 / 投资收益),用 IN subquery 限定
  final txs = await (db.select(db.transactions)
        ..where((t) => t.occurredAt.isBetweenValues(start, end)))
      .get();
  final cats = await ref.watch(allCategoriesProvider.future);
  final investCatIds = cats
      .where((c) => c.type == 'investment')
      .map((c) => c.id)
      .toSet();
  if (investCatIds.isEmpty) {
    // 没投资分类 → 12 月全 0 + 4 个聚合 0
    return const InvestmentYearSummary(
      monthly: [],
      investedYTD: 0,
      returnedYTD: 0,
      maxMonthlyValue: 0,
      minMonthlyValue: 0,
    );
  }

  // 累加到月(单次 fold 算 monthly + investedYTD + returnedYTD + max)
  final invested = List<double>.filled(12, 0);
  final returned = List<double>.filled(12, 0);
  for (final t in txs) {
    if (!investCatIds.contains(t.categoryId)) continue;
    final dt = t.occurredAt;
    if (dt.year != year) continue;
    final mIdx = dt.month - 1;
    if (t.type == 'balance') {
      invested[mIdx] += t.amount;
    } else if (t.type == 'income') {
      returned[mIdx] += t.amount;
    }
  }
  final monthly = [
    for (var i = 0; i < 12; i++)
      MonthlyInvestment(
        year: year,
        month: i + 1,
        invested: invested[i],
        returned: returned[i],
      ),
  ];
  // D64.88:3 个 widget 各 fold 一次 → 这里一次算 3 聚合,widget 读字段 0 额外算
  // 2026-10-16 D65.3:扩展为 4 聚合(加 minMonthlyValue),D64.88 思路延续
  final investedYTD = monthly.fold<double>(0, (s, m) => s + m.invested);
  final returnedYTD = monthly.fold<double>(0, (s, m) => s + m.returned);
  final maxMonthlyValue = monthly.fold<double>(0, (a, m) {
    final mMax = m.invested > m.returned ? m.invested : m.returned;
    return a > mMax ? a : mMax;
  });
  // D65.3:min 初始用 maxMonthlyValue(全 0 月时不会误判成 min=0),逐月取 min
  final minMonthlyValue = maxMonthlyValue == 0
      ? 0.0
      : monthly.fold<double>(maxMonthlyValue, (a, m) {
          final mMin = m.invested < m.returned ? m.invested : m.returned;
          return a < mMin ? a : mMin;
        });
  return InvestmentYearSummary(
    monthly: monthly,
    investedYTD: investedYTD,
    returnedYTD: returnedYTD,
    maxMonthlyValue: maxMonthlyValue,
    minMonthlyValue: minMonthlyValue,
  );
});

/// 累计净收益(全时间,所有投资活动)
///   - 反映"投资整体盈亏":正 = 累计赚的比投的多;负 = 累计投的比赚的多
/// 2026-10-16 D64.81 改:走 transaction_repository.investmentAggregated()
///   - 之前 select 全表 transactions + Dart 端 filter,1w+ 笔时首次 build 200ms+
///   - 改 SQL JOIN categories + GROUP BY tx.type 一次性算 invested/returned 2 个 double
///   - 跟 asset_repository.balanceDeltaByAssetId 6 select 模式同 D49 教训,
///     业务层不接触 DAO,Repository 层做 SQL 聚合
final investmentNetTotalProvider = FutureProvider<double>((ref) async {
  final repo = ref.watch(transactionRepositoryProvider);
  final agg = await repo.investmentAggregated();
  return agg.net;
});
