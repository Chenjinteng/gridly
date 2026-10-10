// lib/features/add/ui/widgets/category_selector.dart
// 分类选择器:点击 → 弹底部 ListView 选择,选完自动关
// 替代 4 列网格(避免 17 个分类挤在屏幕里)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';

class CategorySelector extends ConsumerWidget {
  const CategorySelector({
    super.key,
    required this.type,
    required this.selected,
    required this.onSelect,
  });
  final String type;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesByTypeProvider(type));
    final theme = Theme.of(context);
    return categoriesAsync.when(
      data: (cats) {
        Category? current;
        for (final c in cats) {
          if (c.id == selected) {
            current = c;
            break;
          }
        }
        final hasSelection = current != null;
        return InkWell(
          onTap: () => _openPicker(context, cats),
          borderRadius: AppRadius.brLg,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: hasSelection
                    ? Color(current.color)
                    : theme.colorScheme.outlineVariant,
                width: hasSelection ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              children: [
                if (hasSelection) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(current.color).withValues(alpha: 0.12),
                      borderRadius: AppRadius.brXs,
                      border: Border.all(
                        color: Color(current.color).withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      CategoryIcons.map[current.icon] ??
                          Icons.category_rounded,
                      color: Color(current.color),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '点击换分类',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppGray.g600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.category_outlined,
                    color: AppGray.g400,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  const Expanded(
                    child: Text(
                      '选个分类',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppGray.g600,
                      ),
                    ),
                  ),
                ],
                const Icon(
                  Icons.expand_more,
                  size: 22,
                  color: AppGray.g400,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text(
          '分类加载失败:$e',
          style: const TextStyle(color: AppStatus.error),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context, List<Category> cats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _CategoryPickerSheet(
        categories: cats,
        selected: selected,
        onSelect: (id) {
          onSelect(id);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });
  final List<Category> categories;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题 + 计数
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选分类',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${categories.length} 个',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppGray.g600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final isSel = c.id == selected;
                  final color = Color(c.color);
                  return InkWell(
                    onTap: () => onSelect(c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? color.withValues(alpha: 0.10)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              CategoryIcons.map[c.icon] ??
                                  Icons.category_rounded,
                              color: color,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSel
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSel ? color : null,
                              ),
                            ),
                          ),
                          if (isSel)
                            Icon(Icons.check_circle, color: color, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
