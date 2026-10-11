// lib/features/stats/ui/widgets/monthly_trend.dart
// 过去 12 个月 收入/支出 折线图
//
// 2026-10-12 ColorOS 曲线入场:折线首次出现时从左往右"画"出来,800ms aquaIn。
// 实现:把 LineChart 包在 _AnimatedLineChart 里,内部 ClipRect 按 _ctrl.value
// 推进 reveal(0 → full width)。视觉上是"线在生长",而不是"全部出现"。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class MonthlyTrendChart extends ConsumerWidget {
  const MonthlyTrendChart({super.key});

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
                child: _AnimatedLineChart(
                  data: data,
                  maxY: maxY,
                  niceInterval: niceInterval,
                  chartNeedsWan: chartNeedsWan,
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

/// 2026-10-12 ColorOS 曲线入场:折线图从左往右"画"出来。
///
/// 实现
///   - 内部 AnimationController 800ms aquaIn,从 0 走到 1
///   - ClipRect 用 _LeftRevealClipper 按 _ctrl.value 控制 reveal 宽度
///   - 视觉:折线 + dot + 阴影 area 一起 reveal,不是"全部出现"
///   - 切月份 / 视角时 monthlyTrendProvider 重建 → _AnimatedLineChart 重建
///     → 重新 forward 入场(数据变化时曲线再"画"一次)
class _AnimatedLineChart extends StatefulWidget {
  const _AnimatedLineChart({
    required this.data,
    required this.maxY,
    required this.niceInterval,
    required this.chartNeedsWan,
  });

  final List<MonthlyTrend> data;
  final double maxY;
  final double niceInterval;
  final bool chartNeedsWan;

  @override
  State<_AnimatedLineChart> createState() => _AnimatedLineChartState();
}

class _AnimatedLineChartState extends State<_AnimatedLineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // 首次入场:从左往右 reveal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return ClipRect(
          clipper: _LeftRevealClipper(_ctrl.value),
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: widget.data
                      .asMap()
                      .entries
                      .map((e) =>
                          FlSpot(e.key.toDouble(), e.value.income))
                      .toList(),
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
                  spots: widget.data
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
              minY: 0,
              maxY: widget.maxY,
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
                    reservedSize: 44,
                    interval: widget.niceInterval,
                    getTitlesWidget: (v, meta) => Text(
                      Formatters.amount(
                        v,
                        forceWan: widget.chartNeedsWan,
                        trimTrailingZeros: true,
                      ),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppGray.g600,
                      ),
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
                      if (i < 0 || i >= widget.data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${widget.data[i].month}月',
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
    );
  }
}

/// ClipRect 用:按 progress(0→1)推进 reveal 宽度,从左往右"画"出折线
class _LeftRevealClipper extends CustomClipper<Rect> {
  _LeftRevealClipper(this.progress);
  final double progress;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_LeftRevealClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
