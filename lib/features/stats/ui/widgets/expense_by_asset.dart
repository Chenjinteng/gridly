// lib/features/stats/ui/widgets/expense_by_asset.dart
// 报表第 8 张卡:按支付账户/资产支出分布(类似 category_pie 但按账户)
//   - user 多账户场景:看现金账户 / 各信用卡 / 花呗 各花了多少
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 还款(现金→债务调拨)accountId 是 source 现金账户,归到现金账户
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 加 viewport-aware 圆环入场动画
// 2026-10-15 D64.2 改:用 `ChartCard` + `PieChartCard`,移除重复的卡片容器 / 圆环 + 图例实现
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../application/stats_providers.dart';

class ExpenseByAssetChart extends ConsumerWidget {
  const ExpenseByAssetChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(expenseByAssetProvider);
    return assetsAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        return PieChartCard(
          title: '支付账户',
          items: buildPieChartItems<ExpenseByAsset>(
            data,
            nameOf: (e) => e.name,
            valueOf: (e) => e.amount,
            colorOf: (e) => e.color,
          ),
          total: total,
          centerLabel: '总支出',
          centerValueText: '¥${Formatters.amount(total)}',
          totalLabel: data.isEmpty ? null : '共 ¥${Formatters.amount(total)}',
        );
      },
      loading: () => PieChartCard(
        title: '支付账户',
        items: const [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '¥0',
        totalLabel: null,
      ),
      error: (e, _) => PieChartCard(
        title: '支付账户',
        items: const [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '加载失败',
        totalLabel: null,
      ),
    );
  }
}
