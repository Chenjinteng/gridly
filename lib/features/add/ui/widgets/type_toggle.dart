// lib/features/add/ui/widgets/type_toggle.dart
// 类型切换:支出 / 收入 / 调拨(可选) / 投入 / 收益(投资场景) / 借出 / 借入(负债场景)
//
// 2026-10-13 P7 重设计(ColorOS 14 Aquamorphic 滑动 pill):
//   滑动 pill 动画参考 features/stats/ui/widgets/range_tabs.dart(月/年切换):
//   - 外层 surfaceContainerLowest 底 + brPill 圆角
//   - Stack + AnimatedPositioned 单 pill 在 segment 之间水平滑动
//   - pill 由原"两 segment 自带 bg" 改为"共享 1 个 pill"(切 tab 不会两边 bg 同时 fade,
//     过渡"破碎"的观感问题修掉)
//   - duration = AppMotion.fast(240ms),curve = aquaIn(ColorOS 水感前快后慢)
//
// 2026-10-13 P8 重构:segments 完全由 caller 传入(支持 cash_flow + investment 两套)
//   - cash_flow:[('expense','支出',red),('income','收入',teal),('balance','调拨',softGold)]
//   - investment:[('input','投入',gold),('output','收益',gold),('transfer','调拨',softGold)]
//   - 全部 segment 自定义:label / icon / 颜色,caller 完全控制视觉系统
//
// 2026-10-14 D51 加:负债段 receivable 2 段(借出 / 借入)
//   - 替换之前 2 段(支出 / 收入)语义(支出/收入对负债账户语义错)
//   - 借出 lend_out:我是债权人,balance += amount
//   - 借入 borrow_in:我是负债方,balance -= amount
//   - 颜色:借出 = AppSegment.receivable (#F59E0B 橙);借入 = AppStatus.error (#EF4444 红,警示我欠)
//
// 颜色语义化(user UAT 反馈:支出/收入要"主题蓝色"):
//   - 支出 (expense) → AppStatus.error (#EF4444 红)
//   - 收入 (income)  → AppBrand.teal (#14B8A6 主题蓝)
//   - 调拨 (balance) → AppSecondary.softGold (#FFEAA7 浅金,中性,跟 income 区分)
//   - 投入 (input)   → AppBrand.gold (#F5BC1F 投资主题金,跟资产 'investment' 配色一致)
//   - 收益 (output)  → AppBrand.gold (#F5BC1F 投资主题金)
//   - transfer       → AppSecondary.softGold (浅金,跟 input/output 区分)
//   - 借出 (lend_out)→ AppSegment.receivable #F59E0B(负债段语义色)
//   - 借入 (borrow_in)→ AppStatus.error #EF4444(警示我欠)
//
// 业务规则(TransactionForm 内):
//   - cash_flow: type='expense' / 'income' / 'balance' 直接对应 DB
//   - investment: intent='input'/'output'/'transfer' 全部存 DB type='balance'
//     + destinationAccountId(commit ff440e0 加的列)表达 source→dest 流向
//   - receivable(D51): intent='lend_out'/'borrow_in' 直接对应 DB type('lend_out'/'borrow_in'),
//     accountId=负债账户,无 destinationAccountId(单账户操作,跟现金支出/收入同 pattern)
import 'package:flutter/material.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/card_shadows.dart';

/// toggle 单段配置(2026-10-13 P8 加)
class ToggleSegment {
  const ToggleSegment({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// 内部 key,也是 toggle value:
  ///   - cash_flow:'expense' / 'income' / 'balance' (与 DB type 直接对应)
  ///   - investment:'input' / 'output' / 'transfer' (commit ff440e0 后
  ///     TransactionForm 在 save() 里把这 3 个 key 都映射为 DB type='balance',
  ///     通过 destinationAccountId 区分 source→dest)
  final String key;

  /// 显示文字(支出 / 收入 / 调拨 / 投入 / 收益 / ...)
  final String label;

  /// 段内 icon(18dp)
  final IconData icon;

  /// 段主色(选中 pill bg tint + icon/label 文字色)
  final Color color;
}

class TypeToggle extends StatelessWidget {
  const TypeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.segments,
  });

  /// 当前选中段的 key
  final String value;

  /// 段切换回调,参数是选中段的 key
  final ValueChanged<String> onChanged;

  /// 段配置(2 或 3 段),由 caller 完全控制
  final List<ToggleSegment> segments;

  /// cash_flow 默认 segments(短按+ 默认)
  static const cashFlowSegments = <ToggleSegment>[
    ToggleSegment(
      key: 'expense',
      label: '支出',
      icon: Icons.arrow_outward_rounded,
      color: AppStatus.error, // #EF4444
    ),
    ToggleSegment(
      key: 'income',
      label: '收入',
      icon: Icons.south_west_rounded,
      color: AppBrand.teal, // #14B8A6
    ),
    ToggleSegment(
      key: 'balance',
      label: '调拨',
      icon: Icons.swap_horiz_rounded,
      color: AppSecondary.softGold, // #FFEAA7
    ),
  ];

  /// investment 默认 segments(长按+ 5 段选)
  static const investmentSegments = <ToggleSegment>[
    ToggleSegment(
      key: 'input',
      label: '投入',
      icon: Icons.arrow_upward_rounded,
      color: AppBrand.gold, // #F5BC1F 投资主题金
    ),
    ToggleSegment(
      key: 'output',
      label: '收益',
      icon: Icons.payments_rounded,
      color: AppBrand.gold,
    ),
    ToggleSegment(
      key: 'transfer',
      label: '调拨',
      icon: Icons.swap_horiz_rounded,
      color: AppSecondary.softGold,
    ),
  ];

  /// 2026-10-14 D51 v2 改:receivable 债务段 3 段(借出 / 借入 / 调拨)
  ///   - user 反馈"没看到有调拨,我认为调拨是直接在这里" ——
  ///     调拨(receivable ↔ 现金)跟借出/借入是同场景的 3 个动作,应该一起
  ///   - 借出 lend_out:单账户,我借出钱(我是债权人,balance += amount)
  ///   - 借入 borrow_in:单账户,我借到钱(我是负债方,balance -= amount)
  ///   - 调拨 transfer:双账户,债务 ↔ 现金 流转(收回借款 / 借入方还款)
  ///     DB type='balance',有 destinationAccountId,跟 cash_flow 调拨同 schema
  ///   - 颜色:借出 = #F59E0B 橙(中性正数);借入 = #EF4444 红(警示我欠);
  ///     调拨 = #FFEAA7 浅金(中性,跟 income 区分,跟 cash_flow 调拨一致)
  static const receivableSegments = <ToggleSegment>[
    ToggleSegment(
      key: 'lend_out',
      label: '借出',
      icon: Icons.north_east_rounded, // ↗ 出
      color: AppSegment.receivable, // #F59E0B
    ),
    ToggleSegment(
      key: 'borrow_in',
      label: '借入',
      icon: Icons.south_west_rounded, // ↙ 入
      color: AppStatus.error, // #EF4444
    ),
    ToggleSegment(
      key: 'transfer',
      label: '调拨',
      icon: Icons.swap_horiz_rounded, // 双向
      color: AppSecondary.softGold, // #FFEAA7
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIndex = segments.indexWhere((seg) => seg.key == value);
    final selectedColor = selectedIndex >= 0
        ? segments[selectedIndex].color
        : segments.first.color;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        // 2026-10-13 P7 UAT 改:brLg → brPill,跟下面 _ActionPill brPill 圆角保持一致
        //   之前 brLg=16 + 内部 pill brMd=12 看起来是 rounded rectangle 不够圆,
        //   跟下面 _actionRow 的 fully rounded pill 风格割裂
        borderRadius: AppRadius.brPill,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        // 2026-10-13 P7 UAT 加:极轻 pill 投影,增加"离开纸面"立体感
        // user:"想给这个切换以及所有按钮增加一点点投影,不然没立体感"
        boxShadow: CardShadows.pill(context),
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
                        label: seg.label,
                        icon: seg.icon,
                        selected: value == seg.key,
                        color: seg.color,
                        onTap: () => onChanged(seg.key),
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
/// 2026-10-13 P7 UAT 改(2 轮):
///   - 第 1 轮:Row 去掉 mainAxisSize.min,让 mainAxisAlignment.center 在全宽内居中
///   - 第 2 轮:再加 Center 包 Row 真正做"双向居中"—— 之前内容纵向偏上 7px
///     (Padding 没 alignment 参数,默认把 child 放左上,加上 vertical padding 8,
///      child Row 在 32px padding 区内 top-left,视觉上 pill bg 下方 7px 空白更大)
///     改后 Center 拿到全屏约束,把 Row 在 segment 内 vertical center 居中
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
      // 2026-10-13 P7 UAT 第 2 轮改:用 Center 替代 Padding
      //   - Center 给 child 松约束(max size = InkWell 全宽),
      //     child Row mainAxisSize 默认 max → Row 占满 segment 全宽,
      //     mainAxisAlignment.center 把 icon+gap+text 横向居中
      //   - Center 自身在 InkWell 内垂直 + 水平居中 → Row 双向居中
      //   - 去掉 vertical padding 8:之前 Padding 没 alignment,
      //     child 默认放左上 → 内容偏上 7px;改 Center 后垂直居中自然
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max, // 占满 segment 全宽,center 才有意义
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
