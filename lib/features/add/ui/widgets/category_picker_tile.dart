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
//
// **D64.97 需求(user UAT 截图)**:分类名太长时不要 ellipsis 截断
// (「加餐零…」「咖啡下…」「房租水…」),改成**换行**完整显示,
// 同时**每个小卡片的大小不变**。
//
// **怎么做到卡片不变还能放 2 行**:
//   - 卡片尺寸由 grid 的 `childAspectRatio: 0.85` 决定(改的是内部排版,不是比例)
//   - tile 内部:padding 8 + icon 26 + gap 4 + label 2 行 × (12 × 1.2) = 28.8
//     → 合计 66.8dp,而 tile 高 = 宽 / 0.85 ≈ 85dp(360dp 屏上 76dp 宽)
//     → 还有 ~18dp 余量,2 行放得下
//   - **关键是 label 区域要固定 2 行高**(SizedBox),否则 1 行的分类和 2 行的
//     分类会让 icon 在同一行里高低不齐(Column 居中 + 内容高度不定 = 图标乱跳)。
//     固定高度后 Column 高度恒定 → 所有 tile 的 icon 和 label 第一行都在同一基线上。
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
    this.maxLabelLines = 2,
    this.isDropTarget = false,
  });

  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  /// 分类名最多占几行。2 = 长名换行完整显示(schema 允许 16 字,
  /// 超长时仍会 ellipsis 兜底,不会溢出卡片)
  final int maxLabelLines;

  /// 2026-10-22 D64.98 加:当前是长按拖动的**落点**(拖到这里会插到这一格的位置)
  ///
  /// 用主题 primary(青 / 粉随主题)而不是分类自己的颜色:
  /// 分类色已经被「选中态」占用了,再用一次分不清是"选中了"还是"要放这儿"。
  final bool isDropTarget;

  /// label 的行高倍数(固定值 → 每行高度确定 → 2 行盒高确定)
  static const double _labelLineHeightFactor = 1.2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(category.color);
    final accent = theme.colorScheme.primary;

    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s2),
        decoration: BoxDecoration(
          color: isDropTarget
              ? accent.withValues(alpha: 0.12)
              : isSelected
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: isDropTarget
                ? accent
                : isSelected
                ? color
                : theme.colorScheme.outlineVariant,
            width: isDropTarget || isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          // 内容高度固定(下面的 label 盒高固定)→ 图标在所有 tile 里位置一致
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CategoryIcons.map[category.icon] ?? Icons.category_rounded,
              color: color,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.s1),
            // 固定 N 行高的盒子:1 行的分类名跟 2 行的分类名,第一行基线一致
            SizedBox(
              height: 12 * _labelLineHeightFactor * maxLabelLines,
              child: Text(
                category.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: _labelLineHeightFactor,
                ),
                maxLines: maxLabelLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
