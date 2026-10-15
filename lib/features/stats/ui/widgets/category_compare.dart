// lib/features/stats/ui/widgets/category_compare.dart
// 报表第 5 张卡:本月 vs 上月 各类别支出对比
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

class CategoryCompareChart extends ConsumerWidget {
  const CategoryCompareChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareAsync = ref.watch(categoryCompareProvider);
    return compareAsync.when(
      data: (data) {
        if (data.isEmpty) {
          return const ChartCard(
            title: '类别对比',
            trailing: _LegendDots(),
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
        final shown = data.take(6).toList();
        final maxVal = shown
            .map(
              (e) => e.currAmount > e.prevAmount ? e.currAmount : e.prevAmount,
            )
            .fold<double>(0, (a, b) => a > b ? a : b);
        if (maxVal == 0) {
          return const ChartCard(
            title: '类别对比',
            trailing: _LegendDots(),
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
          title: '类别对比',
          trailing: const _LegendDots(),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: SizedBox(
              height: 220,
              child: AnimatedBarChart(
                bars: [
                  for (final c in shown)
                    BarChartBar(
                      label: c.name,
                      value: c.currAmount,
                      secondaryValue: c.prevAmount,
                    ),
                ],
                maxY: maxY,
                niceInterval: niceInterval,
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
            ),
          ),
        );
      },
      loading: () => const ChartCard(
        title: '类别对比',
        trailing: _LegendDots(),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => ChartCard(
        title: '类别对比',
        trailing: const _LegendDots(),
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

class _LegendDots extends StatelessWidget {
  const _LegendDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _LegendDot(color: AppStatus.error, label: '本月'),
        SizedBox(width: AppSpacing.s3),
        _LegendDot(color: AppGray.g200, label: '上月'),
      ],
    );
  }
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppGray.g600)),
      ],
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
