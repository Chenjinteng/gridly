// lib/features/stats/ui/widgets/consumption_trend.dart
// 报表"消费趋势"模块 —— 同一 ChartCard 根据 statsRangeProvider 切换 3 tab 内容。
//
// 2026-10-15 D64.10 改:把原本 3 张独立卡(本月每日支出 / 类别对比 / 周几支出)
//   合并成"消费趋势"模块,用 tab 切换(每日 / 类别 / 周几),tab 样式照搬
//   `top_expenses.dart` 的"单笔/分类"段。
//
// 2026-10-15 D64.21d 改:range-aware 切换 tab 内容。
//   - 本月模式(StatsRange.thisMonth):3 tab = 每日 / 类别 / 周几(原有逻辑保留)
//   - 本年模式(StatsRange.thisYear):3 tab = 收支 / 结余 / 预算(新增)
//   - 整体结构保持 1 张 ChartCard,trailing TabBar + TabBarView,只是 tabs
//     列表和对应 body widget 根据 range 切换。
//
// 本年模式 3 tab 数据源:
//   - 收支:yearlyMonthlyTrendProvider.family<year>(income + expense 双柱)
//   - 结余:yearlyMonthlyTrendProvider 同上,UI 层算 income - expense(可负)
//   - 预算:monthlyBudgetHistoryProvider.family<year>(D64.21b,可能负或 0)
//
// 设计要点:
// - DefaultTabController(length: 3) 必须包整个 widget(D64.4 教训),trailing TabBar
//   跟 child TabBarView 共享 controller
// - 所有 tab 高度统一 220(SizedBox),切换 tab 时卡片高度不变 → 视觉稳定
// - 全年 3 tab 复用 AnimatedBarChart + D64.21c 新增的 minY 负轴支持
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/vertical_bar_label.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

/// "消费趋势"模块容器 —— range-aware 切换 tab 内容:
///   本月 → 每日/类别/周几(原 D64.10)
///   本年 → 收支/结余/预算(新 D64.21d)
class ConsumptionTrend extends ConsumerWidget {
  const ConsumptionTrend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return range == StatsRange.thisYear
        ? const _YearlyConsumptionTrend()
        : const _MonthlyConsumptionTrend();
  }
}

/// ========== 本月模式(D64.10 原 3 tab 逻辑保留) ==========

class _MonthlyConsumptionTrend extends StatelessWidget {
  const _MonthlyConsumptionTrend();

  @override
  Widget build(BuildContext context) {
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
            // D71.5.5:tabBarTheme 接管
            dividerHeight: 0,
          ),
        ),
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
            // 2026-10-20 D64.72:9 个中文分类名横排重叠 → 改**中文竖排**
            //   - D64.71 曾完全去掉 X 轴 label,user UAT 反馈"没有横坐标有点奇怪"
            //   - 实测(widget test,真机 ChartCard 内容宽 296dp,9 分类):
            //     45° 斜排 + 10sp → 5 对重叠 / +9sp → 3 对 / +8sp → 1 对
            //     55°/60° + 8sp → 0 对(字太小)
            //     70° + 9sp → 0 对(字符被转 70°,读要歪头)
            //     **中文竖排(字正立)+ 9sp → 0 对,字最清楚** ← user 选定
            //   - 用 `VerticalBarLabel`(字符保持正立、上下堆叠),
            //     不是把整段文字旋转 90°(那样中文几乎不可读)
            //   - xLabelReservedSize 64:7 字 × 9sp ≈ 63px 竖排高度上限
            xLabelReservedSize: 64,
            xLabelBuilder: (i, b) => VerticalBarLabel(b.label),
            touchedLabelBuilder: (i, b) => b.label,
            tooltipBuilder: (i, b) =>
                '${b.label}\n¥${Formatters.amount(shown[i].currAmount)}',
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

/// ========== 本年模式(D64.21d 新增 3 tab) ==========

class _YearlyConsumptionTrend extends StatelessWidget {
  const _YearlyConsumptionTrend();

  @override
  Widget build(BuildContext context) {
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
              Tab(text: '收支'),
              Tab(text: '结余'),
              Tab(text: '预算'),
            ],
            // D71.5.5:tabBarTheme 接管
            dividerHeight: 0,
          ),
        ),
        child: const SizedBox(
          height: 220,
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [
              _IncomeExpenseTab(),
              _BalanceTab(),
              _BudgetTab(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收支 tab:某年 1-12 月的 income + expense 双柱(全年)
class _IncomeExpenseTab extends ConsumerWidget {
  const _IncomeExpenseTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(statsCustomYearProvider) ?? DateTime.now().year;
    final trendAsync = ref.watch(yearlyMonthlyTrendProvider(year));
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.income == 0 && d.expense == 0)) {
          return _EmptyHint(text: '本年暂无收支');
        }
        final maxVal = data
            .map((d) => d.income > d.expense ? d.income : d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: AnimatedBarChart(
            bars: [
              for (final m in data)
                BarChartBar(
                  label: '${m.month}月',
                  // 主柱 = expense(支出,关心花多少),次柱 = income(收入)
                  // 颜色:expense 用 error 红、income 用 secondaryColor(默认 g200 灰)
                  value: m.expense,
                  secondaryValue: m.income,
                ),
            ],
            maxVal: maxVal,
            chartNeedsWan: chartNeedsWan,
            primaryColor: AppStatus.error,
            secondaryColor: AppGray.g200,
            // D64.23 改:barWidth 8 太宽,双柱互相重叠。改成跟 _DailyExpenseBars
            // 同款默认细柱(barWidth=5),groupsSpace 用默认 4 跟月度每日一致
            barsSpace: 1,
            // D64.22 改:12 月全标 label 太密,稀疏化到 1 / 6 / 12 三个月(起 / 中 / 末)
            xLabelBuilder: (i, b) {
              final m = data[i].month;
              if (m != 1 && m != 6 && m != 12) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  b.label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
            touchedLabelBuilder: (i, b) => b.label,
            tooltipBuilder: (i, b) =>
                // D64.59:主动语义换行(同 savings_trend 套路,user UAT 反馈
                // "刚好看在换行那里"不整齐)
                '支 ¥${Formatters.amount(data[i].expense)}\n'
                '收 ¥${Formatters.amount(data[i].income)}',
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

/// 结余 tab:某年 1-12 月的 (income - expense),可负
///   - 0 轴线由 D64.21c AnimatedBarChart 自动画(minVal < 0 时启用)
///   - 正柱用 secondaryColor(灰,代表正向结余),负柱用 error(红,代表负向结余)
class _BalanceTab extends ConsumerWidget {
  const _BalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(statsCustomYearProvider) ?? DateTime.now().year;
    final trendAsync = ref.watch(yearlyMonthlyTrendProvider(year));
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.income == 0 && d.expense == 0)) {
          return _EmptyHint(text: '本年暂无收支');
        }
        final balances = data.map((d) => d.income - d.expense).toList();
        final maxVal = balances
            .fold<double>(0, (a, b) => a > b ? a : b);
        final minVal = balances
            .fold<double>(0, (a, b) => a < b ? a : b);
        if (maxVal == 0 && minVal == 0) {
          return _EmptyHint(text: '本年无结余');
        }
        final chartNeedsWan =
            maxVal.abs() >= Formatters.wanThreshold ||
                minVal.abs() >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: AnimatedBarChart(
            bars: [
              for (var i = 0; i < data.length; i++)
                BarChartBar(
                  label: '${data[i].month}月',
                  value: balances[i],
                ),
            ],
            maxVal: maxVal,
            minVal: minVal, // D64.21c 负轴:负柱(支出>收入)自动朝下
            chartNeedsWan: chartNeedsWan,
            // 颜色按正负区分:正结余用 teal(正向),负结余用 error 红
            // D71.2:跟随 palette
            barColorResolver: (i, b) => b.value >= 0
                ? Theme.of(context).colorScheme.primary
                : AppStatus.error,
            // D64.22 改:稀疏化到 1 / 6 / 12 三个月(起 / 中 / 末)
            xLabelBuilder: (i, b) {
              final m = data[i].month;
              if (m != 1 && m != 6 && m != 12) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  b.label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
            touchedLabelBuilder: (i, b) => b.label,
            tooltipBuilder: (i, b) =>
                '结余 ¥${Formatters.amount(b.value)}',
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

/// 预算 tab:某年 1-12 月的预算 vs 实际支出对比
///   - 双柱:预算 teal + 实际支出 error 红
///   - 一眼看出哪几个月超支(红柱超过 teal)
///   - 缺失月份(amount=0)显示空柱,跟 RangeSummary 12 月走势风格一致
///   - D64.24 改:之前只显示预算走势"没意义",补实际支出对比
class _BudgetTab extends ConsumerWidget {
  const _BudgetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(statsCustomYearProvider) ?? DateTime.now().year;
    final budgetAsync = ref.watch(monthlyBudgetHistoryProvider(year));
    final expenseAsync = ref.watch(yearlyExpenseTrendProvider);
    return budgetAsync.when(
      data: (budgets) => expenseAsync.when(
        data: (expenses) {
          // 预算 + 实际支出 双数据合并
          if (budgets.every((d) => d.amount == 0)) {
            return _EmptyHint(text: '本年未设置过预算');
          }
          // 取 max(预算, 实际支出)算 maxVal
          final maxVal = <double>[];
          for (var i = 0; i < budgets.length; i++) {
            maxVal.add(budgets[i].amount);
            maxVal.add(expenses[i].expense);
          }
          final maxChart = maxVal.fold<double>(0, (a, b) => a > b ? a : b);
          if (maxChart == 0) return _EmptyHint(text: '本年无预算数据');
          final chartNeedsWan = maxChart >= Formatters.wanThreshold;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: AnimatedBarChart(
              bars: [
                for (var i = 0; i < budgets.length; i++)
                  BarChartBar(
                    label: '${budgets[i].month}月',
                    // 主柱 = 预算,次柱 = 实际支出
                    value: budgets[i].amount,
                    secondaryValue: expenses[i].expense,
                  ),
              ],
              maxVal: maxChart,
              chartNeedsWan: chartNeedsWan,
              // 预算 teal(品牌色,跟"还剩 ¥X"home 顶部配色对齐)
              // D71.2:跟随 palette
              primaryColor: Theme.of(context).colorScheme.primary,
              // 实际支出 error 红(跟 range_summary 支出配色一致)
              secondaryColor: AppStatus.error,
              // 跟 收支 tab D64.23 同款细柱
              barsSpace: 1,
              // D64.22 改:稀疏化到 1 / 6 / 12 三个月(起 / 中 / 末)
              xLabelBuilder: (i, b) {
                final m = budgets[i].month;
                if (m != 1 && m != 6 && m != 12) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    b.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
              touchedLabelBuilder: (i, b) => b.label,
              tooltipBuilder: (i, b) {
                final budget = budgets[i].amount;
                final spent = expenses[i].expense;
                final diff = budget - spent;
                final pct = budget > 0 ? (spent / budget * 100) : 0;
                final over = spent > budget;
                // D64.59:主动语义换行(3 行,跟储蓄走势对齐)
                //   - 第 1 行:超支警示(仅 over 时显示;不超支时不画空白行)
                //   - 第 2 行:预算
                //   - 第 3 行:实支详情 — "实支 ¥X  超/剩 ¥Y (X%)" 把超差
                //     和占比合并到 1 行,避免 4 行超过 chart maxLines 3
                //   - 跟之前自动 word wrap 截图对照:之前"⚠ 超支 预算 ¥X" 挤
                //     在 1 行不整齐,现在 3 行对齐
                final warningLine = over ? '⚠ 超支\n' : '';
                return '$warningLine'
                    '预算 ¥${Formatters.amount(budget)}\n'
                    '实支 ¥${Formatters.amount(spent)}'
                    '  ${diff >= 0 ? '剩' : '超'} ¥${Formatters.amount(diff.abs())}'
                    ' (${pct.toStringAsFixed(0)}%)';
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
        ),
      ),
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
