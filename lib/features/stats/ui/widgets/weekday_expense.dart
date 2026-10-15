// lib/features/stats/ui/widgets/weekday_expense.dart
// 报表第 6 张卡:周几支出分布(Mon-Sun 7 柱)
//
// 2026-10-15 D64.3 改:用 `ChartCard` 容器替换重复的 Container 装饰
// 2026-10-15 D64.5 改:maxY + niceInterval 算法下沉到 AnimatedBarChart,
//   本文件只算 maxVal,去掉本地 _niceInterval / _pow10 helper(原 maxVal*1.15
//   非整数倍触发了 fl_chart 在 maxY 位置画小数 label 跟 0 tick 重叠的 bug)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

class WeekdayExpenseChart extends ConsumerWidget {
  const WeekdayExpenseChart({super.key});

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
        if (maxVal == 0) {
          return const ChartCard(
            title: '周几支出',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
              child: Center(
                child: Text(
                  '该时段无支出',
                  style: TextStyle(color: AppGray.g600, fontSize: 13),
                ),
              ),
            ),
          );
        }
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return ChartCard(
          title: '周几支出',
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: SizedBox(
              height: 200,
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
            ),
          ),
        );
      },
      loading: () => const ChartCard(
        title: '周几支出',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => ChartCard(
        title: '周几支出',
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Text(
            '加载失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
      ),
    );
  }
}

/// 2026-10-15 D64.5:_niceInterval / _pow10 已下沉到
/// `core/widgets/charts/animated_bar_chart.dart`,本文件不再需要。
