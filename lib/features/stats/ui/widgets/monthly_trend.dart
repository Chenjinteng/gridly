// lib/features/stats/ui/widgets/monthly_trend.dart
// 时间趋势卡片 —— 根据 statsRange 自动切换数据源 + 图表类型:
//   thisMonth → 按天支出柱状图(_DailyExpenseBarChart,看 dailyExpenseTrendProvider)
//   thisYear  → 当年 1-12 月支出柱状图(_MonthlyBarChart,看 yearlyExpenseTrendProvider,单柱)
//
// 2026-10-12 redesign (commit 72):
//   user "近 12 月趋势"反馈:
//     - 本月维度不需要这个 12 月折线图 → 换按天柱状图(本月每天支出)
//     - 本年维度才显示 12 个月柱状图(去掉折线,改成柱状)
//   旧实现是单一 LineChart + 固定过去 12 月数据(不看 range),改成分支 + BarChart。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

/// 时间趋势卡片容器 —— 看 statsRange 自动切换 widget:
///   thisMonth → _DailyExpenseBarChart
///   thisYear  → _MonthlyBarChart
///
/// 容器 widget 的 padding / 卡片边框 / 阴影 / 标题结构不变,只换内部图表。
/// 标题根据 range 切换文案("本月每日支出" / "近 12 月趋势")
class MonthlyTrendChart extends ConsumerWidget {
  const MonthlyTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return Container(
      // 跟 Top 10 / CategoryPie / IncomePie 同卡片风格(surface + 1px 边框 + shadow)
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.0,
        ),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            range == StatsRange.thisMonth ? '本月每日支出' : '近 12 月趋势',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s3),
          // 用 SizedBox + 192px 高度统一,BarChart 自适应高度(底部 X labels 占一些)。
          SizedBox(
            height: 192,
            child: range == StatsRange.thisMonth
                ? const _DailyExpenseBarChart()
                : const _MonthlyBarChart(),
          ),
        ],
      ),
    );
  }
}

/// 本月每日支出柱状图(thisMonth 用)
class _DailyExpenseBarChart extends ConsumerWidget {
  const _DailyExpenseBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyExpenseTrendProvider);
    return dailyAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Center(
              child: Text(
                '本月暂无支出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        // 同 niceInterval 逻辑:避免 345.23 这种带小数的 tick label
        final maxVal = data
            .map((d) => d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final niceInterval = _pickNiceInterval(maxVal);
        final maxY = maxVal == 0
            ? 1.0
            : (maxVal / niceInterval).ceil() * niceInterval;
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: _AnimatedBarChart(
            bars: data,
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            color: AppStatus.error,
            labelKind: BarLabelKind.day, // X label 是日期
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// 当年 1-12 月支出柱状图(thisYear 用)—— 一月一根柱,只显示支出
/// 2026-10-12 commit 78 改:之前用 monthlyTrendProvider(近 12 月 + income/expense),
/// user 反馈"本年不要近 12 个月"+"只需要支出" → 改用 yearlyExpenseTrendProvider,
/// 只算 expense(单柱,不再有 income 维度)
class _MonthlyBarChart extends ConsumerWidget {
  const _MonthlyBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(yearlyExpenseTrendProvider);
    return trendAsync.when(
      data: (data) {
        if (data.every((d) => d.expense == 0)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Center(
              child: Text(
                '本年暂无支出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        final maxVal = data
            .map((d) => d.expense)
            .fold<double>(0, (a, b) => a > b ? a : b);
        final niceInterval = _pickNiceInterval(maxVal);
        final maxY = maxVal == 0
            ? 1.0
            : (maxVal / niceInterval).ceil() * niceInterval;
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s2),
          child: _AnimatedBarChart(
            bars: data,
            maxY: maxY,
            niceInterval: niceInterval,
            chartNeedsWan: chartNeedsWan,
            color: AppStatus.error,
            labelKind: BarLabelKind.month, // X label 是月份
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// Bar label 类型:日期(本月每日柱状图用)还是月份(近 12 月柱状图用)
enum BarLabelKind { day, month }

/// 2026-10-12 commit 82 加:overlay 虚线/label x 偏移常量
///
/// 跟 BarChart.leftTitles.reservedSize(下面 line ~347)强绑定:
///   - AxisChartScaffoldWidget 把 chart 包在
///     `Container(margin: data.titlesData.allSidesPadding)` 里
///   - `allSidesPadding.left = leftTitles.totalReservedSize = 56`
///   - 所以 BarChartLeaf renderObject 的 (0,0) 在 BarChart widget 内是
///     (56, _) 起点
///   - BarTouchedSpot.offset.dx 是 BarChartLeaf 内坐标,要 +56 才是
///     BarChart widget 内坐标(给 Stack Positioned 用)
///
/// ⚠️ 改 leftTitles.reservedSize 时要同步改这个常量,否则 overlay 错位
const double _leftReservedSize = 56;

/// 入场柱子 —— 从底部往上"长"起来,aquaIn 600ms。
///
/// 2026-10-12 commit 86 加 viewport-aware 触发:
///   - user 反馈"因为有一些 dashboard 是在下方的,只想加一些动画,只在滚动
///     加载到该 dashboard 时才有动画。比如底下的柱状图,我想加一个柱条往上
///     增长的动画,但是想滑动到该 dashboard 时才加载出来"
///   - 修法:
///     1) State 加 _appeared 标记 + GlobalKey + ScrollPosition 监听
///     2) _checkInView 检测 widget 在 scroll viewport 内的位置,进入时
///        setState(_appeared = true) + forward 动画
///     3) _buildBarGroups 根据 _appeared 决定 toY:
///        - _appeared=false → toY=0(柱子隐藏)
///        - _appeared=true → toY=real(柱子显示)
///        BarChart 看到 BarChartData 变化,自动用内置 swap animation
///        (duration: 600ms aquaIn) 从 toY=0 过渡到 toY=real,实现"柱条往上长"
///     4) 同步 fade-in Opacity 整体淡入(480ms)
///     5) 离 viewport 后不再重放,只触发一次(_appeared flag 持久)
///
/// 实现:
///   - 内部 AnimationController 480ms aquaIn,BarChart(duration: 600ms) 用
///     fl_chart 内置 swap animation 从 zero→real,实现柱条增长
///   - GlobalKey 给 chart widget,RenderBox.localToGlobal 拿 widget 在
///     scrollable 坐标系中的位置,跟 viewport height 比较
///   - Scrollable.maybeOf(context) 拿当前 Scrollable,addListener
class _AnimatedBarChart extends StatefulWidget {
  const _AnimatedBarChart({
    required this.bars,
    required this.maxY,
    required this.niceInterval,
    required this.chartNeedsWan,
    required this.color,
    required this.labelKind,
  });

  final List bars;
  final double maxY;
  final double niceInterval;
  final bool chartNeedsWan;
  final Color color;
  final BarLabelKind labelKind;

  @override
  State<_AnimatedBarChart> createState() => _AnimatedBarChartState();
}

class _AnimatedBarChartState extends State<_AnimatedBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// 2026-10-12 commit 86 加 viewport-aware 触发入场动画
  ///   - false:widget 还没进入 scroll viewport(toY=0,柱条隐藏)
  ///   - true:widget 进入 viewport 后(toY=real,柱条长出)—— 一次性,不再重置
  bool _appeared = false;

  /// 用来拿 chart widget 在 scroll viewport 中的位置
  final GlobalKey _chartKey = GlobalKey();

  /// 监听 Scrollable 滚动,每次滚动时检查 widget 是否进入 viewport
  ScrollPosition? _scrollPos;

  /// 当前 touch 的 group 索引(0..bars.length-1);null = 没有 touch
  /// commit 79 改:之前 commit 77 用 extraLinesData.verticalLines + VerticalLineLabel,
  /// 但 fl_chart 0.69 BarChart 完全不渲染 verticalLines(注释里写"Vertical lines
  /// will not be painted if received",issue #1149),导致虚线和顶部 label 在
  /// commit 78 user 截图里完全看不到。
  /// → 改用 Stack overlay 在 BarChart 上叠 CustomPaint 画 dashed line +
  /// Positioned label,_touchedOffset 记 BarChart 内局部像素 x 位置(来自
  /// BarTouchedSpot.offset.dx),label 通过 _touchedLabel() 从 group index 反查日期/月。
  int? _touchedGroupIdx;
  Offset? _touchedOffset;

  /// 当前 touch 柱的金额(toY 值)—— commit 85 加:tooltip 从 BarChart 自带
  /// 搬到 overlay 自己画后,需要记下金额给 overlay tooltip 用。
  double? _touchedValue;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    // commit 86 改:不再立即 forward(),改用 viewport-aware 触发
    // 等首帧后 _checkInView 检测 widget 是否在 viewport,进入时才触发动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollPos = Scrollable.maybeOf(context)?.position;
        _scrollPos?.addListener(_checkInView);
        _checkInView();
      }
    });
  }

  /// 2026-10-12 commit 86 加:检测 widget 是否在 scroll viewport 内
  ///   - 拿 chart RenderBox,scrollable RenderBox
  ///   - box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy
  ///     是 widget 顶在 scrollable 坐标系中的 y
  ///   - 如果 widget 顶 < viewport 高 && widget 底 > 0 → 任意部分可见 → 触发
  void _checkInView() {
    if (_appeared) return;
    final ctx = _chartKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      // 没有 Scrollable(不嵌在滚动区域里),直接进入
      _appear();
      return;
    }
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null) return;
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    // 任意部分进入 viewport 就触发(不需要 50% 之类阈值,user 要"滚到时"立刻)
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      _appear();
    }
  }

  /// 进入 viewport 后:开 fade-in + BarChart swap 触发柱条增长
  void _appear() {
    if (_appeared) return;
    _appeared = true;
    _ctrl.forward();
    _scrollPos?.removeListener(_checkInView);
    _scrollPos = null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  /// 处理 barChart touch:
  ///   - commit 85 改:用 `!event.isInterestedForInteractions` 作为清空 trigger,
  ///     覆盖所有"手指 / 鼠标离开"事件
  ///     - FlPanEndEvent / FlPanCancelEvent(pan 结束 / 取消)
  ///     - FlTapUpEvent / FlTapCancelEvent(tap 抬起 / tap 取消)
  ///     - FlLongPressEnd(长按结束)
  ///     - FlPointerExitEvent(鼠标移出 chart 边界)
  ///   - 之前只清 FlPanEnd/FlPanCancel,tap 抬起不会触发 → 虚线卡在柱上不消失
  ///   - 其它 event(FlPanDown / FlPanStart / FlPanUpdate / FlTapDown / FlLongPressStart):
  ///     更新 _touchedGroupIdx + _touchedOffset + _touchedValue(给 overlay tooltip 用)
  void _onTouch(FlTouchEvent event, BarTouchResponse? response) {
    if (!event.isInterestedForInteractions) {
      // "手指 / 鼠标离开"事件:清掉虚线 + label + tooltip overlay
      if (_touchedGroupIdx != null ||
          _touchedOffset != null ||
          _touchedValue != null) {
        setState(() {
          _touchedGroupIdx = null;
          _touchedOffset = null;
          _touchedValue = null;
        });
      }
      return;
    }
    final spot = response?.spot;
    final idx = spot?.touchedBarGroupIndex;
    final off = spot?.offset;
    final val = spot?.touchedRodData.toY;
    if (idx != null &&
        off != null &&
        (idx != _touchedGroupIdx ||
            off != _touchedOffset ||
            val != _touchedValue)) {
      setState(() {
        _touchedGroupIdx = idx;
        _touchedOffset = off;
        _touchedValue = val;
      });
    }
  }

  /// 把当前 touch 的 group index 转成"日期/月"文字
  String? _touchedLabel() {
    final idx = _touchedGroupIdx;
    if (idx == null || idx < 0 || idx >= widget.bars.length) return null;
    if (widget.labelKind == BarLabelKind.day) {
      return '${widget.bars[idx].day}日';
    }
    return '${widget.bars[idx].month}月';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: Curves.easeInOut.transform(_ctrl.value),
          // commit 86 加:GlobalKey 给最外层,让 _checkInView 拿 RenderBox
          // 检测 widget 在 scroll viewport 内的位置
          child: KeyedSubtree(key: _chartKey, child: _buildChart()),
        );
      },
    );
  }

  Widget _buildChart() {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      // commit 79 改:BarChart 不渲染 verticalLines,改用 overlay 在 BarChart
      // 上叠 dashed line + label。Clip.none 让 label 在最左/最右柱时能溢出
      // BarChart widget 边界而不被裁掉。
      clipBehavior: Clip.none,
      children: [
        // commit 86 加:BarChart swap animation duration 600ms aquaIn
        //   - _appeared=false → toY=0;viewport 进入 → setState → toY=real
        //   - BarChart 看到 BarChartData 变化,自动用 swap 600ms 从 zero
        //     lerp 到 real,实现"柱条往上长"
        //   - 跟整体 Opacity fade-in(480ms) 同步叠加
        BarChart(
          BarChartData(
            maxY: widget.maxY,
            minY: 0,
            // daily 30 根柱,BarChartAlignment.spaceAround 默认会把柱挨在一起;
            // 改 spaceBetween + groupsSpace 4 让每根柱之间有 4px 留白,看起来"呼吸"
            // 2026-10-12 user 反馈"柱与柱之间没有间隔",commit 73 加
            alignment: BarChartAlignment.spaceBetween,
            groupsSpace: 4,
            barTouchData: BarTouchData(
              handleBuiltInTouches: true,
              // commit 79 改:touchCallback 改成记 BarTouchedSpot.offset.dx
              // (BarChart 内局部像素坐标)给 overlay 用。之前 commit 77 用
              // group index + extraLinesData.verticalLines,但 BarChart 不画
              // verticalLines(issue #1149),所以虚线根本没渲染。
              touchCallback: _onTouch,
              // commit 87 改:
              //   - touchTooltipData 显式禁用 fl_chart 内置 tooltip
              //     (getTooltipItem 返回 null 触发不渲染)
              //     之前 commit 85 直接移除整个 touchTooltipData,导致
              //     BarChart 仍用默认 BarTouchTooltipData(空 getTooltipItem)
              //     渲染了一个灰色空 tooltip,跟 overlay tooltip 同时显示
              //     → user 截图出现两个金额(灰色 fl_chart 内置 tooltip +
              //     黑色 overlay tooltip)
              //   - touchExtraThreshold 加大到 horizontal: 8
              //     30 根 5px 柱子在窄屏上每柱中心间距 ≈ 9.5px,
              //     默认 threshold all 4 让柱间空白处 pan 移动不会切换柱
              //     → user 反馈"靠点击选取不友好,想滑动跟随"
              //     加大到 horizontal: 8 后任何 x 位置都能命中最近柱,
              //     FlPanUpdateEvent 触发 _onTouch 更新虚线/label/tooltip
              //     → 横滑手指虚线跟着移动到最近柱
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (_, _, _, _) => null,
              ),
              touchExtraThreshold: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 56,
                  interval: widget.niceInterval,
                  getTitlesWidget: (v, meta) => Text(
                    Formatters.amount(
                      v,
                      forceWan: widget.chartNeedsWan,
                      trimTrailingZeros: true,
                    ),
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  // commit 75: 18 → 14,user 反馈"再近一点"
                  reservedSize: 14,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= widget.bars.length) {
                      return const SizedBox.shrink();
                    }
                    if (widget.labelKind == BarLabelKind.day) {
                      // daily bar(30 根柱)X 轴只标 1, 5, 10, 15, 20, 25, 30
                      // 稀疏化,避免小屏 label 重叠
                      // 2026-10-12 user 反馈"太密了",从全 30 个标签改 7 个
                      final day = widget.bars[idx].day;
                      if (day != 1 && day % 5 != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    // monthly bar(12 月)X 轴全标 12 个月
                    return Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        '${widget.bars[idx].month}月',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: _buildBarGroups(),
          ),
          // commit 86:BarChart swap animation 600ms aquaIn
          //   viewport 进入前 toY=0(viewport 内 setState 后)toY=real,
          //   BarChart 看到 BarChartData 变化自动用 swap 从 0 lerp 到 real,
          //   实现"柱条往上增长"。跟整体 Opacity fade-in(480ms)叠加。
          duration: const Duration(milliseconds: 600),
          curve: AppMotion.aquaIn,
        ),
        // commit 79 加:touch 选柱时,顶部画虚线 + "X日/X月" label
        //   - 虚线:_DashedLinePainter 自定义 painter,[4,3] dashArray,贯穿 chart 高度
        //   - label:Surface 背景卡片,边框 + 居中文字
        //   - 位置:用 BarTouchedSpot.offset.dx + _leftReservedSize 偏移
        // commit 82 修:user 截图显示虚线偏左 56px(≈ 6 个 day)
        //   - 根因:BarTouchedSpot.offset.dx 是 BarChartLeaf renderObject
        //     内坐标(从 leaf (0,0) 开始),不是 BarChart widget (AxisChartScaffoldWidget
        //     包装的) 的 (0,0)。AxisChartScaffoldWidget 把 chart 包在
        //     Container(margin: allSidesPadding) 里,allSidesPadding.left =
        //     leftTitles.totalReservedSize = 56 → BarChartLeaf (0,0) 在 BarChart
        //     widget 内是 (56, _) 起点。
        //   - 修法:Positioned.left = offset.dx + _leftReservedSize,跟 chart leaf
        //     在 BarChart widget 内的实际位置对齐
        if (_touchedOffset != null) ...[
          Positioned(
            // 1.5px 虚线居中在 offset.dx(BarChartLeaf 内坐标) + leftReservedSize
            // 才是 BarChart widget 内的实际位置
            left: _touchedOffset!.dx + _leftReservedSize - 0.75,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: CustomPaint(
              painter: _DashedLinePainter(color: scheme.onSurfaceVariant),
            ),
          ),
          Positioned(
            // 56px 宽 label,left = dx + leftReservedSize - 28 居中
            left: _touchedOffset!.dx + _leftReservedSize - 28,
            top: 0,
            width: 56,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant, width: 0.5),
                ),
                child: Text(
                  _touchedLabel() ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          // commit 85 加:金额 tooltip overlay(Stack 最顶层,盖住虚线)
          //   - 之前用 fl_chart 内置 BarTouchTooltipData,但 tooltip 画在
          //     BarChart canvas 内,被 overlay 虚线盖住
          //     user 反馈"跨线时金额要在虚线上方,盖住虚线"
          //   - 改成自己画,放在 Stack children 最后(z-order 顶层)
          //   - 同时 user 反馈"金额底框太大":
          //     原 BarTouchTooltipData 默认 tooltipPadding = h16/v8,
          //     fontSize = 13;改成 h10/v4 + fontSize 12,底框更紧凑
          //   - 位置:日期 label 下方(top: 26),跟虚线/柱子中心对齐
          if (_touchedValue != null)
            Positioned(
              left: _touchedOffset!.dx + _leftReservedSize - 40,
              top: 26,
              width: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppBrand.ink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '¥${Formatters.amount(_touchedValue!)}',
                    style: TextStyle(
                      color: AppBrand.gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 把 daily/monthly 数据转成 BarChartGroupData 列表
  ///
  /// - DailyExpenseBarChart:每天 1 根柱(支出,error 红)
  /// - MonthlyTrendBarChart:每月 1 根柱(支出,error 红;commit 78 改:之前是 grouped 双柱 income+expense)
  ///
  /// commit 86 加 viewport-aware 触发:
  ///   - _appeared=false(toY=0):widget 还没进入 viewport,柱条隐藏
  ///   - _appeared=true(toY=real):viewport 进入后,BarChart swap animation
  ///     (duration: 600ms aquaIn) 把 toY 从 0 lerp 到 real → "柱条往上长"
  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < widget.bars.length; i++) {
      if (widget.labelKind == BarLabelKind.day) {
        // 每日 1 柱
        // commit 73:width 8 → 5 + groupsSpace 4,30 根柱的 30×5 + 29×4 = 266
        // + chart padding ≈ 330,30 根柱之间各有 4px 留白
        final d = widget.bars[i];
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: _appeared ? d.expense : 0.0,
                color: widget.color,
                width: 5,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ],
          ),
        );
      } else {
        // 每月 1 柱(支出 only)—— commit 78 改
        //   之前返 2 根 grouped rod(income gold + expense red),
        //   user 反馈"本年只需要支出,为什么还会有红黄两条柱子的"
        //   → 改单 expense rod(红),不再有 income 维度
        final m = widget.bars[i];
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: _appeared ? m.expense : 0.0,
                color: widget.color,
                width: 5,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ],
          ),
        );
      }
    }
    return groups;
  }
}

/// 垂直虚线 CustomPainter —— commit 79 加,BarChart 不渲染 verticalLines 后的 overlay 替代。
///
/// - 1.5px strokeWidth,4px 实线 + 3px 空白循环,贯穿 CustomPaint 整个高度
/// - Positioned 控位置(left: offset.dx - 0.75 让线居中),大小由外层给
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.butt;
    const dashLen = 4.0;
    const gapLen = 3.0;
    double y = 0;
    while (y < size.height) {
      // drawLine 的 x 用 size.width / 2(线很细,1.5px,正好居中)
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + dashLen),
        paint,
      );
      y += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 2026-10-01 沿用:按"1/2/5 × 10^n"挑 niceInterval,避免 maxY 实际值出现
double _pickNiceInterval(double maxVal) {
  if (maxVal <= 0) return 1;
  final magnitude = _pow10(
    (maxVal.abs().toString().split('.').first.length) - 1,
  );
  final candidates = <double>[magnitude, 2 * magnitude, 5 * magnitude];
  for (final c in candidates) {
    final tickCount = maxVal / c;
    if (tickCount <= 4) return c;
  }
  return candidates.last;
}

double _pow10(int n) {
  double r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
