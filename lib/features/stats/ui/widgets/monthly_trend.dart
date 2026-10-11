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
        // 跟 Top 10 / CategoryPie / IncomePie 同色 = theme.colorScheme.surface
        // 之前用了 surfaceContainerLow,在卡片堆叠里显得"凹"进去一层;
        // 2026-10-11 UAT:"底色跟上面 Top 10 不一样"
        color: Theme.of(context).colorScheme.surface,
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
              // 2026-10-11 UAT 反馈:之前 maxY = maxVal * 1.15 时,fl_chart
              // 把 345,004.60 当成一个 tick 显示在纵坐标,看起来很丑。改成
              // "1/2/5 × 10^n" 模式挑一个整档 interval,maxY 圆整到下一档,
              // 这样 tick 是 0/100k/200k/300k/400k 这种整数,数据点 300k
              // 跟 top tick 400k 之间自然留一档空隙。
              final niceInterval = _pickNiceInterval(maxVal);
              final maxY = maxVal == 0 ? 1.0 : (maxVal / niceInterval).ceil() * niceInterval;
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
                        // 折线:Bezier 关掉。原因:用户的收入/支出都是绝对值,
                        // 数据从 0(或低)→ spike 时 Bezier 控制点会 overshoot,
                        // 在数据点之间出现"下凹"的伪下垂,跟语义不符。
                        // 改直折线,数据点之间走直线,无伪下垂
                        isCurved: false,
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
                        isCurved: false,
                        color: AppStatus.error,
                        barWidth: 2,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppStatus.error.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                    // minY 显式 0:收入/支出都是绝对值 >= 0,纵轴不允许负向,
                    // 防止 fl_chart 自适应时把曲线起点拉到负值区域
                    minY: 0,
                    maxY: maxY,
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
                          // 显式 interval(由 maxVal 推算的"1/2/5 × 10^n"档):
                          // 强制 tick 落在整数档位(0/100k/200k/300k/400k),
                          // 不会再出现 "345,004.60" 这种 maxY 实际值。
                          // 2026-10-11 UAT 反馈"只显示居间就行"。
                          interval: niceInterval,
                          getTitlesWidget: (v, meta) => Text(
                            // 单图单位一致性:
                            //   - chartNeedsWan=true → 一律按万元输出(含 0 → "0万"),
                            //     避免 maxY 跨 100万阈值时 "150万 / 50,000 / 0"
                            //     混排
                            //   - chartNeedsWan=false → 走标准 Formatters 行为
                            // cap 时仍返回 "999.99万+",chart 上看到 + 提示截断
                            // trimTrailingZeros:true → 整数值的 ".00" 后缀去掉
                            //   (2026-10-11 UAT:"300,000.00" 太冗,改 "300,000")
                            Formatters.amount(v, forceWan: chartNeedsWan, trimTrailingZeros: true),
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

/// 2026-10-01 加:按"1/2/5 × 10^n"模式挑一个整档 interval。
/// 让 Y 轴 tick 落在整数档位(0/100k/200k...),不会出现 "345,004.60"
/// 这种 maxY 实际值;同时 maxY 圆整到下一档,顶部自然留一档空隙,
/// 数据点不再叠 top label。
double _pickNiceInterval(double maxVal) {
  if (maxVal <= 0) return 1;
  // 数量级(10^n):maxVal 的整数位数 - 1
  final magnitude = _pow10((maxVal.abs().toString().split('.').first.length) - 1);
  // 候选:1×、2×、5× 乘以 magnitude
  final candidates = <double>[magnitude, 2 * magnitude, 5 * magnitude];
  // 选能让 [0..maxVal] 区间内刚好有 3-4 个 tick 的最小档(留 1 档顶部空隙)
  for (final c in candidates) {
    final tickCount = maxVal / c;
    if (tickCount <= 4) return c;
  }
  return candidates.last;
}

double _pow10(int n) {
  double r = 1;
  for (var i = 0; i < n; i++) {
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
