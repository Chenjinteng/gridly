// lib/features/ledger/ui/filter_picker_sheets.dart
// 流水页"高级筛选"和 3-dropdown 横滚条 共用的 picker 弹层组件。
//
// 抽出来的目的:让 ledger_page.dart(in-page _FilterBar)和 advanced_filter_page.dart
//   (全屏高级筛选)都能用同一套底部 modal sheet picker,避免重复实现。
//
// 设计:
//   - SheetDismissed sentinel — barrier dismiss / "关闭"按钮(没操作)用
//   - AllPicked sentinel — 用户明确点"全部"项(等价 reset 到默认值)用
//   - showSingleSelectSheet<T> — 单选 list(类型 / 月份),DraggableScrollableSheet
//     2026-10-13 P10 加底部"显示全部" FilledButton,匹配 MultiSelect 同款视觉
//     2026-10-13 P11 改:list 自动过滤掉 AllPicked 项(底部按钮已替代表达"全部")
//       - "类型" 4 项 → 列表 3 项(支出/收入/调拨)+ 底部"显示全部"
//       - "月份" 7+ 项 → 列表 N 项月 + 底部"显示全部",sheet
//         用 DraggableScrollableSheet(0.7/0.4/0.9)→ 长 list 可拖拽
//         调高度 + ListView 内部滑动
//   - MultiSelectCategorySheet — 多选 list(分类),DraggableScrollableSheet
//   - MultiSelectAssetSheet — 多选 list(账户),DraggableScrollableSheet
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

/// Sentinel —— ModalBottomSheet dismiss 时返回,跟"选了全部"区分开
class SheetDismissed {
  const SheetDismissed();
}

const sheetDismissed = SheetDismissed();

/// Sentinel —— 用户明确点了"全部"项(等价于 reset 到默认值)
class AllPicked {
  const AllPicked();
}

const allPicked = AllPicked();

/// 单选弹层(类型 / 月份)—— 选完自动关闭
///
/// ⚠️ 关键修复:用两个 sentinel 严格区分:
///   - SheetDismissed → barrier dismiss / "关闭"按钮(没操作)
///   - AllPicked → 用户明确点"全部"(要 reset 到默认值)
///   - 其他 value → 用户点了某个具体选项
/// 选项用 `Object?` 而非 T,因为"全部"用 sentinel 不能跟 T 类型混
///
/// 2026-10-12 P5:showGeneralDialog → showModalBottomSheet(底部 modal sheet 风格)
///
/// 2026-10-13 P11:showModalBottomSheet + Flexible(shrinkWrap) →
///   DraggableScrollableSheet(0.7/0.4/0.9)→ P12 退回 fixed SizedBox
///   - P11 反馈"已经有显示全部按钮了,就不用在滚动里面有'全部'的选项"
///     → list 过滤 AllPicked,底部"显示全部"按钮作为唯一"全部"入口
///   - P12 反馈"不要做什么还能往上滑动的操作了"→ 放弃 DraggableScrollableSheet
///     → SizedBox 固定 0.7 * screenHeight,不可上滑,内部 ListView 自带滚动
///     (长 list 仍能看,只是 sheet 高固定)
Future<Object?> showSingleSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<(Object?, String)> options,
  required T currentValue,
}) {
  // 2026-10-13 P11:list 过滤掉 AllPicked 项 → 不与底部"显示全部"按钮重复
  final listOptions = options.where((o) => o.$1 is! AllPicked).toList();
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      // 2026-10-13 P12 UAT:固定 sheet 高 = 0.7 * screenHeight
      //   不用 DraggableScrollableSheet,user:"不要做什么还能往上滑动的操作了"
      //   内部 ListView 自带滚动(超长 list 仍能看,只是 sheet 高固定)
      final sheetHeight = MediaQuery.sizeOf(ctx).height * 0.7;
      return SafeArea(
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              // 把手(visual only,不可拖)
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, sheetDismissed),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: listOptions.length,
                  itemBuilder: (_, i) {
                    final (value, label) = listOptions[i];
                    // 2026-10-13 P11:AllPicked 已不在 list,只比 value == currentValue
                    final selected = value == currentValue;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                          vertical: AppSpacing.s3,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // 2026-10-13 P10:"显示全部"快捷键 — 单选列表无需"清空",
              //   但要保留底部 FilledButton 跟 MultiSelect 同款视觉
              //   tap → pop AllPicked → caller 已 handle(等价 reset 到默认值)
              // 2026-10-13 P11:list 已过滤掉 AllPicked,按钮是"全部"的唯一入口
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s3,
                  AppSpacing.s4,
                  AppSpacing.s3,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, allPicked),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? AppSecondary.cream
                          : AppBrand.ink,
                      foregroundColor: isDark ? AppBrand.ink : null,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.brLg,
                      ),
                    ),
                    child: const Text(
                      '显示全部',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 多选弹层(分类)—— 临时持有选择集合,点"确定"才提交
class MultiSelectCategorySheet extends StatefulWidget {
  const MultiSelectCategorySheet({
    super.key,
    required this.categories,
    required this.initial,
  });
  final List<Category> categories;
  final Set<int> initial;

  @override
  State<MultiSelectCategorySheet> createState() =>
      _MultiSelectCategorySheetState();
}

class _MultiSelectCategorySheetState extends State<MultiSelectCategorySheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择分类(可多选)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.categories.length,
                itemBuilder: (_, i) {
                  final c = widget.categories[i];
                  final checked = _selected.contains(c.id);
                  final color = Color(c.color);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(c.id);
                      } else {
                        _selected.add(c.id);
                      }
                    }),
                    child: Container(
                      color: checked
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (checked)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                  ),
                  child: Text(
                    _selected.isEmpty ? '显示全部' : '确定(${_selected.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 2026-10-12 P3 commit 加:多选弹层(资产)—— 跟 MultiSelectCategorySheet 同款结构
///   - 行 item:asset icon chip + name + 选中态:整行背景 tint + check icon
class MultiSelectAssetSheet extends StatefulWidget {
  const MultiSelectAssetSheet({
    super.key,
    required this.assets,
    required this.initial,
  });
  final List<Asset> assets;
  final Set<int> initial;

  @override
  State<MultiSelectAssetSheet> createState() => _MultiSelectAssetSheetState();
}

class _MultiSelectAssetSheetState extends State<MultiSelectAssetSheet> {
  late Set<int> _selected;

  IconData _iconFor(String iconKey) {
    switch (iconKey) {
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      case 'swap_horiz':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择账户(可多选)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.assets.length,
                itemBuilder: (_, i) {
                  final a = widget.assets[i];
                  final checked = _selected.contains(a.id);
                  final color = Color(a.color);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(a.id);
                      } else {
                        _selected.add(a.id);
                      }
                    }),
                    child: Container(
                      color: checked
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              _iconFor(a.icon),
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: Text(
                              a.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (checked)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                  ),
                  child: Text(
                    _selected.isEmpty ? '显示全部' : '确定(${_selected.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
