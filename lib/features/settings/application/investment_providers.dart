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

/// 本年(过去 12 月)投资数据
///   - 横轴:月 1-12
///   - 双柱:invested(投入) + returned(收益)
final investmentMonthlyProvider = FutureProvider<List<MonthlyInvestment>>((ref) async {
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
    // 没投资分类 → 12 月全 0
    return List.generate(
      12,
      (i) => MonthlyInvestment(year: year, month: i + 1, invested: 0, returned: 0),
    );
  }

  // 累加到月
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
  return [
    for (var i = 0; i < 12; i++)
      MonthlyInvestment(
        year: year,
        month: i + 1,
        invested: invested[i],
        returned: returned[i],
      ),
  ];
});

/// 累计净收益(全时间,所有投资活动)
///   - 反映"投资整体盈亏":正 = 累计赚的比投的多;负 = 累计投的比赚的多
final investmentNetTotalProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final txs = await db.select(db.transactions).get();
  final cats = await ref.watch(allCategoriesProvider.future);
  final investCatIds = cats
      .where((c) => c.type == 'investment')
      .map((c) => c.id)
      .toSet();
  if (investCatIds.isEmpty) return 0;
  double invested = 0;
  double returned = 0;
  for (final t in txs) {
    if (!investCatIds.contains(t.categoryId)) continue;
    if (t.type == 'balance') {
      invested += t.amount;
    } else if (t.type == 'income') {
      returned += t.amount;
    }
  }
  return returned - invested;
});
