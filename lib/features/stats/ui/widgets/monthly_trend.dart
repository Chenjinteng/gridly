// lib/features/stats/ui/widgets/monthly_trend.dart
// 时间趋势卡片 —— 根据 statsRange 自动切换数据源 + 图表类型:
//   thisMonth → 按天支出柱状图(_DailyExpenseBarChart,看 dailyExpenseTrendProvider)
//   thisYear  → 当年 1-12 月支出柱状图(_MonthlyBarChart,看 yearlyExpenseTrendProvider,单柱)
//
// 2026-10-12 redesign (commit 72):
//   user "近 12 月趋势"反馈:
//     - 本月维度不需要这个 12 月折线图 → 换按天柱状图(本月每天支出)
//     - 本年维度才显示 12 个月柱状图(去掉折线,改成柱状)
//   旧实现是单一 LineChart + 固定过去 12 月数据(不看 range),改成分支 + BarChart。
//
// 2026-10-15 D64 改:BarChart 业务逻辑全部抽到 `core/widgets/charts/animated_bar_chart.dart`,
//   共享 `AnimatedBarChart`(viewport-aware + 触摸 + 虚线 + label + tooltip)。
//   本文件只保留:
//     - 容器 widget (MonthlyTrendChart,卡片样式 + range 标题切换)
//     - 2 个数据 widget (_DailyExpenseBarChart / _MonthlyBarChart),用共享 widget
//     - niceInterval 计算 helper
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../application/stats_providers.dart';

/// 时间趋势卡片容器 —— 看 statsRange 自动切换 widget:
///   thisMonth → _DailyExpenseBarChart
///   thisYear  → _MonthlyBarChart
class MonthlyTrendChart extends ConsumerWidget {
  const MonthlyTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return Container(
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
          child: AnimatedBarChart(
            bars: [
              for (final d in data)
                BarChartBar(label: '${d.day}日', value: d.expense),
            ],
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            primaryColor: AppStatus.error,
            // 30 根柱全标 label 太密,稀疏化:1/5/10/15/20/25/30
            xLabelBuilder: (i, b) {
              final day = data[i].day;
              if (day != 1 && day % 5 != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
            touchedLabelBuilder: (i, b) => '${data[i].day}日',
            tooltipBuilder: (i, b) => '¥${Formatters.amount(b.value)}',
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

/// 当年 1-12 月支出柱状图(thisYear 用)
class _MonthlyBarChart extends ConsumerWidget {
  const _MonthlyBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(yearlyExpenseTrendProvider);
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Center(
              child: Text(
                '本年暂无支出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
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
          child: AnimatedBarChart(
            bars: [
              for (final m in data)
                BarChartBar(label: '${m.month}月', value: m.expense),
            ],
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            primaryColor: AppStatus.error,
            // 12 月全标 label
            xLabelBuilder: (i, b) => Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                b.label,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            touchedLabelBuilder: (i, b) => b.label,
            tooltipBuilder: (i, b) => '¥${Formatters.amount(b.value)}',
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
