// lib/features/stats/ui/widgets/category_pie.dart
// 支出分类饼图(按金额从大到小,最多 8 块)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/stats_providers.dart';

class CategoryPie extends ConsumerWidget {
  const CategoryPie({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支出分类',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s3),
          expensesAsync.when(
            data: (data) {
              if (data.isEmpty) {
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
              final total = data.fold<double>(0, (s, e) => s + e.amount);
              return Row(
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: data
                            .take(8)
                            .map(
                              (e) => PieChartSectionData(
                                value: e.amount,
                                color: Color(e.color),
                                title: '',
                                radius: 32,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: data.take(8).map((e) {
                        final pct = (e.amount / total * 100).toStringAsFixed(0);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Color(e.color),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.name,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppGray.g600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
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
