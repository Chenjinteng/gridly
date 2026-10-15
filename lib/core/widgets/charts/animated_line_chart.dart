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
// 业务 widget 用法参考 savings_trend.dart。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../motion/app_motion.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// 单个点的数据
class LineChartPoint {
  const LineChartPoint({
    required this.label,
    required this.value,
  });

  /// X 轴 label(用于底部显示 + 触摸时顶部 label)
  final String label;

  /// Y 值(主柱 toY 等价)
  final double value;
}

/// X 轴 label builder — return null = 隐藏该 label
typedef XLabelBuilder = Widget? Function(int idx, LineChartPoint point);

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

  late final double _computedMinY = widget.minVal ?? 0.0;
  late final double _computedMaxY = widget.maxVal ??
      (widget.points.isEmpty
          ? 1.0
          : widget.points
              .map((p) => p.value)
              .fold<double>(0, (a, b) => a > b ? a : b));

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
              handleBuiltInTouches: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (_) => [],
              ),
              touchSpotThreshold: 8,
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
                        ? widget.pointColorResolver!(index, widget.points[index])
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
            left: _xPosition(_touchedIdx!, _chartWidth!) + _leftReservedSize - 0.75,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: CustomPaint(
              painter: _DashedLinePainter(color: scheme.onSurfaceVariant),
            ),
          ),
          Positioned(
            left: _xPosition(_touchedIdx!, _chartWidth!) + _leftReservedSize - 28,
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
