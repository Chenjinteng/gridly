// lib/features/stats/ui/widgets/expense_by_asset.dart
// 报表第 8 张卡:按支付账户/资产支出分布(类似 category_pie 但按账户)
//   - user 多账户场景:看现金账户 / 各信用卡 / 花呗 各花了多少
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 还款(现金→债务调拨)accountId 是 source 现金账户,归到现金账户
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 加 viewport-aware 圆环入场动画
// 2026-10-15 D64.2 改:用 `ChartCard` + `PieChartCard`,移除重复的卡片容器 / 圆环 + 图例实现
// 2026-10-15 D64.6 改:颜色用固定 6 色 palette 按 index 取,不读 asset.color。
//   原读 asset.color 时 3 个账户可能同色(用户创建时未刻意区分),圆环 + 图例
//   全绿看不出区别。固定 palette 保证视觉区分(user 反馈"随机颜色也行")。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../application/stats_providers.dart';

class ExpenseByAssetChart extends ConsumerWidget {
  const ExpenseByAssetChart({super.key});

  /// 2026-10-15 D64.6:固定 6 色 palette,按 index 取,>6 时循环。
  /// 选色:teal / orange / blue / pink / purple / cyan 6 色相互区分。
  /// (复用 core palette AppBrand/AppStatus/AppCategory 已有色 token)
  static const _palette = <int>[
    0xFF14B8A6, // AppBrand.teal
    0xFFF59E0B, // AppStatus.warning
    0xFF3B82F6, // AppStatus.info
    0xFFEC4899, // AppCategory.shopping (pink)
    0xFF8B5CF6, // AppCategory.education (purple)
    0xFF06B6D4, // AppCategory.telecom (cyan)
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(expenseByAssetProvider);
    return assetsAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        return PieChartCard(
          title: '支付账户',
          // 2026-10-15 D64.6:不走 buildPieChartItems(其 colorOf 没有 index 参数),
          // 直接 map:按 index 取 palette 色,保证 N 个账户视觉区分。
          items: [
            for (int i = 0; i < data.length; i++)
              PieChartLegendItem(
                name: data[i].name,
                value: data[i].amount,
                color: _palette[i % _palette.length],
              ),
          ],
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
