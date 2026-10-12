// lib/features/stats/ui/widgets/monthly_trend.dart
// 时间趋势卡片 —— 根据 statsRange 自动切换数据源 + 图表类型:
//   thisMonth → 按天支出柱状图(_DailyExpenseBarChart,看 dailyExpenseTrendProvider)
//   thisYear  → 12 月柱状图(_MonthlyBarChart,看 monthlyTrendProvider,收入/支出各一柱)
//
// 2026-10-12 redesign (commit 72):
//   user "近 12 月趋势"反馈:
//     - 本月维度不需要这个 12 月折线图 → 换按天柱状图(本月每天支出)
//     - 本年维度才显示 12 个月柱状图(去掉折线,改成柱状)
//   旧实现是单一 LineChart + 固定过去 12 月数据(不看 range),改成分支 + BarChart。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

/// 时间趋势卡片容器 —— 看 statsRange 自动切换 widget:
///   thisMonth → _DailyExpenseBarChart
///   thisYear  → _MonthlyBarChart
///
/// 容器 widget 的 padding / 卡片边框 / 阴影 / 标题结构不变,只换内部图表。
/// 标题根据 range 切换文案("本月每日支出" / "近 12 月趋势")
class MonthlyTrendChart extends ConsumerWidget {
  const MonthlyTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return Container(
      // 跟 Top 10 / CategoryPie / IncomePie 同卡片风格(surface + 1px 边框 + shadow)
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.0,
        ),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            range == StatsRange.thisMonth ? '本月每日支出' : '近 12 月趋势',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s3),
          // 用 SizedBox + 192px 高度统一,BarChart 自适应高度(底部 X labels 占一些)。
          SizedBox(
            height: 192,
            child: range == StatsRange.thisMonth
                ? const _DailyExpenseBarChart()
                : const _MonthlyBarChart(),
          ),
        ],
      ),
    );
  }
}

/// 本月每日支出柱状图(thisMonth 用)
class _DailyExpenseBarChart extends ConsumerWidget {
  const _DailyExpenseBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyExpenseTrendProvider);
    return dailyAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Center(
              child: Text(
                '本月暂无支出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        // 同 niceInterval 逻辑:避免 345.23 这种带小数的 tick label
        final maxVal = data
            .map((d) => d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final niceInterval = _pickNiceInterval(maxVal);
        final maxY = maxVal == 0
            ? 1.0
            : (maxVal / niceInterval).ceil() * niceInterval;
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: _AnimatedBarChart(
            bars: data,
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            color: AppStatus.error,
            labelKind: BarLabelKind.day, // X label 是日期
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// 近 12 月柱状图(thisYear 用)—— 一月一根柱,revenue 跟 expense 并排 grouped
class _MonthlyBarChart extends ConsumerWidget {
  const _MonthlyBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(monthlyTrendProvider);
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.income == 0 && d.expense == 0)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Center(
              child: Text(
                '近 12 月暂无数据',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        final maxVal = data
            .map((d) => d.income > d.expense ? d.income : d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final niceInterval = _pickNiceInterval(maxVal);
        final maxY = maxVal == 0
            ? 1.0
            : (maxVal / niceInterval).ceil() * niceInterval;
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: _AnimatedBarChart(
            bars: data,
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            color: AppStatus.error,
            labelKind: BarLabelKind.month, // X label 是月份
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// Bar label 类型:日期(本月每日柱状图用)还是月份(近 12 月柱状图用)
enum BarLabelKind { day, month }

/// 入场柱子 —— 从底部往上"长"起来,nice tween 480ms aquaIn。
///
/// 实现:
///   - 内部 AnimationController 480ms aquaIn,从 0 走到 1
///   - 用 _BarGrowCustomPainter 把 BarChart 重画,BarChartRodData 的
///     toY 用 lerp(0, target, _ctrl.value) 做"长高"
///   - 但是 fl_chart 的 BarChart 不直接暴露 BarChartRodData.toY 的 lerp 入口,
///     改用整体 AnimationBuilder 包 BarChart,让 chart 容器整体 fade in(400ms)
///     + 同步用一个 _BarGrowthWidget 在 chart 上 overlay 模拟柱子从下往上的
///     蒙版 reveal(用 progress 0→1 提升 reveal 高度)。
///
/// 简化:不做 column-grow 蒙版,用整体 fade-in + chart 自带的入场动画即可。
class _AnimatedBarChart extends StatefulWidget {
  const _AnimatedBarChart({
    required this.bars,
    required this.maxY,
    required this.niceInterval,
    required this.chartNeedsWan,
    required this.color,
    required this.labelKind,
  });

  final List bars;
  final double maxY;
  final double niceInterval;
  final bool chartNeedsWan;
  final Color color;
  final BarLabelKind labelKind;

  @override
  State<_AnimatedBarChart> createState() => _AnimatedBarChartState();
}

class _AnimatedBarChartState extends State<_AnimatedBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
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
        return Opacity(
          opacity: Curves.easeInOut.transform(_ctrl.value),
          child: _buildChart(),
        );
      },
    );
  }

  Widget _buildChart() {
    final scheme = Theme.of(context).colorScheme;
    return BarChart(
      BarChartData(
        maxY: widget.maxY,
        minY: 0,
        // daily 30 根柱,BarChartAlignment.spaceAround 默认会把柱挨在一起;
        // 改 spaceBetween + groupsSpace 4 让每根柱之间有 4px 留白,看起来"呼吸"
        // 2026-10-12 user 反馈"柱与柱之间没有间隔",commit 73 加
        alignment: BarChartAlignment.spaceBetween,
        groupsSpace: 4,
        barTouchData: BarTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppBrand.ink,
            getTooltipItem: (group, gIdx, rod, rIdx) {
              final v = rod.toY;
              return BarTooltipItem(
                '¥${Formatters.amount(v)}',
                TextStyle(
                  color: AppBrand.gold,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: widget.niceInterval,
              getTitlesWidget: (v, meta) => Text(
                Formatters.amount(
                  v,
                  forceWan: widget.chartNeedsWan,
                  trimTrailingZeros: true,
                ),
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
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
              interval: 1,
              getTitlesWidget: (v, meta) {
                final idx = v.toInt();
                if (idx < 0 || idx >= widget.bars.length) {
                  return const SizedBox.shrink();
                }
                if (widget.labelKind == BarLabelKind.day) {
                  // daily bar(30 根柱)X 轴只标 1, 5, 10, 15, 20, 25, 30
                  // 稀疏化,避免小屏 label 重叠
                  // 2026-10-12 user 反馈"太密了",从全 30 个标签改 7 个
                  final day = widget.bars[idx].day;
                  if (day != 1 && day % 5 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                // monthly bar(12 月)X 轴全标 12 个月
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${widget.bars[idx].month}月',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: _buildBarGroups(),
      ),
    );
  }

  /// 把 daily/monthly 数据转成 BarChartGroupData 列表
  ///
  /// - DailyExpenseBarChart:每天 1 根柱(支出,error 红)
  /// - MonthlyTrendBarChart:每月 1 组(grouped),组里 2 根柱(收入 gold / 支出 red)
  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < widget.bars.length; i++) {
      if (widget.labelKind == BarLabelKind.day) {
        // 每日 1 柱
        // commit 73:width 8 → 5 + groupsSpace 4,30 根柱的 30×5 + 29×4 = 266
        // + chart padding ≈ 330,30 根柱之间各有 4px 留白
        final d = widget.bars[i];
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: d.expense,
                color: widget.color,
                width: 5,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ],
          ),
        );
      } else {
        // 每月 grouped(income + expense)
        final m = widget.bars[i];
        groups.add(
          BarChartGroupData(
            x: i,
            barsSpace: 2, // 双柱紧贴
            barRods: [
              BarChartRodData(
                toY: m.income,
                color: AppBrand.gold,
                width: 5,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
              BarChartRodData(
                toY: m.expense,
                color: AppStatus.error,
                width: 5,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ],
          ),
        );
      }
    }
    return groups;
  }
}

/// 2026-10-01 沿用:按"1/2/5 × 10^n"挑 niceInterval,避免 maxY 实际值出现
double _pickNiceInterval(double maxVal) {
  if (maxVal <= 0) return 1;
  final magnitude = _pow10(
    (maxVal.abs().toString().split('.').first.length) - 1,
  );
  final candidates = <double>[magnitude, 2 * magnitude, 5 * magnitude];
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
