// lib/features/ledger/ui/widgets/monthly_summary.dart
// 月度汇总 —— 设计成"Excel 工作表"风格,呼应"格子"主题:
//   - 顶部 sheet title(深色底 + 金色 1.5px 下边 + LOGO + 月份)
//   - 主数字区(深色底):本月结余大字
//   - 收入 / 支出两个 cell(等高,IntrinsicHeight 强制),中间 1px 分隔线
//   - 日均支出行(底部独立小行),防止 cell 内容不对称导致底不齐
//
// D70.3 改(user 1.0.1 装机实测反馈,跟 D64.51/D70 反反复复到现在):
//   - user 实际要的:global 决定默认 hidden,home 按钮能临时 toggle,
//     切 tab 时 home 的 local state 重置
//   - 公式:hidden = global ^ localVisible(XOR)
//     · global=开 + local=开(true,默认) = 显示
//     · global=开 + local=关(点了一次) = 隐藏(local 临时遮蔽)
//     · global=关 + local=开(true,默认) = 隐藏(看 global)
//     · global=关 + local=关(点了一次) = 显示(local 临时突破 global)
//   - local state 提升到 HomePage 层(原来是 D64.51 的 StateProvider + D70
//     第一稿的 MonthlySummary 自己持有 widget-local,导致 MonthlySummary 和
//     BudgetProgress 行为分裂,点月度汇总卡眼睛按钮预算卡不变)
//   - 当前 MonthlySummary 改回 ConsumerWidget,localVisible / onToggleLocal
//     从 HomePage 注入;BudgetProgress 同理从 HomePage 注入同一个 localVisible
//     这样两张卡行为一致(同月隐藏 / 同月显示)
//   - 切 tab 走 shell AnimatedSwitcher -> 旧 HomePage widget 销毁,新 HomePage
//     initState 把 _localVisible 重置为 true,"当前生效"语义自然实现
//   - 删 homeAmountVisibilityProvider / combineAmountVisibilityProvider,
//     直接用 amountVisibilityProvider(global)+ props 传入的 localVisible 计算 hidden
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/settings/amount_visibility_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/theme/gridly_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/gridly_mark.dart';
import '../../application/transactions_providers.dart';

class MonthlySummary extends ConsumerWidget {
  const MonthlySummary({
    super.key,
    required this.localVisible,
    required this.onToggleLocal,
  });

  /// D70.3:HomePage 持有的 widget-local "显示金额" 状态
  ///   - 默认 true(跟 global 默认一致)
  ///   - 切 tab 时 HomePage widget 销毁重建,自动 reset
  final bool localVisible;

  /// D70.3:MonthlySummary 持有的眼睛按钮 onTap → HomePage._toggleLocal,
  ///   通过 prop 注入,让 MonthlySummary 自己 stateless
  final VoidCallback onToggleLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);
    // D70.3:hidden = globalVisible ^ localVisible (XOR)
    //   - global 决定默认,local 临时 toggle
    //   - 真值表见文件头
    final globalVisible = ref.watch(amountVisibilityProvider);
    final hidden = globalVisible ^ localVisible;
    // D70.3:按钮文字/icon 基于 local(不是 global),按钮状态反映 local
    final homeHidden = !localVisible;
    final now = DateTime.now();
    final sheetTitle = '${now.year}年${now.month}月';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 日均支出 = 当月支出 / 当日已过天数(月初时 = 当日)
    final dailyAvg = now.day > 0 ? summary.expense / now.day : summary.expense;

    // 金额文本:隐藏时显示「¥ •••••」占位(位数感保留),不暴露具体数字
    // withUnit=false → 数字不带"万",由"万"作为单独 TextSpan 在大数字右侧补上
    // (cells 由本小 label `收入(万元)` 已声明单位,不需要再带)
    String amountText(double v) =>
        hidden ? '••••••' : '¥${Formatters.amount(v, withUnit: false)}';

    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        // D71.3:rim light 用 onInkSurface(cream)
        border: Border.all(
          color: theme
              .extension<GridlyPalette>()!
              .onInkSurface
              .withValues(alpha: isDark ? 0.08 : 0.15),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部 sheet title(浅色底)
            // D71.3:背景永远 ink(默认黑 / 粉色 → 深紫红)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: theme.extension<GridlyPalette>()!.inkSurface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.secondary,
                    width: 1.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // LOGO 三色方块 mark(深色底上,Ink → cream)
                      const GridlyMark(size: 26, onDark: true),
                      const SizedBox(width: AppSpacing.s2),
                      Text(
                        sheetTitle,
                        style: TextStyle(
                          color: theme.extension<GridlyPalette>()!.onInkSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  // 眼睛按钮 —— 切换金额显示/隐藏
                  // D70.3:onTap 调 onToggleLocal (HomePage.setState),不再 toggle
                  //   全局(避免 user 反馈 bug:点首页按钮同时关掉"我的"页那个
                  //   全局开关)
                  // D70.3:按钮文字/icon 基于 localVisible(不是 global hidden),
                  //   按钮状态反映 local 状态,global 切换不影响按钮显示
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onToggleLocal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            homeHidden ? '显示金额' : '本月结余',
                            style: TextStyle(
                              color: homeHidden
                                  ? theme.extension<GridlyPalette>()!.onInkSurface
                                  : theme.extension<GridlyPalette>()!.onInkSurface
                                      .withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: homeHidden
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            homeHidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 14,
                            color: homeHidden
                                ? theme.extension<GridlyPalette>()!.onInkSurface
                                : theme.extension<GridlyPalette>()!.onInkSurface
                                    .withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 主体:大数字区
            // D71.3:永远 ink
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              color: theme.extension<GridlyPalette>()!.inkSurface,
              child: Align(
                alignment: Alignment.centerLeft,
                // 余额同样可能接近 9999999.99(7 位整数 + 2 位小数),
                // 用 FittedBox.scaleDown 兜底防止极端情况下换行成两行
                // 万 mode 下主体右侧追加小号灰色"(万元)"作为单位标记,
                // 跟 cells 的 `收入(万元)` label 风格一致 —— 视觉系统里
                // 单位统一是带 parens 的 `(万元)` 形式,只是大小不同
                // (cells fontSize 11 vs main 30;大数字旁用 14 折中)
                // text 前导一个空格(继承 fontSize 14 ≈ 4px),给数字和单位
                // 标记之间一点呼吸空间,避免 `999.99(万元)` 这种贴脸感
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: amountText(summary.balance)),
                        // 万元 mode + 可见时:小号灰"(万元)"作单位标记
                        // 灰色固定,因为单位标记是"信息"非"信号";
                        // 信号(正/负)在主数字颜色上
                        if (!hidden && Formatters.unit(summary.balance) == '万元')
                          TextSpan(
                            text: ' (万元)', // 前导空格 ≈ 4px 呼吸
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.extension<GridlyPalette>()!.onInkSurface
                                  .withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      // D71.5.7:在默认主题 / 白天+粉色时代,这部分
                      //   焦 ink 卡是 #0F1419 黑 / #4A1942 冷紫,
                      //   balanceFor 的 teal/error/cream 三色都 readable
                      //   所以保持原逻辑
                      color: hidden
                          ? theme.extension<GridlyPalette>()!.onInkSurface
                              .withValues(alpha: 0.6)
                          : AppSemantic.balanceFor(summary.balance),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            // 收入 / 支出 两列 cell(等高,内容对称)
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Cell(
                      // 隐藏金额时不加单位后缀(避免误导);可见时按值动态加 (元)/(万元)
                      label: hidden
                          ? '收入'
                          : Formatters.labelledUnit('收入', summary.income),
                      amount: hidden ? null : summary.income,
                      // D71.2:收入色跟随 palette(浅粉 → 亮粉,默认 → 金黄)
                      color: theme.colorScheme.secondary,
                      showDivider: true,
                    ),
                  ),
                  Expanded(
                    child: _Cell(
                      label: hidden
                          ? '支出'
                          : Formatters.labelledUnit('支出', summary.expense),
                      amount: hidden ? null : summary.expense,
                      color: AppStatus.error,
                      showDivider: false,
                    ),
                  ),
                ],
              ),
            ),
            // 日均支出行(独立底部,避免两 cell 内容不对齐)
            // D71.3:永远 ink
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: theme.extension<GridlyPalette>()!.inkSurface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.secondary,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    // 动态单位后缀
                    hidden ? '日均支出' : Formatters.labelledUnit('日均支出', dailyAvg),
                    style: TextStyle(
                      color: theme.extension<GridlyPalette>()!.onInkSurface
                          .withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    hidden
                        ? '••••••'
                        : '¥${Formatters.amount(dailyAvg, withUnit: false)}',
                    style: TextStyle(
                      color: hidden
                          ? theme.extension<GridlyPalette>()!.onInkSurface
                              .withValues(alpha: 0.6)
                          : AppStatus.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.amount,
    required this.color,
    required this.showDivider,
  });
  final String label;

  /// null = 隐藏(显示 ••••••)
  final double? amount;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<GridlyPalette>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      // D71.3:永远 ink
      decoration: BoxDecoration(
        color: palette.inkSurface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.secondary, // cell 顶线
            width: 0.5,
          ),
          // 收入 cell 才有分隔线 —— 画在 RIGHT 边,自然落在两 cell 中间。
          // 之前写在 LEFT 边时,分隔线落在卡片最左内边缘,跟 rim light border
          // (0.08 alpha 白边)紧挨成两条平行线,中间 收入/支出 之间反而没线
          // —— 截图里红框高亮的就是这条错位的竖线
          //
          // 2026-10-11 UAT:改成跟卡片内 3 条品牌金横线同色 + 同宽,
          // 整张卡 4 条分隔线 = 同一种语言,不再"横金竖灰"混杂。
          right: showDivider
              ? BorderSide(
                  color: Theme.of(context).colorScheme.secondary, // 跟 card 顶/cell 顶/cell 底 3 条金横线一致
                  width: 0.5,
                )
              : BorderSide.none,
        ),
      ),
      child: Column(
        // stretch 让金额 FittedBox 拿到 cell 的真实可用宽度,
        // 否则 FittedBox 会按字面 intrinsic 撑开,失去限宽意义
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.onInkSurface.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpacing.s05),
          // 数字 length 受"7 位整数 + 2 位小数"语义上限保护(走 transaction_form),
          // 极端值 ¥9,999,999.99 在窄屏会撑爆 cell —— scaleDown 自动按比例缩,
          // 小金额(如 ¥123.45)按原字号渲染,大金额等比缩小,不换行成两行
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount == null
                  ? '••••••'
                  : '¥${Formatters.amount(amount!, withUnit: false)}',
              style: TextStyle(
                color: amount == null
                    ? palette.onInkSurface.withValues(alpha: 0.6)
                    : color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}