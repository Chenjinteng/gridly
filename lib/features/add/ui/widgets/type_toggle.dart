// lib/features/add/ui/widgets/type_toggle.dart
// 类型切换:支出 / 收入 / 调拨(可选)
//
// 2026-10-13 P7 重设计(ColorOS 14 Aquamorphic 滑动 pill):
//   滑动 pill 动画参考 features/stats/ui/widgets/range_tabs.dart(月/年切换):
//   - 外层 surfaceContainerLowest 底 + brLg 圆角
//   - Stack + AnimatedPositioned 单 pill 在 segment 之间水平滑动
//   - pill 由原"两 segment 自带 bg" 改为"共享 1 个 pill"(切 tab 不会两边 bg 同时 fade,
//     过渡"破碎"的观感问题修掉)
//   - duration = AppMotion.fast(240ms),curve = aquaIn(ColorOS 水感前快后慢)
//
// 颜色语义化(user UAT 反馈:支出/收入要"主题蓝色"):
//   - 支出 (expense) → AppStatus.error (#EF4444 红)
//   - 收入 (income)  → AppBrand.teal (#14B8A6 主题蓝)
//   - 调拨 (balance) → AppSecondary.softGold (#FFEAA7 浅金,中性,跟 income 区分)
// 收入色改 teal 是为跟 AmountDisplay 数字色 + "保存"按钮 + today pill 形成视觉系统。
//
// 业务规则(TransactionForm 内):
//   - type='expense' / 'income' → 计入月度汇总(已花 / 收入)
//   - type='balance' → 不计入月度汇总,仅算对应资产 currentBalance 变动
import 'package:flutter/material.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

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

  /// 语义色:type 名 → 主色 + 18% tint bg
  /// 支出 = 红(强调"花钱出去"),收入 = 主题蓝(强调"钱进来"),调拨 = 浅金(中性,跟 income 区分)
  static Color _primaryFor(String type) {
    switch (type) {
      case 'expense':
        return AppStatus.error; // #EF4444
      case 'income':
        return AppBrand.teal; // #14B8A6
      default:
        return AppSecondary.softGold; // balance / #FFEAA7
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = allowBalance
        ? [..._baseOptions, _balanceOption]
        : _baseOptions;
    final selectedIndex = segments.indexWhere((seg) => seg.$1 == value);
    final selectedColor = _primaryFor(value);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        // 2026-10-13 P7 UAT 改:brLg → brPill,跟下面 _ActionPill brPill 圆角保持一致
        //   之前 brLg=16 + 内部 pill brMd=12 看起来是 rounded rectangle 不够圆,
        //   跟下面 _actionRow 的 fully rounded pill 风格割裂
        borderRadius: AppRadius.brPill,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final segWidth = c.maxWidth / segments.length;
          return Stack(
            children: [
              // 滑动 pill:在 segment 之间水平移动
              // - horizontal 4 + vertical 4 inset,pill 略小于 segment
              // - color 用当前 type 语义色 18% tint(pill 在 segment 间滑动时,
              //   颜色会随 type 切换改变 → 配合 AnimatedPositioned 实现"换色"动画)
              // - 2026-10-13 P7 UAT 改:brMd → brPill,跟外层 + 下面 _ActionPill 风格统一
              AnimatedPositioned(
                duration: AppMotion.fast,
                curve: AppMotion.aquaIn,
                left: segWidth * selectedIndex + 4,
                top: 4,
                bottom: 4,
                width: segWidth - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: 0.18),
                    borderRadius: AppRadius.brPill,
                  ),
                ),
              ),
              // 3 segment 本体(无 bg,只文字 + icon)
              Row(
                children: [
                  for (final seg in segments)
                    Expanded(
                      child: _Segment(
                        label: seg.$2,
                        icon: seg.$3,
                        selected: value == seg.$1,
                        color: _primaryFor(seg.$1),
                        onTap: () => onChanged(seg.$1),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 单段 tab —— 只是文字 + icon,选中态背景由父级 Stack 的共享 pill 提供。
/// 文字色:每段用对应语义色,选中 w700,未选 onSurfaceVariant 灰
///
/// 2026-10-13 P7 UAT 改:Row 用 mainAxisSize.max(默认),让 mainAxisAlignment.center
///   把 icon+gap+text 真正居中(之前 mainAxisSize.min 把 Row 缩到内容宽,视觉上
///   "内容居中"但 pill bg 宽度大于内容 → 内容看起来偏左)
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      // 2026-10-13 P7 UAT 改:brMd → brPill,跟外层 pill bg 圆角一致
      //   ripple 半径跟着 pill bg 走,视觉上 ripple 像 pill 内部高光
      borderRadius: AppRadius.brPill,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          // 去掉 mainAxisSize.min,让 Row 占满 InkWell 全宽,
          //   mainAxisAlignment.center 才会真正把 icon+text 居中
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              curve: AppMotion.aquaIn,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : theme.colorScheme.onSurfaceVariant,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
