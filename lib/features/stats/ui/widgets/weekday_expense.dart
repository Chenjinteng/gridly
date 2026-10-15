// lib/features/stats/ui/widgets/weekday_expense.dart
// 报表第 6 张卡:周几支出分布(Mon-Sun 7 柱)
//   - user 想看"哪天爱花钱",辅助"工作日 vs 周末"消费习惯分析
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 仅本月维度有意义(本年维度按月聚合,weekday 不直观),本年维度 widget 仍按本月数据兜底
//   - 高亮最大值柱(用 AppStatus.error 实色,其它柱用 AppGray.g200 浅灰)
//
// 2026-10-15 D63 加
// 2026-10-15 D64 改:BarChart 业务用共享 `AnimatedBarChart`
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../application/stats_providers.dart';

class WeekdayExpenseChart extends ConsumerWidget {
  const WeekdayExpenseChart({super.key});

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekdayAsync = ref.watch(weekdayExpenseProvider);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '周几支出',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          weekdayAsync.when(
            data: (data) {
              final maxVal = data.fold<double>(
                0,
                (a, b) => a > b.expense ? a : b.expense,
              );
              if (maxVal == 0) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final maxY = maxVal * 1.15;
              final niceInterval = _niceInterval(maxY);
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              return Padding(
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
                    barWidth: 18, // 7 柱,每柱宽一点
                    // 高亮最大值柱:用 barColorResolver 按 bar 算色
                    barColorResolver: (i, b) =>
                        b.value == maxVal ? AppStatus.error : AppGray.g200,
                    xLabelBuilder: (i, b) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        b.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    touchedLabelBuilder: (i, b) => '周${_weekdayLabels[i]}',
                    tooltipBuilder: (i, b) => '¥${Formatters.amount(b.value)}',
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
        ],
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
