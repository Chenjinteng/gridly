// lib/features/stats/ui/widgets/category_compare.dart
// 报表第 5 张卡:本月 vs 上月 各类别支出对比
//   - 类别维度:每类 2 柱(本月 + 上月),看"哪类涨 / 哪类降"
//   - 跟 12 月月度趋势区别:monthlyTrendProvider 看时间维度(每月总额),这个看类别维度
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 取前 6 类按本月+上月合计从大到小,过小的隐藏避免柱子太挤
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 加 viewport-aware 柱条 swap + tap 选柱虚线(label + 金额)
//   - 参考 monthly_trend _AnimatedBarChart 实现思路(viewport-aware + 触摸
//     选柱时画 dashed line + 顶部 label + 金额 tooltip)
//   - 简化:只支持 tap 选柱(touch down 显示,touch up 消失),不跟手拖
//     (monthly_trend 的拖动逻辑依赖空间位置,2 柱类对比场景不必要)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class CategoryCompareChart extends ConsumerStatefulWidget {
  const CategoryCompareChart({super.key});

  @override
  ConsumerState<CategoryCompareChart> createState() =>
      _CategoryCompareChartState();
}

class _CategoryCompareChartState extends ConsumerState<CategoryCompareChart> {
  // viewport-aware 触发:false → 柱条 toY=0;true → setState 让 BarChart
  // swap animation 600ms 从 0 推到 real
  bool _appeared = false;
  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;

  // tap 选柱(简化版,只 tap 触发 + dismiss)
  int? _touchedIdx;
  double? _touchedValue; // 当前柱的金额(本月 column)
  double? _touchedCenterX; // 虚线 x 位置(BarChartLeaf 内坐标)

  @override
  void initState() {
    super.initState();
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
      setState(() => _appeared = true);
      return;
    }
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null) return;
    final top = box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
    if (top < scrollableBox.size.height && top + box.size.height > 0) {
      setState(() => _appeared = true);
    }
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compareAsync = ref.watch(categoryCompareProvider);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  '类别对比',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: const [
                    _LegendDot(color: AppStatus.error, label: '本月'),
                    SizedBox(width: AppSpacing.s3),
                    _LegendDot(color: AppGray.g200, label: '上月'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          compareAsync.when(
            data: (data) {
              if (data.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final shown = data.take(6).toList();
              final maxVal = shown
                  .map(
                    (e) => e.currAmount > e.prevAmount
                        ? e.currAmount
                        : e.prevAmount,
                  )
                  .fold<double>(0, (a, b) => a > b ? a : b);
              if (maxVal == 0) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final maxY = maxVal * 1.15;
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              final niceInterval = _niceInterval(maxY);
              final scheme = theme.colorScheme;
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: SizedBox(
                  height: 220,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final chartWidth = constraints.maxWidth;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // BarChart(swap animation + 触摸选柱)
                          KeyedSubtree(
                            key: _chartKey,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (e) => _onPointerDown(
                                e,
                                chartWidth,
                                shown,
                                niceInterval,
                              ),
                              onPointerUp: (_) => _onPointerEnd(),
                              onPointerCancel: (_) => _onPointerEnd(),
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceBetween,
                                  groupsSpace: 4,
                                  maxY: maxY,
                                  minY: 0,
                                  barTouchData: BarTouchData(
                                    enabled: false, // 触摸走自画 Listener
                                  ),
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    horizontalInterval: niceInterval,
                                    getDrawingHorizontalLine: (_) => FlLine(
                                      color: scheme.outlineVariant,
                                      strokeWidth: 0.5,
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 38,
                                        interval: niceInterval,
                                        getTitlesWidget: (value, _) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4,
                                          ),
                                          child: Text(
                                            chartNeedsWan
                                                ? '${(value / 10000).toStringAsFixed(value >= 10000 ? 0 : 1)}万'
                                                : value.toInt().toString(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 32,
                                        getTitlesWidget: (value, _) {
                                          final i = value.toInt();
                                          if (i < 0 || i >= shown.length) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              shown[i].name,
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  barGroups: [
                                    for (int i = 0; i < shown.length; i++)
                                      BarChartGroupData(
                                        x: i,
                                        barsSpace: 2,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _appeared
                                                ? shown[i].currAmount
                                                : 0,
                                            color: AppStatus.error,
                                            width: 8,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                          BarChartRodData(
                                            toY: _appeared
                                                ? shown[i].prevAmount
                                                : 0,
                                            color: AppGray.g200,
                                            width: 8,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                duration: const Duration(milliseconds: 600),
                                curve: const _AquaInCurve(),
                              ),
                            ),
                          ),
                          // 触摸 overlay:虚线 + 顶部 label + 金额 tooltip
                          if (_touchedIdx != null &&
                              _touchedCenterX != null) ...[
                            // 虚线
                            Positioned(
                              left: _touchedCenterX! - 0.75,
                              top: 0,
                              bottom: 0,
                              width: 1.5,
                              child: CustomPaint(
                                painter: _DashedLinePainter(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            // 顶部类目 label
                            Positioned(
                              left: _touchedCenterX! - 28,
                              top: 0,
                              width: 56,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    shown[_touchedIdx!].name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            // 金额 tooltip
                            if (_touchedValue != null)
                              Positioned(
                                left: _touchedCenterX! - 40,
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
                                      style: const TextStyle(
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
                    },
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.s3),
              child: Text(
                '加载失败:$e',
                style: const TextStyle(color: AppStatus.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 触摸 down:找最近的 group,记录 idx + centerX + value
  void _onPointerDown(
    PointerDownEvent event,
    double chartWidth,
    List<CategoryCompare> shown,
    double niceInterval,
  ) {
    // 简单算法:BarChartAlignment.spaceBetween + groupsSpace 4,
    //   每 group 2 柱 width 8 + 柱间距 2,加 groupsSpace 4
    //   group width ≈ 2*8 + 2 + 4 = 22,均匀分布
    // (跟 fl_chart spaceBetween 实际渲染对齐)
    const reservedLeft = 38.0; // leftTitles reservedSize
    final innerDx = event.localPosition.dx - reservedLeft;
    if (innerDx < 0) return;
    final n = shown.length;
    if (n == 0) return;
    const groupWidth = 2 * 8.0 + 2.0; // 2 柱 + 柱间 2
    const groupSpacing = 4.0;
    final totalGroupWidth = n * groupWidth + (n - 1) * groupSpacing;
    final innerWidth = chartWidth - reservedLeft;
    final eachSpace = (innerWidth - totalGroupWidth) / (n + 1); // 两侧 + 组间均分
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < n; i++) {
      final groupStart =
          reservedLeft + eachSpace * (i + 1) + i * (groupWidth + groupSpacing);
      final groupCenter = groupStart + groupWidth / 2;
      final dist = (event.localPosition.dx - groupCenter).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    final groupStart =
        reservedLeft +
        eachSpace * (bestIdx + 1) +
        bestIdx * (groupWidth + groupSpacing);
    final groupCenter = groupStart + groupWidth / 2;
    setState(() {
      _touchedIdx = bestIdx;
      _touchedCenterX = groupCenter - reservedLeft; // 转 BarChartLeaf 内坐标
      _touchedValue = shown[bestIdx].currAmount;
    });
  }

  void _onPointerEnd() {
    if (_touchedIdx == null) return;
    setState(() {
      _touchedIdx = null;
      _touchedValue = null;
      _touchedCenterX = null;
    });
  }
}

double _niceInterval(double maxY) {
  if (maxY <= 0) return 100;
  final v = maxY / 5;
  if (v <= 0) return 1;
  final exp = v.toString().split('.').first.length - 1;
  final n = _pow10(exp < 0 ? 0 : exp);
  final cands = [n.toDouble(), (2 * n).toDouble(), (5 * n).toDouble()];
  return cands.reduce((a, b) => (a - v).abs() < (b - v).abs() ? a : b);
}

int _pow10(int n) {
  int r = 1;
  for (int i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppGray.g600)),
      ],
    );
  }
}

/// 垂直虚线 painter(1.5px strokeWidth,[4,3] dash 循环)
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
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// aquaIn 曲线(用于 BarChart swap animation 600ms)
class _AquaInCurve extends Curve {
  const _AquaInCurve();
  @override
  double transformInternal(double t) {
    // 简单 cubic:前快后慢
    return Curves.easeOutCubic.transform(t);
  }
}
