// lib/features/stats/ui/widgets/savings_trend.dart
// 报表"储蓄走势"模块 —— 1 张 ChartCard + 折线图(line chart)
//
// 2026-10-15 D64.27 加:user UAT D64.25 上线后反馈'储蓄不要加在消费趋势
// tab 里,应该新起一个折线图模块':
// - 储蓄 = (income - expense) / income × 100%(%)走势,跟柱状图视觉不同
// - 折线图更能反映趋势(连续变化 vs 离散柱)
// - 加到 stats_page 后面(消费趋势之后),本年模式专属
//
// 设计要点:
// - 共享 AnimatedLineChart widget(D64.27 加),跟 AnimatedBarChart 镜像 API
// - 12 月储蓄率 points,曲线 + 节点 + 区域填色(0.08 alpha)
// - 节点颜色:正储蓄率 teal,负储蓄率 error 红
// - 0 轴线(负轴时):跟 D64.21c 同款 outline 1px 横线
// - X 轴 label 稀疏化到 1 / 6 / 12 月(跟 D64.22 同款)
// - chartNeedsWan:false(百分比不会到万,强制不走 wan 缩写)
//
// 2026-10-16 D64.29 改:
// - 传 `axisLabelBuilder: (v, _) => v.toStringAsFixed(0)`,Y 轴 label 走整数
//   百分比(原 D64.27 走 Formatters.amount 出 "189.02" 这种带小数百分比是错的)
// - chart height 220 → 260,给密集 range(如 [-189%, +30%])足够 vertical room,
//   Y 轴 0/-50 label 视觉重叠缓解(底层 nice interval 由 D64.29
//   `AnimatedLineChart` 内部计算)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_line_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

/// "储蓄走势"模块 —— 1 张 ChartCard + 折线图
///   本年专属(statsRangeProvider == thisYear 才显示)
class SavingsTrend extends ConsumerWidget {
  const SavingsTrend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(statsCustomYearProvider) ?? DateTime.now().year;
    final trendAsync = ref.watch(yearlyMonthlyTrendProvider(year));
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.income == 0 && d.expense == 0)) {
          return ChartCard(
            title: '储蓄走势',
            showDivider: false,
            child: const SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  '本年暂无收支',
                  style: TextStyle(color: AppGray.g600, fontSize: 13),
                ),
              ),
            ),
          );
        }
        // 算每月储蓄率(%);income=0 该月 rate=null(不画点)
        final points = <LineChartPoint>[];
        for (final m in data) {
          if (m.income == 0) continue; // 跳过 income=0
          final rate = (m.income - m.expense) / m.income * 100;
          points.add(LineChartPoint(label: '${m.month}月', value: rate));
        }
        if (points.isEmpty) {
          return ChartCard(
            title: '储蓄走势',
            showDivider: false,
            child: const SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  '本年无收入',
                  style: TextStyle(color: AppGray.g600, fontSize: 13),
                ),
              ),
            ),
          );
        }
        final values = points.map((p) => p.value).toList();
        final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
        final minVal = values.fold<double>(0, (a, b) => a < b ? a : b);
        return ChartCard(
          title: '储蓄走势',
          showDivider: false,
          child: SizedBox(
            height: 260,
            child: AnimatedLineChart(
              points: points,
              maxVal: maxVal,
              minVal: minVal < 0 ? minVal : null, // D64.21c 负轴
              chartNeedsWan: false, // 百分比不会到万
              // D64.29 加:整数百分比(替代 Formatters.amount 出 "189.02")
              // D64.53 改:加 `%` 单位,user UAT 反馈"单位是什么,我看到还有
              //   负数的" — Y 轴 60/40/-80 没标% user 困惑,加 % 让单位明确
              axisLabelBuilder: (v, _) => '${v.toStringAsFixed(0)}%',
              lineColor: AppBrand.teal,
              // 节点颜色:正储蓄率 teal,负储蓄率 error 红
              pointColorResolver: (i, p) =>
                  p.value >= 0 ? AppBrand.teal : AppStatus.error,
              // X 轴 label 稀疏化到 1 / 6 / 12 月(跟 D64.22 同款)
              xLabelBuilder: (i, p) {
                final m = data[i].month;
                if (m != 1 && m != 6 && m != 12) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    p.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
              touchedLabelBuilder: (i, p) => p.label,
              tooltipBuilder: (i, p) {
                final m = data[i];
                // D64.59:主动语义换行(\n),不依赖 Text widget word wrap 自动切位
                //   - user UAT 反馈"像这种多个的,其实可以换行,比如:
                //     储蓄率:xxx
                //     收:xxx
                //     支:xxx
                //     而不是刚好看在换行那里" — 之前 word wrap 在某字符切到
                //     "支 ¥X" 单独 1 行不整齐,改主动 \n 3 行对齐
                return '储蓄率 ${p.value.toStringAsFixed(0)}%\n'
                    '收 ¥${Formatters.amount(m.income)}\n'
                    '支 ¥${Formatters.amount(m.expense)}';
              },
            ),
          ),
        );
      },
      loading: () => ChartCard(
        title: '储蓄走势',
        showDivider: false,
        child: const SizedBox(
          height: 260,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => ChartCard(
        title: '储蓄走势',
        showDivider: false,
        child: SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s3),
            child: Text(
              '加载失败:$e',
              style: const TextStyle(color: AppStatus.error),
            ),
          ),
        ),
      ),
    );
  }
}
