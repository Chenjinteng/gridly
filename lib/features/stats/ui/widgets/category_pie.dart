// lib/features/stats/ui/widgets/category_pie.dart
// 支出分类"格子单元"网格 —— 替代之前的饼图。
// 3 列 × N 行的 cell 网格:每格 = 一个分类(图标 + 名字 + 占比 + 金额)。
// 格子背景颜色深度按占比变化,视觉上像 Excel 数据单元格。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';
import '../../application/stats_providers.dart';

class CategoryPie extends ConsumerWidget {
  const CategoryPie({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    final catsAsync = ref.watch(allCategoriesProvider);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
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
              children: [
                const Text(
                  '支出分类',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                expensesAsync.maybeWhen(
                  data: (data) {
                    if (data.isEmpty) return const SizedBox.shrink();
                    final total = data.fold<double>(0, (s, e) => s + e.amount);
                    return Text(
                      '共 ¥${Formatters.amount(total)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppGray.g600,
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
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
              final cats = catsAsync.valueOrNull ?? const <Category>[];
              return _CategoryGrid(
                expenses: data,
                categories: cats,
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

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.expenses,
    required this.categories,
  });
  final List<CategoryExpense> expenses;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 限制展示前 9 个(3×3);其余合并到"其他"
    final visible = expenses.take(9).toList();
    final overflow = expenses.skip(9).toList();
    final overflowSum = overflow.fold<double>(0, (s, e) => s + e.amount);
    final cells = <_CellData>[
      for (final e in visible)
        _CellData(
          name: e.name,
          amount: e.amount,
          color: e.color,
          iconKey: _iconKeyFor(e.categoryId, categories),
        ),
      if (overflow.isNotEmpty)
        _CellData(
          name: '其他',
          amount: overflowSum,
          color: AppGray.g400.toARGB32(),
          iconKey: 'more_horiz',
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 3;
        const cellSpacing = 0.5;
        final cellWidth = (constraints.maxWidth -
                cellSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final cellHeight = cellWidth * 0.85;
        final rowCount = (cells.length / crossAxisCount).ceil();
        return Column(
          children: [
            for (var row = 0; row < rowCount; row++)
              Row(
                children: [
                  for (var col = 0; col < crossAxisCount; col++)
                    _buildCell(
                      theme: theme,
                      index: row * crossAxisCount + col,
                      cell: row * crossAxisCount + col < cells.length
                          ? cells[row * crossAxisCount + col]
                          : null,
                      width: cellWidth,
                      height: cellHeight,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  String _iconKeyFor(int catId, List<Category> cats) {
    for (final c in cats) {
      if (c.id == catId) return c.icon;
    }
    return 'category';
  }

  Widget _buildCell({
    required ThemeData theme,
    required int index,
    required _CellData? cell,
    required double width,
    required double height,
  }) {
    final hasRight = (index % 3) != 2;
    if (cell == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
            right: hasRight
                ? BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  )
                : BorderSide.none,
          ),
        ),
      );
    }
    final total = expenses.fold<double>(0, (s, e) => s + e.amount);
    final pct = total > 0 ? (cell.amount / total * 100) : 0.0;
    final color = Color(cell.color);
    // 占比越高,背景越深 —— 视觉权重
    final bgAlpha = (0.04 + (pct / 100) * 0.18).clamp(0.04, 0.22);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
          right: hasRight
              ? BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                )
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  CategoryIcons.map[cell.iconKey] ?? Icons.category_rounded,
                  color: color,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    cell.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              '¥${Formatters.amount(cell.amount)}',
              style: const TextStyle(
                fontSize: 10,
                color: AppGray.g600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CellData {
  const _CellData({
    required this.name,
    required this.amount,
    required this.color,
    required this.iconKey,
  });
  final String name;
  final double amount;
  final int color;
  final String iconKey;
}