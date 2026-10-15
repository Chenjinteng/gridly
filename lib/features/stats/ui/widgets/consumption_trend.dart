// lib/features/stats/ui/widgets/consumption_trend.dart
// 报表"消费趋势"模块 —— 3 个柱状图合并成 1 张卡 + tab 切换。
//
// 2026-10-15 D64.10 改:把原本 3 张独立卡(本月每日支出 / 类别对比 / 周几支出)
//   合并成"消费趋势"模块,用 tab 切换(每日 / 类别 / 周几),tab 样式照搬
//   `top_expenses.dart` 的"单笔/分类"段。3 段共用 1 个 ChartCard,降低视觉碎片。
//
// - 每日 tab:本月 → 按天支出(dailyExpenseTrendProvider);本年 → 按月支出
//   (yearlyExpenseTrendProvider,替代原 monthly_trend thisYear 行为)
// - 类别 tab:本月 → 本月 vs 上月各类支出(categoryCompareProvider);
//   本年 → 空态("切到本月查看对比"),原 provider thisYear 1 月 vs 12 月语义错
// - 周几 tab:weekdayExpenseProvider,本月 / 本年通用(本年是 12 月按 weekday 聚合)
//
// 设计要点:
// - DefaultTabController(length: 3) 必须包整个 widget(D64.4 教训),trailing TabBar
//   跟 child TabBarView 共享 controller
// - 所有 tab 高度统一 220(SizedBox),切换 tab 时卡片高度不变 → 视觉稳定
// - 沿用 monthly_trend / category_compare / weekday_expense 原 widget 的全部逻辑
//   (providers + bar chart 配置),本文件取代那 3 个文件
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

/// "消费趋势"模块容器 —— 1 张 ChartCard + 3 tabs(每日 / 类别 / 周几)
class ConsumptionTrend extends ConsumerWidget {
  const ConsumptionTrend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: ChartCard(
        title: '消费趋势',
        showDivider: false,
        trailing: SizedBox(
          height: 36,
          child: TabBar(
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.label,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: const [
              Tab(text: '每日'),
              Tab(text: '类别'),
              Tab(text: '周几'),
            ],
            labelColor: AppBrand.teal,
            unselectedLabelColor: AppGray.g600,
            indicatorColor: AppBrand.teal,
            dividerHeight: 0,
          ),
        ),
        // 固定高度 220 让 3 个 tab 切换时卡片高度不抖动(原 3 张卡分别是
        // 192 / 220 / 200,统一到 220 容下类别对比的 padding)
        child: const SizedBox(
          height: 220,
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [_DailyTab(), _CategoryTab(), _WeekdayTab()],
          ),
        ),
      ),
    );
  }
}

/// 每日 tab:本月 → 按天支出;本年 → 当年 1-12 月支出(原 monthly_trend thisYear)
class _DailyTab extends ConsumerWidget {
  const _DailyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return range == StatsRange.thisMonth
        ? const _DailyExpenseBars()
        : const _MonthlyExpenseBars();
  }
}

/// 本月每日支出柱状图
class _DailyExpenseBars extends ConsumerWidget {
  const _DailyExpenseBars();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyExpenseTrendProvider);
    return dailyAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return _EmptyHint(text: '本月暂无支出');
        }
        final maxVal = data
            .map((d) => d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: AnimatedBarChart(
            bars: [
              for (final d in data)
                BarChartBar(label: '${d.day}日', value: d.expense),
            ],
            maxVal: maxVal,
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

/// 当年 1-12 月支出柱状图(本年维度)
class _MonthlyExpenseBars extends ConsumerWidget {
  const _MonthlyExpenseBars();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(yearlyExpenseTrendProvider);
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return _EmptyHint(text: '本年暂无支出');
        }
        final maxVal = data
            .map((d) => d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: AnimatedBarChart(
            bars: [
              for (final m in data)
                BarChartBar(label: '${m.month}月', value: m.expense),
            ],
            maxVal: maxVal,
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

/// 类别 tab:本月 vs 上月各类支出对比(本月专用,本年返空态)
class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    if (range != StatsRange.thisMonth) {
      // categoryCompareProvider 在 thisYear 模式下语义错(1 月 vs 12 月) → 不显示
      return _EmptyHint(text: '类别对比仅本月维度,切到本月查看');
    }
    final compareAsync = ref.watch(categoryCompareProvider);
    return compareAsync.when(
      data: (data) {
        if (data.isEmpty) return _EmptyHint(text: '该时段无支出');
        final shown = data.take(6).toList();
        final maxVal = shown
            .map(
              (e) => e.currAmount > e.prevAmount ? e.currAmount : e.prevAmount,
            )
            .fold<double>(0, (a, b) => a > b ? a : b);
        if (maxVal == 0) return _EmptyHint(text: '该时段无支出');
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: AnimatedBarChart(
            bars: [
              for (final c in shown)
                BarChartBar(
                  label: c.name,
                  value: c.currAmount,
                  secondaryValue: c.prevAmount,
                ),
            ],
            maxVal: maxVal,
            chartNeedsWan: chartNeedsWan,
            primaryColor: AppStatus.error,
            secondaryColor: AppGray.g200,
            barWidth: 8,
            barsSpace: 2,
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

/// 周几 tab:Mon-Sun 7 柱支出分布(本月 / 本年通用)
class _WeekdayTab extends ConsumerWidget {
  const _WeekdayTab();

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekdayAsync = ref.watch(weekdayExpenseProvider);
    return weekdayAsync.when(
      data: (data) {
        final maxVal = data.fold<double>(
          0,
          (a, b) => a > b.expense ? a : b.expense,
        );
        if (maxVal == 0) return _EmptyHint(text: '该时段无支出');
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: AnimatedBarChart(
            bars: [
              for (final d in data)
                BarChartBar(
                  label: _weekdayLabels[d.weekday - 1],
                  value: d.expense,
                ),
            ],
            maxVal: maxVal,
            chartNeedsWan: chartNeedsWan,
            barWidth: 18,
            barColorResolver: (i, b) =>
                b.value == maxVal ? AppStatus.error : AppGray.g200,
            xLabelBuilder: (i, b) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(b.label, style: const TextStyle(fontSize: 11)),
            ),
            touchedLabelBuilder: (i, b) => '周${_weekdayLabels[i]}',
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

/// 通用空态(灰字居中,跟原 3 个 widget 行为一致)
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: AppGray.g600, fontSize: 13),
      ),
    );
  }
}
