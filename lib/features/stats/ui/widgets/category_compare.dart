// lib/features/stats/ui/widgets/category_compare.dart
// 报表第 5 张卡:本月 vs 上月 各类别支出对比
//   - 类别维度:每类 2 柱(本月 + 上月),看"哪类涨 / 哪类降"
//   - 跟 12 月月度趋势区别:monthlyTrendProvider 看时间维度(每月总额),这个看类别维度
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 取前 6 类按本月+上月合计从大到小,过小的隐藏避免柱子太挤
//
// 2026-10-15 D63 加
// 2026-10-15 D64 改:BarChart 业务用共享 `AnimatedBarChart`(`core/widgets/charts/`)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../application/stats_providers.dart';

class CategoryCompareChart extends ConsumerWidget {
  const CategoryCompareChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareAsync = ref.watch(categoryCompareProvider);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '类别对比',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: const [
                    _LegendDot(color: AppStatus.error, label: '本月'),
                    SizedBox(width: AppSpacing.s3),
                    _LegendDot(color: AppGray.g200, label: '上月'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          compareAsync.when(
            data: (data) {
              if (data.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final shown = data.take(6).toList();
              final maxVal = shown
                  .map(
                    (e) => e.currAmount > e.prevAmount
                        ? e.currAmount
                        : e.prevAmount,
                  )
                  .fold<double>(0, (a, b) => a > b ? a : b);
              if (maxVal == 0) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final maxY = maxVal * 1.15;
              final niceInterval = _niceInterval(maxY);
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: SizedBox(
                  height: 220,
                  child: AnimatedBarChart(
                    bars: [
                      for (final c in shown)
                        BarChartBar(
                          label: c.name,
                          value: c.currAmount,
                          secondaryValue: c.prevAmount,
                        ),
                    ],
                    maxY: maxY,
                    niceInterval: niceInterval,
                    chartNeedsWan: chartNeedsWan,
                    primaryColor: AppStatus.error, // 本月 红
                    secondaryColor: AppGray.g200, // 上月 浅灰
                    barWidth: 8, // 双柱,每柱略宽
                    barsSpace: 2, // 柱内间距
                    xLabelBuilder: (i, b) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        b.label,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    touchedLabelBuilder: (i, b) => b.label,
                    tooltipBuilder: (i, b) =>
                        '¥${Formatters.amount(shown[i].currAmount)}',
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.s3),
              child: Text(
                '加载失败:$e',
                style: const TextStyle(color: AppStatus.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppGray.g600)),
      ],
    );
  }
}

double _niceInterval(double maxY) {
  if (maxY <= 0) return 100;
  final v = maxY / 5;
  if (v <= 0) return 1;
  final exp = v.toString().split('.').first.length - 1;
  final n = _pow10(exp < 0 ? 0 : exp);
  final cands = [n.toDouble(), (2 * n).toDouble(), (5 * n).toDouble()];
  return cands.reduce((a, b) => (a - v).abs() < (b - v).abs() ? a : b);
}

int _pow10(int n) {
  int r = 1;
  for (int i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
