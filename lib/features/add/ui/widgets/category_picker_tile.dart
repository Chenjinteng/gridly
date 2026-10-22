// lib/features/add/ui/widgets/category_picker_tile.dart
// 分类选择 sheet 里的一格 —— icon + 分类名
//
// 2026-10-22 D64.97 从 `transaction_form.dart` 里内联的 GridView tile 抽出来。
//
// **为什么抽**:
//   - 之前那段 tile 是**内联**在 `_CategoryPickerSheet` 的 `itemBuilder` 里的,
//     没法写 widget test。
//   - D64.95 那轮我写的 `category_picker_rename_test.dart` 测的是
//     `lib/features/add/ui/widgets/category_grid.dart` —— 那个 widget 早期
//     (P1-2 commit e48a7b1)用过,但 `2d52fa1`(分类选择改成下拉)和
//     `e800c29`(分类入口合并到 SaveBar)之后 picker 改成了**内联 GridView**,
//     `CategoryGrid` 就成了**死代码** —— 测试等于没测到生产界面。
//   - 抽出来之后:① picker 和测试用**同一个实现** ② 以后改 tile 样式有测试兜着。
//     顺带删掉了死代码 `category_grid.dart`(2.0 线 `~/Documents/Projects/gridly/`
//     有自己一份,不受影响)。
//
// **本 commit 只做搬运,不改任何视觉**:label 还是单行 + ellipsis 截断。
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/constants/default_categories.dart';

/// 分类选择网格里的一格
class CategoryPickerTile extends StatelessWidget {
  const CategoryPickerTile({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(category.color);

    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s2),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CategoryIcons.map[category.icon] ?? Icons.category_rounded,
              color: color,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              category.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
