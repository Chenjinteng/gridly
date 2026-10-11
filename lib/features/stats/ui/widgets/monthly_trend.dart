// lib/features/stats/ui/widgets/monthly_trend.dart
// 过去 12 个月 收入/支出 折线图
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class MonthlyTrend extends ConsumerWidget {
  const MonthlyTrend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(monthlyTrendProvider);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.0, // 全卡片统一:0.5 → 1.0
        ),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '近 12 月趋势',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s3),
          trendAsync.when(
            data: (data) {
              if (data.every((d) => d.income == 0 && d.expense == 0)) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
                  child: Center(
                    child: Text(
                      '近 12 月暂无数据',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              // 单图 Y 轴单位策略:整图要么全走"元"、要么全走"万",不混排。
              //   maxVal < wanThreshold → 整轴走元(保留精度,"50,000.00" 跟 cell 一致)
              //   maxVal ≥ wanThreshold → 整轴强制走万 mode(否则会出 "150.00万 / 50,000.00 / 0.00"
              //                  这种跨阈值混排,视觉割裂)
              // 0 baseline 在大图里显示成 "0.00万" 是为了跟其他 tick 同单位模式,
              // "看起来怪但一致" 比"自然切但割裂"优先。
              final maxVal = data
                  .map((d) =>
                      d.income > d.expense ? d.income : d.expense)
                  .fold<double>(0, (a, b) => a > b ? a : b);
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              return SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: data
                            .asMap()
                            .entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value.income))
                            .toList(),
                        isCurved: true,
                        color: AppBrand.gold,
                        barWidth: 2,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppBrand.gold.withValues(alpha: 0.08),
                        ),
                      ),
                      LineChartBarData(
                        spots: data
                            .asMap()
                            .entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value.expense))
                            .toList(),
                        isCurved: true,
                        color: AppStatus.error,
                        barWidth: 2,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppStatus.error.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
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
                          // Y 轴预留宽度:数字经 Formatters.amount 走万元 mode,
                          // "999.99万" ≈ 7 字符 + 千分位逗号,28 像素够装。
                          // 之前 48 是给 raw "9999999" 这种 7 位整数留的,现在不需要
                          reservedSize: 44,
                          getTitlesWidget: (v, meta) => Text(
                            // 单图单位一致性:
                            //   - chartNeedsWan=true → 一律按万元输出(含 0 → "0.00万"),
                            //     避免 maxY 跨 100万阈值时 "150.00万 / 50,000.00 / 0.00"
                            //     混排
                            //   - chartNeedsWan=false → 走标准 Formatters 行为
                            // cap 时仍返回 "999.99万+",chart 上看到 + 提示截断
                            Formatters.amount(v, forceWan: chartNeedsWan),
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppGray.g600,
                            ),
                            // 防御性关闭 wrap:即使未来真出现 8+ 位数字也不会竖切,
                            // 溢出部分借 overflow.visible 延伸到绘图区边缘(sideTitles 会裁掉,
                            // 但总比换行成两行好看)
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 2,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= data.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${data[i].month}月',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppGray.g600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => AppBrand.ink,
                        // 自定义 tooltip 内容,避免 fl_chart 默认
                        // double.toString() 暴露浮点尾数(如 25420.7600000002)
                        getTooltipItems: (touchedSpots) => touchedSpots
                            .map(
                              (s) => LineTooltipItem(
                                '¥${Formatters.amount(s.y)}',
                                TextStyle(
                                  color: s.bar.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            )
                            .toList(),
                      ),
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
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: const [
              _LegendDot(color: AppBrand.gold, label: '收入'),
              SizedBox(width: AppSpacing.s3),
              _LegendDot(color: AppStatus.error, label: '支出'),
            ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppGray.g600),
        ),
      ],
    );
  }
}
