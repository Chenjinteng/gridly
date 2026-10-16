// lib/core/widgets/charts/animated_line_chart.dart
// 2026-10-15 D64.27 加:共享的折线图 widget
//
// 跟 animated_bar_chart.dart 镜像设计(ChartCard 内嵌 + 触摸 overlay +
// viewport-aware 入场动画),区别:
//   - 数据是连续的点序列(LineChartData 的 spots),不是离散的柱条
//   - X 轴 label / tooltip 文字 走 builder 回调(跟柱状同款)
//   - 颜色:整条线统一 1 色(品牌色 teal),点之间不切换
//   - 点的颜色按 value 区分(可选):正 teal / 负 error 红
//   - 0 轴线(D64.21c 同款):minY < 0 时自动画 y=0 outline 1px 横线
//
// 2026-10-16 D64.29 改:
//   - 加 `_pickNiceInterval` + `_computedMaxY` / `_computedMinY`(镜像
//     `AnimatedBarChart` D64.21c),保证 maxY/minY 是 niceInterval 的整数倍,
//     避免 maxY=189.02 时 fl_chart 选 interval=50 但 0/-50 视觉重叠的 bug
//   - 新增 `axisLabelBuilder` 回调参数(镜像 `xLabelBuilder`),默认回落到
//     `Formatters.amount(v, forceWan, trimTrailingZeros)` 保持向后兼容。
//     储蓄走势(D64.27)百分比不该有 ".02" 小数,通过这个 callback 走
//     `v.toStringAsFixed(0)` 输出整数百分比。
//
// 业务 widget 用法参考 savings_trend.dart。
//
// 2026-10-16 D64.39 改:
//   - user UAT 反馈触摸储蓄走势时 fl_chart 抛错 `tooltipItems and
//     touchedSpots size should be same`(连续 17 次 Exception) —— 跟 user 观察
//     的'虚线对不上'是同一根因:触摸时 fl_chart 内部 LineTouchData
//     `handleBuiltInTouches: true` 启用内置触摸 + 我们外层 Listener
//     (HitTestBehavior.translucent) 也接触摸,两路触摸同时触发:
//     - fl_chart 内部 GestureDetector 接触摸 → 算 touchedSpots(非空)
//     - getTooltipItems 回调被调用 → 返回 [] (空)→ 长度不匹配 → 抛错
//     - 同时我们的外层 Listener 算 _touchedIdx 跟 fl_chart 内部 idx 不一致,
//       dashed line 落位就出现"虚线对不上"的视觉错位
//   - 修法:LineTouchData `handleBuiltInTouches: false`,fl_chart 不参与触摸,
//     完全由外层 Listener (Listener 模式,跟 Speed Dial 同款避开 GestureDetector
//     冲突) 自己处理触摸和 dashed line / label 渲染,消除双重触摸路径 + 异常
//   - touchTooltipData 不传 —— fl_chart 不参与触摸就不会触发 getTooltipItems
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../motion/app_motion.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// 单个点的数据
class LineChartPoint {
  const LineChartPoint({required this.label, required this.value});

  /// X 轴 label(用于底部显示 + 触摸时顶部 label)
  final String label;

  /// Y 值(主柱 toY 等价)
  final double value;
}

/// X 轴 label builder — return null = 隐藏该 label
typedef XLabelBuilder = Widget? Function(int idx, LineChartPoint point);

/// Y 轴 label builder(D64.29 加)—— 跟 fl_chart `SideTitles.getTitlesWidget`
/// 镜像签名 (value, meta)。默认(不传)走 Formatters.amount,储蓄走势传
/// `(v, _) => v.toStringAsFixed(0)` 输出整数百分比。
typedef AxisLabelBuilder = String Function(double value, TitleMeta meta);

/// 触摸时顶部 label 文字
typedef TouchedLabelBuilder = String? Function(int idx, LineChartPoint point);

/// 触摸时 tooltip 文字
typedef TooltipBuilder = String? Function(int idx, LineChartPoint point);

/// 单点颜色解析器(可选,默认单色)
typedef PointColorResolver = Color Function(int idx, LineChartPoint point);

class AnimatedLineChart extends StatefulWidget {
  const AnimatedLineChart({
    super.key,
    required this.points,
    required this.chartNeedsWan,
    this.maxVal,
    this.minVal,
    this.xLabelBuilder,
    this.axisLabelBuilder, // D64.29 加:Y 轴 label 格式
    this.touchedLabelBuilder,
    this.tooltipBuilder,
    this.pointColorResolver,
    this.lineColor, // 默认 teal
    this.gridColor, // 默认 outlineVariant
  });

  final List<LineChartPoint> points;
  final bool chartNeedsWan;
  final double? maxVal; // null = 自动算
  final double? minVal; // null = 自动算(>= 0)
  final XLabelBuilder? xLabelBuilder;
  final AxisLabelBuilder? axisLabelBuilder; // D64.29 加
  final TouchedLabelBuilder? touchedLabelBuilder;
  final TooltipBuilder? tooltipBuilder;
  final PointColorResolver? pointColorResolver;
  final Color? lineColor;
  final Color? gridColor;

  @override
  State<AnimatedLineChart> createState() => _AnimatedLineChartState();
}

class _AnimatedLineChartState extends State<AnimatedLineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _appeared = false;
  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;
  int? _touchedIdx;
  double? _chartWidth;

  // D64.29 加:nice interval + 对称 minY/maxY(镜像 AnimatedBarChart D64.21c)
  //   - maxVal=30, minVal=-189 → niceInterval = max(|30|,|189|) = 189 → 50
  //   - computedMaxY = ceil(30/50)*50 = 50
  //   - computedMinY = floor(-189/50)*50 = -200
  //   → ticks 在 [-200, 50] 整数倍上,不再出现 0 / -50 重叠 / 189.02 这种浮点
  //
  // widget.maxVal / widget.minVal 可为 null —— 不传时从 points 自动算(原 D64.27
  // 行为),保证 caller 不传也能跑,保持向后兼容。
  double _autoMaxVal() => widget.points.isEmpty
      ? 1.0
      : widget.points
            .map((p) => p.value)
            .fold<double>(0, (a, b) => a > b ? a : b);

  double _autoMinVal() => widget.points.isEmpty
      ? 0.0
      : widget.points
            .map((p) => p.value)
            .fold<double>(0, (a, b) => a < b ? a : b);

  double get _eMax => widget.maxVal ?? _autoMaxVal();
  double get _eMin => widget.minVal ?? _autoMinVal();

  late final bool _hasNegativeAxis = _eMin < 0;
  late final double _niceInterval = _pickNiceInterval(
    _hasNegativeAxis ? math.max(_eMax.abs(), _eMin.abs()) : _eMax,
  );
  late final double _computedMaxY = _eMax == 0 && !_hasNegativeAxis
      ? 1.0
      : (_eMax / _niceInterval).ceil() * _niceInterval;
  late final double _computedMinY = _hasNegativeAxis
      ? (_eMin / _niceInterval).floor() * _niceInterval
      : 0.0;

  static const double _leftReservedSize = 56;

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
                _chartWidth = chartWidth;
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

  int? _findNearestPoint(Offset localPosition, double chartWidth) {
    final n = widget.points.length;
    if (n == 0) return null;
    final innerWidth = chartWidth - _leftReservedSize;
    if (innerWidth <= 0) return null;
    final innerDx = localPosition.dx - _leftReservedSize;
    if (innerDx < 0) return 0;
    final stepX = innerWidth / (n - 1);
    final idx = (innerDx / stepX).round().clamp(0, n - 1);
    return idx;
  }

  void _onPointerDown(PointerDownEvent event, double chartWidth) {
    final idx = _findNearestPoint(event.localPosition, chartWidth);
    if (idx == null) return;
    setState(() {
      _touchedIdx = idx;
    });
  }

  void _onPointerMove(PointerMoveEvent event, double chartWidth) {
    if (_touchedIdx == null) return;
    final idx = _findNearestPoint(event.localPosition, chartWidth);
    if (idx == null || idx == _touchedIdx) return;
    setState(() {
      _touchedIdx = idx;
    });
  }

  void _onPointerEnd() {
    if (_touchedIdx != null) {
      setState(() {
        _touchedIdx = null;
      });
    }
  }

  Widget _buildChart() {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = widget.lineColor ?? AppBrand.teal;
    final gridColor = widget.gridColor ?? scheme.outlineVariant;
    final hasNegative = _computedMinY < 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        LineChart(
          LineChartData(
            minX: 0,
            maxX: (widget.points.length - 1).toDouble(),
            minY: _computedMinY,
            maxY: _computedMaxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              // D64.29 加:跟 leftTitles interval 对齐,网格线对齐 Y 轴 tick
              horizontalInterval: _niceInterval,
              getDrawingHorizontalLine: (v) {
                if (hasNegative && v == 0) {
                  return FlLine(color: scheme.outline, strokeWidth: 1);
                }
                return FlLine(color: gridColor, strokeWidth: 0.5);
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
                  // D64.29 加:用 niceInterval 取代 fl_chart 自动 interval,
                  // 避免 0/-50 重叠 / 189.02 这种浮点小数的边角 label
                  interval: _niceInterval,
                  getTitlesWidget: (v, meta) {
                    final label =
                        widget.axisLabelBuilder?.call(v, meta) ??
                        Formatters.amount(
                          v,
                          forceWan: widget.chartNeedsWan,
                          trimTrailingZeros: true,
                        );
                    return Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= widget.points.length) {
                      return const SizedBox.shrink();
                    }
                    final p = widget.xLabelBuilder;
                    if (p != null) {
                      return p(idx, widget.points[idx]) ??
                          const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        widget.points[idx].label,
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
            lineTouchData: LineTouchData(
              // D64.39 改:`handleBuiltInTouches: false` 让 fl_chart 不参与触摸,
              //   完全由外层 Listener (HitTestBehavior.translucent) 自己处理,
              //   避免双重触摸路径 + tooltipItems/touchedSpots 长度不匹配异常
              //   + 内外 idx 不一致导致的'虚线对不上'视觉错位
              handleBuiltInTouches: false,
              // 不传 touchTooltipData —— fl_chart 不参与触摸就不会触发
              //   getTooltipItems,无 tooltip 渲染需求
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < widget.points.length; i++)
                    FlSpot(
                      i.toDouble(),
                      _appeared ? widget.points[i].value : _computedMinY,
                    ),
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                color: lineColor,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final color = widget.pointColorResolver != null
                        ? widget.pointColorResolver!(
                            index,
                            widget.points[index],
                          )
                        : lineColor;
                    return FlDotCirclePainter(
                      radius: 3,
                      color: color,
                      strokeWidth: 1.5,
                      strokeColor: scheme.surface,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: lineColor.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 600),
          curve: AppMotion.aquaIn,
        ),
        // 触摸 overlay(1.5px 垂直虚线 + 顶部 label + 金额 tooltip)
        if (_touchedIdx != null && _chartWidth != null) ...[
          Positioned(
            left:
                _xPosition(_touchedIdx!, _chartWidth!) +
                _leftReservedSize -
                0.75,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: CustomPaint(
              painter: _DashedLinePainter(color: scheme.onSurfaceVariant),
            ),
          ),
          Positioned(
            left:
                _xPosition(_touchedIdx!, _chartWidth!) + _leftReservedSize - 28,
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
                        widget.points[_touchedIdx!],
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
        ],
      ],
    );
  }

  double _xPosition(int idx, double chartWidth) {
    final n = widget.points.length;
    if (n <= 1) return 0;
    final innerWidth = chartWidth - _leftReservedSize;
    final stepX = innerWidth / (n - 1);
    return idx * stepX;
  }
}

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

/// D64.29 加(从 animated_bar_chart.dart 拷一份,避免共享 top-level 函数跨文件依赖):
/// 按 1/2/5 × 10^n 候选挑 niceInterval,保证 maxY 是 niceInterval 的整数倍,
/// 避免 fl_chart 在 maxY 位置额外画小 label(跟 0 重叠)。
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
