// lib/features/stats/ui/widgets/weekday_expense.dart
// 报表第 6 张卡:周几支出分布(Mon-Sun 7 柱)
//
// 2026-10-15 D64.3 改:用 `ChartCard` 容器替换重复的 Container 装饰
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
        final maxY = maxVal * 1.15;
        final niceInterval = _niceInterval(maxY);
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
                maxY: maxY,
                niceInterval: niceInterval,
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

double _niceInterval(double maxY) {
  if (maxY <= 0) return 100;
  final v = maxY / 5;
  if (v <= 0) return 1;
  final exp = v.toString().split('.').first.length - 1;
  final n = _pow10(exp < 0 ? 0 : exp);
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
