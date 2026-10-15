// lib/features/stats/ui/widgets/category_pie.dart
// 支出分类圆环图 + 右侧图例。
// 圆环中心显示"总支出"金额,右侧前 8 个分类按金额排序列出来。
// 容器套外框 + 标题栏,延续"格子"Excel 主题风格。
//
// 2026-10-15 D64.2 改:用 `ChartCard` + `PieChartCard`(`core/widgets/charts/`)
//   共用通用圆环+图例 widget,本身只保留数据接入逻辑。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../application/stats_providers.dart';

class CategoryPie extends ConsumerWidget {
  const CategoryPie({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    return expensesAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        return PieChartCard(
          title: '支出分类',
          items: buildPieChartItems<CategoryExpense>(
            data,
            nameOf: (e) => e.name,
            valueOf: (e) => e.amount,
            colorOf: (e) => e.color,
          ),
          total: total,
          centerLabel: '总支出',
          centerValueText: '¥${Formatters.amount(total)}',
          totalLabel: data.isEmpty ? null : '共 ¥${Formatters.amount(total)}',
        );
      },
      loading: () => PieChartCard(
        title: '支出分类',
        items: const [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '¥0',
        totalLabel: null,
      ),
      error: (e, _) => PieChartCard(
        title: '支出分类',
        items: const [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '加载失败',
        totalLabel: null,
      ),
    );
  }
}
