// lib/features/add/ui/widgets/category_grid.dart
// 4 列分类网格 —— 选中态加描边 + 浅色背景
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../ledger/application/transactions_providers.dart';
import '../../../../shared/constants/default_categories.dart';

class CategoryGrid extends ConsumerWidget {
  const CategoryGrid({
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
    return categoriesAsync.when(
      data: (cats) => GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: AppSpacing.s2,
          crossAxisSpacing: AppSpacing.s2,
          childAspectRatio: 1.0,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          final isSel = c.id == selected;
          final color = Color(c.color);
          return InkWell(
            onTap: () => onSelect(c.id),
            borderRadius: AppRadius.brLg,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s1),
              decoration: BoxDecoration(
                color: isSel
                    ? color.withValues(alpha: 0.12)
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.brLg,
                border: Border.all(
                  color: isSel ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CategoryIcons.map[c.icon] ?? Icons.category_rounded,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.name,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('分类加载失败:$e')),
    );
  }
}
