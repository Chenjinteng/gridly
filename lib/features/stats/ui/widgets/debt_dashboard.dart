// lib/features/stats/ui/widgets/debt_dashboard.dart
// 报表"资产"视角 —— 债务情况 tabbed 卡片(负债 | 借出)
//
// 2026-10-16 D64.64 加(user UAT 反馈):
//   - user 反馈"我感觉,负债和借出这两个卡片可以合起来用一个 tab 切换的方式,
//     卡片名就叫债务情况,两个tab,负债|借出"
//   - 之前 D64.56/D64.62 是两张独立卡片,合并成 1 张 tabbed 卡片
//
// 2026-10-16 D64.66 重写(user UAT 反馈 + 上一版崩溃):
//   - user 上机验证 D64.64 装 0.1.0+12 后"资产报表整页空白"
//   - 根因:D64.64 用 `DefaultTabController` + `TabBar` + `TabBarView`,
//     而 TabBarView 必须在父级给它一个 bounded height 才能渲染
//     (Container 在 ListView 内是 unbounded,TabBarView 抛
//     "Vertical viewport was given unbounded height" → 整个 case
//     StatsView.assets 的 widgets 列表 build 失败 → 整张 body 空白)
//   - 修法:不用 Flutter TabBar widget,改成自维护 `_selectedIndex` +
//     自定义 `_DebtTabSegmented`(参考 stats_page _CompactViewSegmented
//     风格 — Row + AnimatedPositioned underline 横条滑动)+ 直接
//     `if (_index == 0) ... else ...` 切 body(用 Column 不需要 bounded
//     height)
//   - 设计要点保留 D64.64:
//     - ink 底 + 1px outline + CardShadows.dark(警示色,跟负债语义一致)
//     - 标题"债务情况"在卡片顶部
//     - 2 段 tab("负债" | "借出"),选中 teal 友好色
//     - body 切 LiabilitiesDashboard(警示红字) / ReceivablesDashboard(teal 字)
//
// 设计要点:
//   - 不复用 Flutter TabBar widget(避免 unbounded height 异常)
//   - 自维护 `_selectedIndex`,用 setState 切 tab
//   - underline 滑动 240ms aquaIn(跟 _CompactViewSegmented 同款"丝滑切换")
//   - body 用 if/else conditional render,切 tab 时数字动画重新触发
//     (符合 D64.62 设计:数字动画做"警示/友好"反馈)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/theme/gridly_palette.dart';
import 'liabilities_dashboard.dart';
import 'receivables_dashboard.dart';

/// 报表"债务情况" tabbed 卡片
///   - 1 张卡片(ink 底)+ 2 个 tab 切换(负债 | 借出)
///   - body 切 LiabilitiesDashboard / ReceivablesDashboard 两个纯 body
class DebtDashboard extends ConsumerStatefulWidget {
  const DebtDashboard({super.key});

  @override
  ConsumerState<DebtDashboard> createState() => _DebtDashboardState();
}

class _DebtDashboardState extends ConsumerState<DebtDashboard> {
  /// 当前 tab(0 = 负债 / 1 = 借出)
  int _index = 0;

  static const _options = <String>['负债', '借出'];

  // 几何:每段固定 56px,underline 横条 24px 居中(跟 stats_page _CompactViewSegmented 同款)
  static const double _segW = 56;
  static const double _underlineW = 24;
  static const double _underlineH = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        // ink 底警示色,跟原 LiabilitiesDashboard 一致 — user 切到"负债"
        // tab 看到警示红字数字,切到"借出" tab 看到 teal 字数字,警示色/
        // 友好色都包在同一个 ink 卡片里,user 一眼区分
        color: theme.extension<GridlyPalette>()!.inkSurface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: theme.extension<GridlyPalette>()!.onInkSurface.withValues(
            alpha: isDark ? 0.08 : 0.15,
          ),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 卡片顶部 row:左侧标题"债务情况" + 右侧自定义 tab segmented
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 标题"债务情况"(D64.64:user 明确卡片名)
                const Text(
                  '债务情况',
                  style: TextStyle(
                    color: AppGray.g400,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                // 自定义 tab segmented(2 段 + 共享 underline 横条)
                SizedBox(
                  height: 36,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 2 段文字 row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < _options.length; i++)
                            SizedBox(
                              width: _segW,
                              child: _DebtTabSegment(
                                label: _options[i],
                                selected: i == _index,
                                onTap: () => setState(() => _index = i),
                              ),
                            ),
                        ],
                      ),
                      // 共享 underline indicator — 240ms aquaIn 滑动
                      AnimatedPositioned(
                        duration: AppMotion.fast,
                        curve: AppMotion.aquaIn,
                        left: _index * _segW + (_segW - _underlineW) / 2,
                        bottom: 0,
                        width: _underlineW,
                        height: _underlineH,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // body(2 个 tab 切换)— D64.66:用 if/else conditional render,
          //   不用 IndexedStack(避免 ListView unbounded height 异常),
          //   不用 TabBarView(同上),切 tab 时子 widget 重新 build,
          //   数字动画重新触发(符合 D64.62 设计:数字滚动做"警示/友好"反馈)
          // 2026-10-16 D64.72 修:外层共享同一个 Padding + body widget
          //   if/else,改 padding 改 1 处(之前两个一样 padding 容易漏改 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s4,
            ),
            child: _index == 0
                ? const LiabilitiesDashboard()
                : const ReceivablesDashboard(),
          ),
        ],
      ),
    );
  }
}

/// 单段 tab — 纯 GestureDetector + AnimatedDefaultTextStyle
///   - 选中:teal 加粗(友好色跟"借出"语义匹配)
///   - 未选中:onSurfaceVariant
///   - 无 splash / 无 InkWell ripple(避免 pill bg 视觉)
class _DebtTabSegment extends StatelessWidget {
  const _DebtTabSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: selected ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppMotion.fast,
            curve: AppMotion.aquaIn,
            style: TextStyle(
              fontSize: 14,
              color: fg,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}