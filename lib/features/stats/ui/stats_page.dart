// lib/features/stats/ui/stats_page.dart
// 报表:AppBar(报表 title + 视角 dropdown)→ 时间范围 tabs → 汇总 → 内容
//
// 视角选择放在 AppBar 右端(2026-10-11 UAT:\"不要增加一个 row,放在
// 与报表 title 同一级别即可,用下拉\"),不占 body 高度。下拉选完
// 后正文自动 switch,眼睛也不用离开页面顶部。
//
// 下拉刷新:广谱 invalidate 所有依赖 provider(流水 / 月度汇总 / 分类)
//
// 视角路由:
//   expense → CategoryPie + TopExpenses + MonthlyTrendChart
//   income  → IncomePie + MonthlyTrendChart
//   assets  → 占位(2026-10-11 资产功能预留)
//
// 2026-10-12 报表 widget 错峰入场(用户反馈"想有类似流水的那种往上抬"):
// _viewContent 内每个非 SizedBox widget 包 StaggeredFadeIn,首次 mount 时按
// index 30ms 错峰 fade + 上推 8px,360ms aquaIn。view 切换 / 月份切换不重放
// (_appeared 保持 true),只在 ConsumerStatefulWidget 首次 mount 触发。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/widgets/staggered_fade_in.dart';
import 'widgets/category_pie.dart';
import 'widgets/income_pie.dart';
import 'widgets/monthly_trend.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';
import 'widgets/top_expenses.dart';
import '../application/stats_providers.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  /// 2026-10-12 报表入场错峰:
  ///   - false:首次 build 阶段,_viewContent 内 widget 走 StaggeredFadeIn,
  ///     30ms*i 错峰 fade + 上推 8px,360ms aquaIn
  ///   - true:首 build 后下一帧翻 true,后续 rebuild(视角切换 / 月份切换 /
  ///     AnimatedSwitcher 重新 mount)不重放 stagger,各 widget 直接显示
  bool _appeared = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _appeared = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(statsViewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('报表'),
        actions: [
          // 2026-10-12 视角选择:AppBar 右侧 3 段 underline indicator
          // (ColorOS 16 风格)。
          // ── 修复 ── (2026-10-12 UAT 截图反馈"title 不见 + 3 段不显示"):
          //   1. 不能包 `Center`:Center 在 AppBar actions slot 里会强行
          //      撑满横向空间,把 title 挤出可见区,只剩 actions 左对齐
          //      的"支出"浮在左上
          //   2. AppBar 自己会垂直居中 actions,不需要 Center
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s2),
            child: _CompactViewSegmented(
              current: view,
              onChange: (v) => ref.read(statsViewProvider.notifier).state = v,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAllData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.s6),
          children: [
            // 时间范围(本月/本年) —— 现在是该页 body 的最顶(view
            // segmented 改到 AppBar 右侧了,这里不再有 view 行)
            const RangeTabs(),
            // 汇总(收入/支出/结余)— 三个视角共享(它是"窗口内总览")
            const RangeSummary(),
            const SizedBox(height: AppSpacing.s3),
            // 视角特定内容 — 包 AnimatedSwitcher cross-fade,切视角(支出/收入/资产)时
            // 新旧 view 同时存在(Stack 同时透明),完全无缝过渡。
            //
            // 2026-10-12 修(第 5 次迭代):
            //   - 之前 v1+v2:旧 fade out 完成才接着淡入新 view,有"空白瞬间",感觉卡
            //   - v3:加 layoutBuilder Stack cross-fade,新旧同时存在,无空白
            //   - v4:duration 680ms,过场太快,用户感觉不到"淡入淡出"的过场
            //   - v5(本版):duration 加到 1100ms,让 fade in/out 中间有 ~550ms
            //     两 view 都半透明的重叠区,过场节奏明显;StaggerGrow 同步
            //     拉到 1300ms,色块在 fade in 中后段长完,避免"已经画完但
            //     fade 还没结束"的不协调
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1100),
              switchInCurve: AppMotion.aquaIn,
              switchOutCurve: AppMotion.aquaOut,
              // cross-fade:Stack 让 previous children 跟 current child 同时
              // 渲染(各自带 FadeTransition),默认布局只显示 current 会有
              // "先消失后出现"的空白帧。ColorOS 切 view 风格是 cross-fade。
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[...previousChildren, ?currentChild],
                );
              },
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: ValueKey('view-${view.name}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _viewContent(view, animateStagger: !_appeared),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 视角特定内容。
  ///
  /// animateStagger=true 时,非 SizedBox 元素按 index 30ms 错峰 fade + 上推,
  /// 首次 mount 触发一次(由 _appeared flag 控制)。后续 view / 月份切换走
  /// AnimatedSwitcher 的 fade,StaggeredFadeIn 全部 enabled=false 直接显示。
  List<Widget> _viewContent(StatsView view, {required bool animateStagger}) {
    final widgets = <Widget>[];
    var staggerIndex = 0;
    void add(Widget w) {
      widgets.add(
        StaggeredFadeIn(
          index: staggerIndex++,
          enabled: animateStagger,
          child: w,
        ),
      );
    }

    switch (view) {
      case StatsView.expense:
        add(const CategoryPie());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        add(const TopExpenses());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        add(const MonthlyTrendChart());
      case StatsView.income:
        add(const IncomePie());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        add(const MonthlyTrendChart());
      case StatsView.assets:
        add(const _AssetsPlaceholder());
    }
    return widgets;
  }
}

/// AppBar 右侧的视角选择(共享 underline 横条滑动风格)
///   - 3 段(支出 / 收入 / 资产),放 AppBar 右侧,跟 title 同一行
///   - 每段:仅文字(无独立下划线、无 pill bg、无 InkWell ripple 圆角"pill 阴影")
///   - 选中:文字 onSurface 加粗
///   - 未选中:文字 onSurfaceVariant
///   - 切换:共享 underline 横条在 3 段底部滑动,240ms aquaIn(跟 range_tabs 共享 pill
///     同一思路 — "丝滑切换"= 共 1 根 underline 横条滑动,不是各自 fade)
///   - 触觉:撤掉(2026-10-12 commit 61)
///   - 没有 pill / 没有 ripple 圆角"pill 阴影":user 反馈 commit 61 边框 borderRadius:18
///     看起来像 pill 形阴影,这次撤掉,ripple 改 8(柔但不 pill 形)
///
/// 几何:每段固定 56px(14sp 中文 2 字 + padding 12*2 + 微 buffer),下划线 24px 居中
class _CompactViewSegmented extends StatelessWidget {
  const _CompactViewSegmented({required this.current, required this.onChange});

  final StatsView current;
  final ValueChanged<StatsView> onChange;

  static const _options = <(StatsView, String)>[
    (StatsView.expense, '支出'),
    (StatsView.income, '收入'),
    (StatsView.assets, '资产'),
  ];

  // 几何常量 —— 每段固定 56,underline 横条 24 居中,跟 range_tabs 共享 pill 同思路
  static const double _segW = 56;
  static const double _underlineW = 24;
  static const double _underlineH = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIdx = _options.indexWhere((o) => o.$1 == current);

    return SizedBox(
      // padding 8+8 + 14sp text + 4 gap + underline 2 ≈ 36
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 3 段文字 row(每段固定 56 wide)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _options.length; i++)
                SizedBox(
                  width: _segW,
                  child: _CompactViewSegment(
                    label: _options[i].$2,
                    selected: _options[i].$1 == current,
                    // onTap 永远调用 onChange;_CompactViewSegment 内部看 selected 决定
                    // 是否 disable ripple(避免当前段重复点击时的"晃一下")
                    onTap: () => onChange(_options[i].$1),
                  ),
                ),
            ],
          ),
          // 共享 underline indicator — 240ms aquaIn 在 3 段底部滑动
          AnimatedPositioned(
            duration: AppMotion.fast,
            curve: AppMotion.aquaIn,
            left: currentIdx * _segW + (_segW - _underlineW) / 2,
            bottom: 0,
            width: _underlineW,
            height: _underlineH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单段 — 仅文字,underline 共享(在父 Stack 上;commit 66 不再自己渲染)
///   - 选中:文字 onSurface 加粗;InkWell ripple disable(避免当前段重复点击时的"晃一下")
///   - 未选中:文字 onSurfaceVariant
///   - ripple 圆角:18(commit 61 太 pill)→ 8(柔但不 pill 形)。
class _CompactViewSegment extends StatelessWidget {
  const _CompactViewSegment({
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
    final fg = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      // 选中时 InkWell disable,避免"当前段被点时不响应也起 ripple"的鬼影
      onTap: selected ? null : onTap,
      // borderRadius:18 (commit 61) 像 pill 阴影 → user 反馈后改 8,柔但不 pill
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // vertical 8,horizontal 由父 SizedBox(width:56) 给死,此处 0
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

class _AssetsPlaceholder extends StatelessWidget {
  const _AssetsPlaceholder();

  @override
  Widget build(BuildContext context) {
    // 2026-10-12 修:资产 placeholder 的「即将上线」文字 dark mode 下也看不见
    // (AppGray.g600 在黑背景上融掉)。改用 onSurfaceVariant。
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s6,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: AppGray.g400,
            ),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              '资产结构',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '即将上线',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
