// lib/features/stats/ui/widgets/budget_overview_chart.dart
// 预算报表 widget —— stats 页本月维度专用(2026-10-12 commit 93 加)
//
// 视觉(commit 95 重构,commit 96 对齐 CategoryPie 风格,commit 98 去重 + 三档颜色,
//      commit 100 multi-turn 超额圆环 + 数字加载动画):
//   - 标题栏:本月预算 + 总额(右侧,跟 CategoryPie "共 ¥X" 对等)
//   - 上半:圆环 + 右侧图例(三段:已花 / 超额 / 剩余)
//     圆环 140x140 + inner 48 / outer 64
//     **multi-turn 支持**:已花 ≤ 预算时圆环 1 圈;过预算时"已花"占 1 圈,
//     "超额"继续从 360° 起转 N 圈(N = over / budget),颜色深递(已花 error 红 /
//     超额 overBudgetDeep 深红)
//     中心"已花 ¥X":数字 TweenAnimationBuilder 从 0 递增到目标值(1200ms aquaIn)
//     图例双行:第一行色块 + 名字 + 百分比,第二行(缩进)绝对金额
//   - 共享池说明(已分配 X · 共享池 Y 给未配置)
//   - 下半:分类列表 —— 每行 icon + name + 横向柱状图 + 百分比
//     颜色三档:< 80% teal / 80-100% warning 黄 / > 100% error 红
//
// 数据源:budgetOverviewForMonthProvider(commit 91 加)
// 数据流:用户在 BudgetSheet(commit 92)改 → refreshAllData → widget 重建
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../../../shared/constants/default_categories.dart';

import 'package:fl_chart/fl_chart.dart';

class BudgetOverviewChart extends ConsumerWidget {
  const BudgetOverviewChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final monthKey = BudgetMonthKey(now.year, now.month);
    final overviewAsync = ref.watch(budgetOverviewForMonthProvider(monthKey));
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: overviewAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.s4),
          child: SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Text(
            '加载预算失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
        data: (overview) => _BudgetOverviewBody(overview: overview),
      ),
    );
  }
}

class _BudgetOverviewBody extends StatefulWidget {
  const _BudgetOverviewBody({required this.overview});

  final BudgetOverview overview;

  @override
  State<_BudgetOverviewBody> createState() => _BudgetOverviewBodyState();
}

class _BudgetOverviewBodyState extends State<_BudgetOverviewBody> {
  BudgetOverview get overview => widget.overview;

  /// 总已花
  double get _totalSpent =>
      overview.items.fold<double>(0.0, (sum, i) => sum + i.spent);

  /// 进度比(可能 > 1,表示超额)
  ///   - ≤ 1:圆环 1 圈内,已花 + 剩余两段
  ///   - > 1:圆环 multi-turn,已花占 1 圈 + 超额继续转 N 圈
  double get _progress {
    if (overview.totalBudget <= 0) return 0;
    return _totalSpent / overview.totalBudget;
  }

  /// 是否已设置预算
  bool get _hasBudget => overview.totalBudget > 0;

  /// 是否超额(已花 > 预算)
  bool get _isOver => _hasBudget && _totalSpent > overview.totalBudget;

  /// 超额金额(已花 - 预算,只在超额时 > 0)
  double get _overSpent =>
      (_totalSpent - overview.totalBudget).clamp(0.0, double.infinity);

  /// commit 102 加:viewport-aware 触发入场动画
  ///   - false:widget 还没进入 scroll viewport,圆环和数字都不动
  ///   - true:viewport 进入后,圆环和数字才开始动 —— 一次性,不再重置
  bool _appeared = false;

  /// 用来拿 widget 在 scroll viewport 中的位置
  final GlobalKey _chartKey = GlobalKey();

  /// 监听 Scrollable 滚动,每次滚动时检查 widget 是否进入 viewport
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    // 跟 monthly_trend BarChart 同模式(commit 86):监听 Scrollable.position
    // 任何子 widget 在 scrollable 坐标系中"任意部分进入 viewport"都触发
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollPos = Scrollable.maybeOf(context)?.position;
      _scrollPos?.addListener(_checkInView);
      _checkInView();
    });
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  /// 检测 widget 是否在 scroll viewport 内
  ///   - 拿 chart RenderBox,scrollable RenderBox
  ///   - box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy
  ///     是 widget 顶在 scrollable 坐标系中的 y
  ///   - 如果 widget 顶 < viewport 高 && widget 底 > 0 → 任意部分可见 → 触发
  void _checkInView() {
    if (_appeared) return;
    final ctx = _chartKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final scrollableBox =
        _scrollPos?.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollableBox == null) return;
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      _appeared = true;
      _scrollPos?.removeListener(_checkInView);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏
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
              const Text(
                '本月预算',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (_hasBudget)
                Text(
                  '总额 ¥${Formatters.amount(overview.totalBudget)}',
                  style: const TextStyle(fontSize: 12, color: AppGray.g600),
                ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // 上半:圆环 + 图例(multi-turn + 数字加载动画)
        //   圆环 140x140 + inner 48 / outer 64
        //   圆环 sections(value = 圈数):
        //     - 未设置预算: 单段灰 (1 圈)
        //     - 已花 ≤ 预算: 已花(error 红,0~1 圈) + 剩余(灰,0~1 圈)
        //     - 已花 > 预算: 已花(error 红,固定 1 圈) + 超额(deep 红,N 圈)
        //       N = _overSpent / budget(可超过 1,触发 multi-turn)
        //   中心:小标签 + 大金额(数字 TweenAnimationBuilder 从 0 递增到实际值)
        //   右侧:图例(已花 / 超额 或 已花 / 剩余 三段)
        //   commit 102 加 KeyedSubtree 给上半部分:_checkInView 用此 key 拿
        //     widget 在 scrollable 坐标系中的位置,任意部分进入 viewport 时
        //     setState(_appeared = true) → 圆环 + 数字动画开始
        KeyedSubtree(
          key: _chartKey,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Builder(
                        builder: (_) {
                          final sections = <PieChartSectionData>[
                            if (_hasBudget && _isOver)
                              PieChartSectionData(
                                // 已花段:固定 1 圈(error 红)
                                value: 1.0,
                                color: AppStatus.error,
                                radius: 18,
                              ),
                            if (_hasBudget && _isOver)
                              PieChartSectionData(
                                // 超额段:N 圈(deep 红)
                                value: _overSpent / overview.totalBudget,
                                color: AppSemantic.overBudgetDeep,
                                radius: 18,
                              ),
                            if (_hasBudget && !_isOver && _progress > 0)
                              PieChartSectionData(
                                // 已花段:0~1 圈(error 红)
                                value: _progress.clamp(0.001, 1.0),
                                color: AppStatus.error,
                                radius: 18,
                              ),
                            if (_hasBudget && !_isOver)
                              PieChartSectionData(
                                // 剩余段:0~1 圈(灰)
                                value: (1.0 - _progress).clamp(0.0, 1.0),
                                color: AppGray.g200,
                                radius: 18,
                              ),
                            if (!_hasBudget)
                              PieChartSectionData(
                                value: 1.0,
                                color: AppGray.g200,
                                radius: 18,
                              ),
                          ];
                          return AnimatedOverBudgetChart(
                            key: pieChartKeyForSections(sections),
                            sections: sections,
                            innerRadius: 48,
                            outerRadius: 64,
                            // commit 102:viewport-aware 触发,play=false 时不 forward,
                            //   _appeared 变 true 时由 didUpdateWidget 触发
                            play: _appeared,
                          );
                        },
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '已花',
                            style: TextStyle(fontSize: 11, color: AppGray.g600),
                          ),
                          const SizedBox(height: 2),
                          // 数字加载动画:viewport 进入后才从 0 递增到实际值
                          //   - _appeared=false:显示静态最终值(避免"未加载完成"闪过)
                          //   - _appeared=true:TweenAnimationBuilder mount,begin=0 递增到 end
                          //     2000ms aquaIn(commit 102 改:之前 1200ms user 反馈太快)
                          if (_appeared)
                            TweenAnimationBuilder<double>(
                              key: ValueKey('spent-${_totalSpent.round()}'),
                              tween: Tween(begin: 0.0, end: _totalSpent),
                              duration: const Duration(milliseconds: 2000),
                              curve: AppMotion.aquaIn,
                              builder: (context, value, _) {
                                return Text(
                                  _hasBudget
                                      ? '¥${Formatters.amount(value)}'
                                      : '—',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              },
                            )
                          else
                            Text(
                              _hasBudget
                                  ? '¥${Formatters.amount(_totalSpent)}'
                                  : '—',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                // 右侧图例(commit 100 加第三段"超额")
                //   - 未设置预算: 空
                //   - 已花 ≤ 预算: 已花 + 剩余
                //   - 已花 > 预算: 已花 + 超额
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasBudget) ...[
                        _legendRow(
                          AppStatus.error,
                          '已花',
                          _isOver
                              ? '100' // 已花占满 100% 预算,不再乘 _progress
                              : (_progress * 100).toStringAsFixed(0),
                          Formatters.amount(_totalSpent, withUnit: false),
                        ),
                        const SizedBox(height: 4),
                        if (_isOver)
                          _legendRow(
                            AppSemantic.overBudgetDeep,
                            '超额',
                            // 超额百分比 = (over / budget) × 100
                            (_overSpent / overview.totalBudget * 100)
                                .toStringAsFixed(0),
                            Formatters.amount(_overSpent, withUnit: false),
                          )
                        else
                          _legendRow(
                            AppGray.g200,
                            '剩余',
                            ((1 - _progress).clamp(0.0, 1.0) * 100)
                                .toStringAsFixed(0),
                            Formatters.amount(
                              (overview.totalBudget - _totalSpent).clamp(
                                0.0,
                                double.infinity,
                              ),
                              withUnit: false,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // commit 98 移除:中部一行"已用 X% / 剩余 ¥X / 总额 ¥X" 是冗余信息
        //   — 已花百分比已经在圆环图例,剩余/总额已经在标题栏右侧 + 图例双行。
        // 共享池说明
        if (_hasBudget)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 14,
                    color: AppBrand.teal,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      overview.allocated > 0
                          ? '已分配 ¥${Formatters.amount(overview.allocated)} · 共享池 ¥${Formatters.amount(overview.poolRemaining)}'
                          : '未配置子额度 · 全部 ¥${Formatters.amount(overview.totalBudget)} 共享给所有支出分类',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 分类列表 —— commit 95 改:横向柱状图展示已花 / 子额度
        //   不再给数字 + 进度条,每行 icon + name + 横向 bar
        const Divider(height: 1, thickness: 0.5),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '分类预算',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '已配 ${overview.configuredItems.length}',
                style: const TextStyle(fontSize: 11, color: AppGray.g600),
              ),
            ],
          ),
        ),
        if (overview.configuredItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Center(
              child: Text(
                '未配置分类子额度',
                style: TextStyle(color: AppGray.g600, fontSize: 12),
              ),
            ),
          )
        else
          ...overview.configuredItems.map(
            (item) => _CategoryBudgetBarRow(item: item),
          ),
        const SizedBox(height: AppSpacing.s2),
      ],
    );
  }

  /// 图例行:双行 — 第一行 色块 + 名字 + 百分比,第二行(缩进对齐名字)绝对金额
  ///   commit 98 改:之前只有百分比,user 反馈"已花 / 剩余其实可以放金额"
  ///   双行布局只占 2 行,信息密度合理(只两个图例)。
  Widget _legendRow(Color color, String name, String pct, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppGray.g600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // 第二行:缩进对齐名字(8px 色块 + 8px gap = 18px)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 2),
            child: Text(
              '¥$amount',
              style: const TextStyle(fontSize: 11, color: AppGray.g600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类预算行 —— 横向柱状图
///
///   - 顶行:icon + 分类名 + 数字(右侧"已花 X / Y 总额"风格,便于核对)
///
///   🍔 餐饮          ¥2,100 / ¥3,000
///   ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░
///
///   - bar:
///     - 背景:浅灰底(full width)
///     - 已花:实色(< 100% = teal,> 100% = error 红)
///     - 圆角:左 2px(右端不圆,跟 left edge 对齐)
///     - 高度:6px
///
/// 不再用 LinearProgressIndicator(因为 user 要求"不要直接给数字",
/// 而是横向柱状图)。这里"用柱状图展示"含义是:不显示金额作为主数字,
/// bar 长度就是 spent / amount 的视觉表达。
class _CategoryBudgetBarRow extends StatelessWidget {
  const _CategoryBudgetBarRow({required this.item});

  final CategoryBudgetSummary item;

  @override
  Widget build(BuildContext context) {
    final color = Color(item.category.color);
    final spent = item.spent;
    final amount = item.amount;
    final ratio = amount > 0 ? (spent / amount).clamp(0.0, 1.5) : 0.0;
    // 三档状态(commit 98 加 warning 段,跟 _stateColor 规则一致):
    //   < 80% teal / 80-100% warning 黄 / > 100% error 红
    final over = amount > 0 && spent > amount;
    final warning = !over && amount > 0 && spent / amount >= 0.8;
    final barColor = over
        ? AppStatus.error
        : warning
        ? AppStatus.warning
        : AppBrand.teal;
    final ratioDisplay = amount > 0
        ? (spent / amount * 100).clamp(0, 999).toStringAsFixed(0)
        : '0';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  CategoryIcons.map[item.category.icon] ??
                      Icons.category_rounded,
                  size: 13,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  item.category.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 数字区域:不直接给金额数字,用"已花百分比 + 子额度"组合
              //   - "70%" 表示已用 70%
              //   - over 时显示"已超 X%"(红)
              //   - warning (80-100%) 显示百分比(黄)
              //   - 三档颜色跟 bar / 底部"已花 ¥X"同步
              Text(
                over
                    ? '已超 ${((ratio - 1) * 100).toStringAsFixed(0)}%'
                    : '$ratioDisplay%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          // 横向柱状图(bar) — 三档颜色:< 80% teal / 80-100% warning 黄 / > 100% error 红
          LayoutBuilder(
            builder: (ctx, c) {
              final width = c.maxWidth;
              final filledWidth = width * ratio.clamp(0.0, 1.0);
              return Stack(
                children: [
                  Container(
                    width: width,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppGray.g200,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    width: filledWidth,
                    height: 6,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s1),
          // 底部金额:辅助信息,小字号 — 颜色跟状态同步
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已花 ¥${Formatters.amount(spent, withUnit: false)}',
                style: TextStyle(
                  fontSize: 10,
                  color: over || warning
                      ? barColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '总额 ¥${Formatters.amount(amount, withUnit: false)}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
