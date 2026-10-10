// lib/features/stats/ui/widgets/top_expenses.dart
// 报表页 Top 10 区域 —— 单笔 / 分类 两个 Tab 切换。
// 单笔:每行 = 分类图标 + 名字 + 日期 + 金额(降序前 10)
// 分类:复用 expenseByCategoryProvider,截取前 10,每行 = 图标 + 名字 + 金额 + 占比
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';
import '../../application/stats_providers.dart';

class TopExpenses extends ConsumerWidget {
  const TopExpenses({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Top 10 支出',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  TabBar(
                    isScrollable: true,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: const [
                      Tab(text: '单笔'),
                      Tab(text: '分类'),
                    ],
                    labelColor: AppBrand.teal,
                    unselectedLabelColor: AppGray.g600,
                    indicatorColor: AppBrand.teal,
                    dividerHeight: 0,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 520,
              child: const TabBarView(
                physics: NeverScrollableScrollPhysics(),
                children: [
                  _TopList(),
                  _TopByCategory(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopList extends ConsumerWidget {
  const _TopList();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(topExpensesProvider);
    final cats = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return topAsync.when(
      data: (txs) {
        if (txs.isEmpty) {
          return Column(
            children: List.generate(
              _slotCount,
              (i) => _EmptyRow(height: _rowHeight, slot: i + 1),
            ),
          );
        }
        return Column(
          children: [
            for (final t in txs.take(_slotCount))
              _DataRow(
                height: _rowHeight,
                color: _colorForCategory(t.categoryId, cats),
                iconKey: _iconKeyForCategory(t.categoryId, cats),
                primary: _categoryNameForCategory(t.categoryId, cats),
                secondary: t.note,
                trailing: '¥${Formatters.amount(t.amount)}',
                trailingSub: DateFormat('M月d日').format(t.occurredAt),
                trailingColor: AppStatus.error,
              ),
            // 不足 10 条,补空行 —— 浅灰显示 "#N" 占位序号
            for (int i = txs.length; i < _slotCount; i++)
              _EmptyRow(height: _rowHeight, slot: i + 1),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error))),
    );
  }
}

class _TopByCategory extends ConsumerWidget {
  const _TopByCategory();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    final cats = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return expensesAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        final top = data.take(_slotCount).toList();
        if (top.isEmpty) {
          return Column(
            children: List.generate(
              _slotCount,
              (i) => _EmptyRow(height: _rowHeight, slot: i + 1),
            ),
          );
        }
        return Column(
          children: [
            for (final e in top)
              _DataRow(
                height: _rowHeight,
                color: Color(e.color),
                iconKey: _iconKeyForCategory(e.categoryId, cats),
                primary: e.name,
                secondary: '${(e.amount / total * 100).toStringAsFixed(0)}%',
                trailing: '¥${Formatters.amount(e.amount)}',
                trailingColor: Color(e.color),
              ),
            // 不足 10 条,补空行 —— 浅灰显示 "#N" 占位序号
            for (int i = top.length; i < _slotCount; i++)
              _EmptyRow(height: _rowHeight, slot: i + 1),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error))),
    );
  }
}
// 固定高度的数据行(单笔 / 分类共用)
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.height,
    required this.color,
    required this.iconKey,
    required this.primary,
    this.secondary,
    required this.trailing,
    this.trailingSub,
    required this.trailingColor,
  });
  final double height;
  final Color color;
  final String iconKey;
  final String primary;
  final String? secondary;
  final String trailing;
  final String? trailingSub;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppGray.g100, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.brXs,
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Icon(
                CategoryIcons.map[iconKey] ?? Icons.category_rounded,
                color: color,
                size: 14,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primary,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary != null && secondary!.isNotEmpty)
                    Text(
                      secondary!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppGray.g600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: trailingColor,
                  ),
                ),
                if (trailingSub != null && trailingSub!.isNotEmpty)
                  Text(
                    trailingSub!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppGray.g600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 空行(占位,浅灰 "#N" 序号 + 顶部 0.5px 分隔线)
// 用途:数据不足 10 条时,补足行高,让卡片高度恒定,避免底部"留白"
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.height, required this.slot});
  final double height;
  final int slot; // 1-based
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppGray.g100, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '#$slot',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppGray.g400, // 浅灰,与数据行视觉区分
            ),
          ),
        ),
      ),
    );
  }
}

// 分类查找辅助(根据 categoryId 找 cat,fallback 默认)
Color _colorForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return Color(c.color);
  }
  return AppGray.g400;
}

String _iconKeyForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return c.icon;
  }
  return 'category';
}

String _categoryNameForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return c.name;
  }
  return '未分类';
}
