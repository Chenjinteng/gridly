// lib/features/stats/ui/widgets/category_compare.dart
// 报表第 5 张卡:本月 vs 上月 各类别支出对比
//   - 类别维度:每类 2 柱(本月 + 上月),看"哪类涨 / 哪类降"
//   - 跟 12 月月度趋势区别:monthlyTrendProvider 看时间维度(每月总额),这个看类别维度
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 取前 6 类按本月+上月合计从大到小,过小的隐藏避免柱子太挤
//
// 2026-10-15 D63 加:user 提议"还需要增加哪些视图" — 我推荐列表第 1 项,user 选了 4 个都做。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
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
                // 图例:本月/上月色块对照
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
              // 取前 6 类,避免柱子太多挤
              final shown = data.take(6).toList();
              // maxY = 本月 / 上月 最大值,再 +10% padding 防止顶到边
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
              // 自适应单位:本月总额 ≥ 100 万时 Y 轴用"万"
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              // Y 轴 niceInterval — 按 maxY 估
              final niceInterval = _niceInterval(maxY);
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      minY: 0,
                      barTouchData: BarTouchData(
                        enabled: false, // 简单版,关 tooltip
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: niceInterval,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: theme.colorScheme.outlineVariant,
                          strokeWidth: 0.5,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            interval: niceInterval,
                            getTitlesWidget: (value, _) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  chartNeedsWan
                                      ? '${(value / 10000).toStringAsFixed(value >= 10000 ? 0 : 1)}万'
                                      : value.toInt().toString(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppGray.g600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, _) {
                              final i = value.toInt();
                              if (i < 0 || i >= shown.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  shown[i].name,
                                  style: const TextStyle(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (int i = 0; i < shown.length; i++)
                          BarChartGroupData(
                            x: i,
                            barsSpace: 2,
                            barRods: [
                              BarChartRodData(
                                toY: shown[i].currAmount,
                                color: AppStatus.error,
                                width: 8,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              BarChartRodData(
                                toY: shown[i].prevAmount,
                                color: AppGray.g200,
                                width: 8,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ],
                          ),
                      ],
                    ),
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

/// Y 轴 nice interval(简单取整 50/100/500/1000/...)
double _niceInterval(double maxY) {
  if (maxY <= 0) return 100;
  final mag = _magnitude(maxY / 5);
  return mag;
}

double _magnitude(double v) {
  if (v <= 0) return 1;
  final exp = (v.abs() == 0) ? 0 : (v.abs().toString().length - 1);
  // 简化:取 1, 2, 5 × 10^n 中最接近 v 的
  final n = _pow10(exp - 1);
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
