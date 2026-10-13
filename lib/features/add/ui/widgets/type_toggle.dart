// lib/features/add/ui/widgets/type_toggle.dart
// 类型切换:支出 / 收入 / 调拨(可选)
//
// 2026-10-13 P7 重设计:ColorOS 14 Aquamorphic pill segmented 风格
//   - user UAT:之前 Material SegmentedButton "丑了不搭",要"按 ColorOS UI 重做"
//   - 弃用 SegmentedButton(默认 Material 灰底胶囊,选中色 contrast 太硬)
//   - 自定义 pill toggle:
//     * 外层 48dp 圆角胶囊(brPill 24 = 半高)
//     * 背景 surfaceContainerLowest(干净白底),1px outlineVariant 边框
//     * 内嵌 3 段(expense / income / 调拨),等宽 Expanded
//   * 选中段:gold 18% 底色 + 选中滑入动画(AnimatedContainer 250ms,ColorOS 略快于通用 motion)
//   * 未选段:透明 + onSurfaceVariant 灰文字
//   * 每段:icon(18dp) + label(14sp / w500 → w700 选中)
//   * 点击整段(onTap + HitTestBehavior.opaque,无 splash 但 InkingWell 上层用 GestureDetector)
//   - 保留 allowBalance 参数(短按 2 段 / 长按 3 段)
//
// 业务规则(TransactionForm 内):
//   - type='expense' / 'income' → 计入月度汇总(已花 / 收入)
//   - type='balance' → 不计入月度汇总,仅算对应资产 currentBalance 变动
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';

class TypeToggle extends StatelessWidget {
  const TypeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowBalance = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowBalance;

  /// 3 段配置(顺序按查看频度:支出 > 收入 > 调拨)
  static const _baseOptions = [
    ('expense', '支出', Icons.arrow_outward_rounded),
    ('income', '收入', Icons.south_west_rounded),
  ];
  static const _balanceOption = ('balance', '调拨', Icons.swap_horiz_rounded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = allowBalance
        ? [..._baseOptions, _balanceOption]
        : _baseOptions;

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // 外层干净底,让内嵌选中段"浮起"产生 AquaMorph 水感
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.brPill,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          for (final seg in segments)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(seg.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    // 选中:gold 18% tint(跟"保存"按钮 / "默认" chip 同款金)
                    // 2026-10-13 P7:沿用 AppBrand.gold,不再用 SegmentedButton 的 primary,
                    // 视觉更温润,跟 gridly 整体 AquaMorph 调性一致
                    color: value == seg.$1
                        ? AppBrand.gold.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        seg.$3,
                        size: 18,
                        color: value == seg.$1
                            ? AppBrand.gold
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        seg.$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: value == seg.$1
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: value == seg.$1
                              ? AppBrand.gold
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}