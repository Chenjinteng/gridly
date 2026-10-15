// lib/core/widgets/charts/animated_bar_chart.dart
// 2026-10-15 D64 加:共享的 viewport-aware 柱状图 widget
//
// 从 monthly_trend._AnimatedBarChart 抽出(原本 private 在 monthly_trend.dart
// 里,~600 行,跟 BarLabelKind / DailyExpense / MonthlyTrend 强耦合)。
// 改造:
//   - bars 改用通用 BarChartBar 数据结构(label + value + optional secondaryValue)
//   - X 轴 label / 触摸 label / tooltip 文字 走 builder 回调
//   - 颜色支持 3 种:固定色(primaryColor + secondaryColor 双柱),
//     或动态色(barColorResolver 单柱按 bar 算色,周几支出高亮最大值柱)
//
// 2026-10-15 D64.5 改:maxY + niceInterval 算法下沉到本 widget 内部。
//   业务 widget 只传 `maxVal`(实际最大柱值),内部按整数倍规则算出
//   maxY = (maxVal / niceInterval).ceil() * niceInterval,避免 fl_chart 在
//   maxY 位置额外画一个小数 label 跟 0 重叠(原 `maxVal * 1.15` 非整数倍
//   触发的 bug)。
//
// 2026-10-15 D64.21c 改:支持负轴
//   - 新增 `minVal` 参数(可空,null/0 = 老逻辑,负值启用负轴)
//   - niceInterval 算法:`max(|minVal|, |maxVal|)` 取 max,保证 min/max 区间
//     都按整数倍铺开
//   - computedMinY = (minVal / niceInterval).floor() * niceInterval(向下取整)
//   - computedMaxY = (maxVal / niceInterval).ceil() * niceInterval(向上取整)
//   - 0 轴线(当启用负轴):gridData 在 v=0 时画 outline 1px(其他 grid 0.5px
//     outlineVariant),视觉上区别"坐标中线"vs"普通网格线"
//   - bar borderRadius:正值圆顶,负值圆底,跟柱条方向匹配
//
// 行为(跟 monthly_trend._AnimatedBarChart 一致):
//   - viewport-aware 触发入场动画(toY=0 → real via BarChart swap 600ms)
//   - 触摸:
//     - onPointerDown / onPointerMove / onPointerUp / onPointerCancel
//     - 走 Flutter 原生 Listener(无 touch slop 延迟)
//     - 自算最近 group index + centerX
//     - move 时只 setState 切换 group(不重建 chart)
//   - 触摸 overlay:
//     - 1.5px 垂直虚线(DashedLinePainter)
//     - 顶部类目 label(56px 宽 surface bg card)
//     - 金额 tooltip(80px 宽 ink bg + gold 文字)
//
// 业务 widget 用法(参考 monthly_trend / category_compare / weekday_expense):
//   AnimatedBarChart(
//     bars: data.map((d) => BarChartBar(
//       label: '${d.day}日',
//       value: d.expense,
//     )).toList(),
//     maxVal: maxVal,           // 实际最大柱值(非 maxY)
//     minVal: ...,              // D64.21c 加:实际最小柱值(负值启用负轴,默认 0)
//     chartNeedsWan: chartNeedsWan,
//     xLabelBuilder: (i, b) => Text(...),  // 可选,X 轴 label widget
//     touchedLabelBuilder: (i, b) => b.label,  // 触摸顶部 label
//     tooltipBuilder: (i, b) => '¥${b.value}',  // 触摸金额 tooltip
//     barColorResolver: (i, b) => b.value == maxVal ? AppStatus.error : AppGray.g200,
//   )
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../motion/app_motion.dart';
import '../../utils/formatters.dart';

/// 单个柱的数据
class BarChartBar {
  const BarChartBar({
    required this.label,
    required this.value,
    this.secondaryValue,
  });

  /// X 轴 label(用于底部显示 + 触摸时顶部 label)
  final String label;

  /// 主柱 toY(必填)
  final double value;

  /// 次柱 toY(可选,用于 grouped 双柱如本月 vs 上月)
  final double? secondaryValue;
}

/// X 轴 label builder — return null = 隐藏该 label
typedef XLabelBuilder = Widget? Function(int idx, BarChartBar bar);

/// 触摸时顶部 label 文字
typedef TouchedLabelBuilder = String? Function(int idx, BarChartBar bar);

/// 触摸时金额 tooltip 文字
typedef TooltipBuilder = String? Function(int idx, BarChartBar bar);

/// 单柱颜色解析器(默认色 / 高亮最大值柱 等场景)
typedef BarColorResolver = Color Function(int idx, BarChartBar bar);

class AnimatedBarChart extends StatefulWidget {
  const AnimatedBarChart({
    super.key,
    required this.bars,
    required this.maxVal,
    required this.chartNeedsWan,
    this.minVal, // D64.21c 加:实际最小柱值,负值启用负轴;null/0 = 老逻辑
    this.xLabelBuilder,
    this.touchedLabelBuilder,
    this.tooltipBuilder,
    this.barColorResolver,
    this.primaryColor, // 双柱场景:主柱固定色
    this.secondaryColor, // 双柱场景:次柱固定色
    this.barWidth = 5,
    this.barsSpace = 2, // 双柱内间距
    this.groupsSpace = 4, // 组间间距
  });

  final List<BarChartBar> bars;

  /// 实际最大柱值(非 maxY)。本 widget 内部按整数倍规则算出 maxY + niceInterval。
  final double maxVal;

  /// D64.21c 加:实际最小柱值(非 minY)。负值启用负轴,内部按整数倍规则算出
  /// minY = (minVal / niceInterval).floor() * niceInterval。
  final double? minVal;
  final bool chartNeedsWan;
  final XLabelBuilder? xLabelBuilder;
  final TouchedLabelBuilder? touchedLabelBuilder;
  final TooltipBuilder? tooltipBuilder;
  final BarColorResolver? barColorResolver;
  final Color? primaryColor;
  final Color? secondaryColor;
  final double barWidth;
  final double barsSpace;
  final double groupsSpace;

  @override
  State<AnimatedBarChart> createState() => _AnimatedBarChartState();
}

class _AnimatedBarChartState extends State<AnimatedBarChart>
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
  int? _touchedIdx;

  /// 触摸点的 x 位置(BarChartLeaf 内坐标)
  double? _touchedCenterX;

  /// 当前 touch 柱的 toY 值
  double? _touchedValue;

  /// 2026-10-15 D64.5:由 maxVal 算 niceInterval + 整数倍 maxY。
  /// 整数倍保证 fl_chart 不在 maxY 位置额外画 label(避免跟顶部 tick 重叠)。
  ///
  /// 2026-10-15 D64.21c:负轴支持 —— niceInterval 取 max(|minVal|, |maxVal|)
  /// 算,保证 min..max 区间按整数倍铺开。computedMinY 向下取整,floor 保证
  /// minVal 永远被包含在视图内。
  late final bool _hasNegativeAxis = (widget.minVal ?? 0) < 0;
  late final double _niceInterval = _pickNiceInterval(
    _hasNegativeAxis
        ? math.max(widget.maxVal.abs(), (widget.minVal ?? 0).abs())
        : widget.maxVal,
  );
  late final double _computedMaxY = widget.maxVal == 0 && !_hasNegativeAxis
      ? 1.0
      : (widget.maxVal / _niceInterval).ceil() * _niceInterval;
  late final double _computedMinY = _hasNegativeAxis
      ? ((widget.minVal ?? 0) / _niceInterval).floor() * _niceInterval
      : 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollPos = Scrollable.maybeOf(context)?.position;
        _scrollPos?.addListener(_checkInView);
        _checkInView();
      }
    });
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
    if (box == null || !box.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
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

  // BarChart.leftTitles.reservedSize 强绑定的偏移常量 ——
  // 改 reservedSize 时同步改这里,否则 overlay 错位
  static const double _leftReservedSize = 56;

  /// 找 pointer localPosition 最近的 bar group index
  int? _findNearestBarGroup(Offset localPosition, double chartWidth) {
    final n = widget.bars.length;
    if (n == 0) return null;
    final barWidth = widget.barWidth;
    final innerWidth = chartWidth - _leftReservedSize;
    if (innerWidth <= 0) return null;
    final innerDx = localPosition.dx - _leftReservedSize;
    if (innerDx < 0) return 0;

    // spaceBetween:每柱 barWidth + 组间 groupsSpace,均分剩余空间
    final sumBarsWidth = n * barWidth;
    final eachSpace = sumBarsWidth >= innerWidth
        ? 0.0
        : (innerWidth - sumBarsWidth) / (n - 1);

    double bestCenter = barWidth / 2;
    int bestIdx = 0;
    double bestDist = (innerDx - bestCenter).abs();
    for (int i = 1; i < n; i++) {
      final center = barWidth / 2 + i * (barWidth + eachSpace);
      final dist = (innerDx - center).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
        bestCenter = center;
      }
    }
    return bestIdx;
  }

  /// 算 group i 的中心 x(BarChartLeaf 内坐标),给 overlay Positioned 用
  double _groupCenterInner(int idx, double chartWidth) {
    final n = widget.bars.length;
    final barWidth = widget.barWidth;
    final innerWidth = chartWidth - _leftReservedSize;
    if (innerWidth <= 0 || n == 0) return 0;
    final sumBarsWidth = n * barWidth;
    final eachSpace = sumBarsWidth >= innerWidth
        ? 0.0
        : (innerWidth - sumBarsWidth) / (n - 1);
    return barWidth / 2 + idx * (barWidth + eachSpace);
  }

  void _onPointerDown(PointerDownEvent event, double chartWidth) {
    final idx = _findNearestBarGroup(event.localPosition, chartWidth);
    if (idx == null) return;
    final center = _groupCenterInner(idx, chartWidth);
    setState(() {
      _touchedIdx = idx;
      _touchedCenterX = center;
      _touchedValue = widget.bars[idx].value;
    });
  }

  void _onPointerMove(PointerMoveEvent event, double chartWidth) {
    final idx = _findNearestBarGroup(event.localPosition, chartWidth);
    if (idx == null) return;
    if (idx == _touchedIdx) return; // 同柱不重建
    final center = _groupCenterInner(idx, chartWidth);
    setState(() {
      _touchedIdx = idx;
      _touchedCenterX = center;
      _touchedValue = widget.bars[idx].value;
    });
  }

  void _onPointerEnd() {
    if (_touchedIdx != null ||
        _touchedCenterX != null ||
        _touchedValue != null) {
      setState(() {
        _touchedIdx = null;
        _touchedCenterX = null;
        _touchedValue = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: Curves.easeInOut.transform(_ctrl.value),
          child: KeyedSubtree(
            key: _chartKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth = constraints.maxWidth;
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) => _onPointerDown(e, chartWidth),
                  onPointerMove: (e) => _onPointerMove(e, chartWidth),
                  onPointerUp: (_) => _onPointerEnd(),
                  onPointerCancel: (_) => _onPointerEnd(),
                  child: _buildChart(),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildChart() {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BarChart(
          BarChartData(
            maxY: _computedMaxY,
            minY: _computedMinY,
            alignment: BarChartAlignment.spaceBetween,
            groupsSpace: widget.groupsSpace,
            barTouchData: BarTouchData(
              handleBuiltInTouches: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (_, _, _, _) => null,
              ),
              touchExtraThreshold: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: _niceInterval,
              getDrawingHorizontalLine: (v) {
                // D64.21c:0 轴线(当启用负轴)用 outline 1px,
                // 区别于普通网格线的 outlineVariant 0.5px
                if (_hasNegativeAxis && v == 0) {
                  return FlLine(
                    color: scheme.outline,
                    strokeWidth: 1,
                  );
                }
                return FlLine(
                  color: scheme.outlineVariant,
                  strokeWidth: 0.5,
                );
              },
            ),
            borderData: FlBorderData(show: false),
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
                  reservedSize: _leftReservedSize,
                  interval: _niceInterval,
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
                  // 2026-10-15 D64.5:从 14 提到 18,留够 2 字中文 category label
                  // (如"购物")的 padding(原 14 太紧,部分 label 被 fl_chart skip)。
                  reservedSize: 18,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= widget.bars.length) {
                      return const SizedBox.shrink();
                    }
                    final b = widget.xLabelBuilder;
                    if (b != null) {
                      return b(idx, widget.bars[idx]) ??
                          const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        widget.bars[idx].label,
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
            barGroups: _buildBarGroups(),
          ),
          duration: const Duration(milliseconds: 600),
          curve: AppMotion.aquaIn,
        ),
        // 触摸 overlay
        if (_touchedIdx != null && _touchedCenterX != null) ...[
          // 虚线
          Positioned(
            left: _touchedCenterX! + _leftReservedSize - 0.75,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: CustomPaint(
              painter: _DashedLinePainter(color: scheme.onSurfaceVariant),
            ),
          ),
          // 顶部 label
          Positioned(
            left: _touchedCenterX! + _leftReservedSize - 28,
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
                  widget.touchedLabelBuilder?.call(
                        _touchedIdx!,
                        widget.bars[_touchedIdx!],
                      ) ??
                      '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          // 金额 tooltip
          if (_touchedValue != null)
            Positioned(
              left: _touchedCenterX! + _leftReservedSize - 40,
              top: 26,
              width: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B), // AppBrand.ink
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.tooltipBuilder?.call(
                          _touchedIdx!,
                          widget.bars[_touchedIdx!],
                        ) ??
                        '',
                    style: const TextStyle(
                      color: Color(0xFFEAB308), // AppBrand.gold
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

  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < widget.bars.length; i++) {
      final b = widget.bars[i];
      final isSecondary = b.secondaryValue != null;
      Color primaryColor;
      if (widget.barColorResolver != null) {
        primaryColor = widget.barColorResolver!(i, b);
      } else if (widget.primaryColor != null) {
        primaryColor = widget.primaryColor!;
      } else {
        primaryColor = const Color(0xFFEF4444); // AppStatus.error
      }
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _appeared ? b.value : 0.0,
              color: primaryColor,
              width: widget.barWidth,
              // D64.21c:正值圆顶、负值圆底,跟柱条方向匹配
              borderRadius: BorderRadius.vertical(
                top: b.value >= 0 ? const Radius.circular(2) : Radius.zero,
                bottom: b.value >= 0 ? Radius.zero : const Radius.circular(2),
              ),
            ),
            if (isSecondary)
              BarChartRodData(
                toY: _appeared ? b.secondaryValue! : 0.0,
                color: widget.secondaryColor ?? const Color(0xFFE4E4E7), // g200
                width: widget.barWidth,
                borderRadius: BorderRadius.vertical(
                  top: (b.secondaryValue ?? 0) >= 0
                      ? const Radius.circular(2)
                      : Radius.zero,
                  bottom: (b.secondaryValue ?? 0) >= 0
                      ? Radius.zero
                      : const Radius.circular(2),
                ),
              ),
          ],
        ),
      );
    }
    return groups;
  }
}

/// 垂直虚线 CustomPainter ——
/// - 1.5px strokeWidth,4px 实线 + 3px 空白循环,贯穿 CustomPaint 整个高度
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

/// `Formatters.amount` from `core/utils/formatters.dart` ——
/// 已 import 真 Formatters,上面 inline 的简化版删除。

/// 2026-10-15 D64.5:从 monthly_trend.dart 移过来 —— 按 1/2/5 × 10^n 挑 niceInterval,
/// 保证 maxY 是 niceInterval 的整数倍,避免 fl_chart 在 maxY 位置额外画 label。
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
