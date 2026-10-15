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
//   expense → CategoryPie + TopExpenses + ConsumptionTrend + ExpenseAnalysis(+ thisMonth: BudgetOverviewChart)
//   assets  → 占位(2026-10-11 资产功能预留)
// 2026-10-12 P5 commit 简化:删 income 段(2 段:收支 / 资产),IncomePie 文件同步删
// 2026-10-15 D64.10 改:MonthlyTrendChart + CategoryCompareChart + WeekdayExpenseChart
//   3 张独立卡合并成"消费趋势"1 张 tabbed 模块,本文件不再单独 import 它们。
// 2026-10-15 D64.11 改:CategoryPie + ExpenseByAssetChart 2 张独立卡合并成
//   "支付分析"1 张 tabbed 模块,本文件不再单独 import 它们。
// 2026-10-15 D64.16 改:"支付分析" → "支出分析"(user UAT 反馈模块名),同时
//   文件 / 类名 PaymentAnalysis → ExpenseAnalysis。
//
// 2026-10-12 报表 widget 错峰入场(用户反馈"想有类似流水的那种往上抬"):
// _viewContent 内每个非 SizedBox widget 包 StaggeredFadeIn,首次 mount 时按
// index 30ms 错峰 fade + 上推 8px,360ms aquaIn。view 切换 / 月份切换不重放
// (_appeared 保持 true),只在 ConsumerStatefulWidget 首次 mount 触发。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/widgets/staggered_fade_in.dart';
import '../../../core/widgets/privacy_obscure.dart';
import 'widgets/budget_overview_chart.dart';
import 'widgets/consumption_trend.dart';
import 'widgets/expense_analysis.dart';
import 'widgets/assets_by_type.dart';
import 'widgets/assets_overview_chart.dart';
import 'widgets/assets_radar.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';
import 'widgets/savings_trend.dart';
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
      if (mounted) {
        // 2026-10-12 commit 84 加:打开报表那一刻主动 refresh,user 反馈
        //   "edit 了 7 月历史支出,12 月趋势没变"
        //   "打开报表那一刻都要动态获取最新的数据"
        // 原因:
        //   - Riverpod FutureProvider 只要被 watch 过就缓存,即使 db 已经变化
        //     也不会自动重新 fetch(除非显式 invalidate)
        //   - user 在记一笔 / 流水 / 分类管理页修改了数据,如果不主动
        //     refreshAllData,stats tab 切回来时显示的还是修改前的缓存
        //   - BottomNavigationBar 切 tab 不会触发 StatsPage.initState 重跑
        //     (State 持久化),所以在 initState 里加 postFrameCallback 调一次
        //     refreshAllData,保证"首次进入 stats tab"一定是最新
        //   - 后续 add / update / delete 也走 refreshAllData(commit 81/67 已
        //     接上),但 initState 这层是兜底,防止上游链路漏接 provider
        refreshAllData(ref);
        setState(() => _appeared = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(statsViewProvider);
    // 2026-10-14 D60:整页隐私覆盖 —— 关闭"显示金额"时,报表页整页盖半透明蒙版
    //   (含 AppBar),block 全部点击。点蒙版任意位置 = 恢复显示。详情见 PrivacyObscure。
    return PrivacyObscure(
      child: Scaffold(
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
              // 视角特定内容 — 包 AnimatedSwitcher cross-fade,切视角(收支/资产)时
              // 新旧 view 同时存在(Stack 同时透明),完全无缝过渡。
              //
              // 2026-10-12 修(第 6 次迭代):
              //   - 之前 v5:duration 1100ms + cross-fade Stack,中间 ~550ms
              //     两 view 都半透明重叠,user 反馈"页面消失的太慢,重叠了"
              //   - v6(本版):duration 500ms,保留 cross-fade 但重叠窗口
              //     缩到 ~250ms,既保留 ColorOS 水波过场感,又不再"两个
              //     view 糊在一起"的长时间叠加
              //   - StaggeredFadeIn 360ms 不动,它只在首次 mount 触发一次,
              //     view 切换时不重放,跟 AnimatedSwitcher 节奏无冲突
              //
              // 2026-10-13 P6 第 7 次改(UAT 截图反馈"老问题又来了,500ms 还是
              //   太长,重影"):
              //   - duration 500ms → 200ms(200ms 重叠窗口 ~100ms,基本察觉不到)
              //   - 切 view 是用户主动操作,要快(入场动画可以慢,view 切换要快)
              //   - 入场动画(StaggeredFadeIn 360ms + AnimatedCounter 1200ms)
              //     保持不变,它们只在 view 首次 mount 触发一次,不冲突
              //
              // 2026-10-13 P6 改:RangeTabs(本月/本年) + RangeSummary(收入/支出/结余)
              //   只对 expense 视角显示。资产视角是"当前余额",不依赖时间窗口,
              //   不显示这 2 个 section 更干净。
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
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
        // 2026-10-13 P6 改:RangeTabs + RangeSummary 只对 expense 视角显示
        //   资产视角是"当前余额",不依赖时间窗口,不需要本月/本年/收入/支出/结余
        add(const RangeTabs());
        add(const RangeSummary());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        // 2026-10-15 D64.11 改:CategoryPie + ExpenseByAssetChart 2 张独立
        //   卡合并成"支付分析"1 张 tabbed 模块(分类 / 账户)
        // 2026-10-15 D64.16 改:模块名 PaymentAnalysis → ExpenseAnalysis
        //   ("支付分析" → "支出分析",user UAT 反馈命名)
        add(const ExpenseAnalysis());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        add(const TopExpenses());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        // 2026-10-12 commit 95 改位置:预算报表放到 Top 10 支出下面
        //   user 原话:"预算放在 top10 支出报表下面"
        //   仅本月维度显示(本年维度跟月度预算无关)
        if (ref.watch(statsRangeProvider) == StatsRange.thisMonth) {
          add(const BudgetOverviewChart());
          widgets.add(const SizedBox(height: AppSpacing.s3));
        }
        // 2026-10-15 D64.10 改:把原来 MonthlyTrendChart(thisMonth 才显示按天
        // 柱状) + CategoryCompareChart + WeekdayExpenseChart 3 张独立卡合并
        // 成 1 张"消费趋势"模块(tab 切换 每日/类别/周几),沿用
        // top_expenses "单笔/分类"同款 tab 样式(teal label + 0 高 indicator)。
        // 本年维度:每日 tab 显示 12 月聚合(原 monthly_trend thisYear 行为),
        //   类别 tab 空态(provider thisYear 1 月 vs 12 月语义错),
        //   周几 tab 通用。
        add(const ConsumptionTrend());
        // D64.27 加:储蓄走势折线图模块 —— 加到消费趋势后面,本年专属
        //   (本年维度看全年趋势,本月维度没意义)
        if (ref.watch(statsRangeProvider) == StatsRange.thisYear) {
          widgets.add(const SizedBox(height: AppSpacing.s3));
          add(const SavingsTrend());
          // D64.28 加:按资产 6 段分析 —— 储蓄走势之后,本年专属
          widgets.add(const SizedBox(height: AppSpacing.s3));
          add(const AssetsByType());
        }
      case StatsView.assets:
        // 2026-10-12 P4 commit:资产视角 = 总览卡 + 6 维雷达图(2026-10-13 P6 改 4 维 → 6 维)
        //   2026-10-13 P6:RangeTabs/RangeSummary 不在这里显示
        add(const AssetsOverviewChart());
        widgets.add(const SizedBox(height: AppSpacing.s3));
        add(const AssetsRadar());
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
    (StatsView.expense, '收支'),
    (StatsView.assets, '资产'),
  ];

  // 几何常量 —— 2 段后每段固定 56,underline 横条 24 居中,跟 range_tabs 共享 pill 同思路
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

/// 单段 — 仅文字,underline 共享(在父 Stack 上;commit 71 起纯 GestureDetector)
///   - 选中:文字 onSurface 加粗;GestureDetector disable(避免当前段重复点击时的"晃一下")
///   - 未选中:文字 onSurfaceVariant
///   - 无 ripple / 无 splash / 无 highlight:user 反馈"InkWell 即使 borderRadius:8
///     ripple 看起来还是 pill bg"(M3 InkRipple splash 默认浅色波形,跟 pill bg 视觉
///     重合)。commit 71 改成 GestureDetector,完全无 tap 视觉反馈,只保留:
///     1) 文字色 + 加粗切换(240ms aquaIn)
///     2) 父 Stack 上共享 underline 横条滑动 240ms aquaIn
///   - 触觉:无(v66 起就无)
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
    return GestureDetector(
      // 选中时 disable,避免"当前段被点时不响应"的鬼影;
      // 完全无 splash / highlight / ripple — user 反馈 ripple 看着像 pill bg
      onTap: selected ? null : onTap,
      behavior: HitTestBehavior.opaque,
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
