// lib/features/stats/ui/widgets/weekday_expense.dart
// 报表第 6 张卡:周几支出分布(Mon-Sun 7 柱)
//   - user 想看"哪天爱花钱",辅助"工作日 vs 周末"消费习惯分析
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 仅本月维度有意义(本年维度按月聚合,weekday 不直观),本年维度 widget 仍按本月数据兜底
//   - 高亮最大值柱(用 AppStatus.error 实色,其它柱用 AppGray.g200 浅灰)
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 加 viewport-aware 柱条 swap + tap 选柱虚线(label + 金额)
//   - 参考 monthly_trend _AnimatedBarChart 思路(viewport-aware + 触摸选柱
//     画 dashed line + 顶部 label + 金额 tooltip)
//   - 简化:只支持 tap 选柱(touch down 显示,touch up 消失),不跟手拖
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class WeekdayExpenseChart extends ConsumerStatefulWidget {
  const WeekdayExpenseChart({super.key});

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  ConsumerState<WeekdayExpenseChart> createState() =>
      _WeekdayExpenseChartState();
}

class _WeekdayExpenseChartState extends ConsumerState<WeekdayExpenseChart> {
  // viewport-aware 触发
  bool _appeared = false;
  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;

  // tap 选柱状态
  int? _touchedIdx;
  double? _touchedValue;
  double? _touchedCenterX;

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
    final weekdayAsync = ref.watch(weekdayExpenseProvider);
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
              children: const [
                Text(
                  '周几支出',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          weekdayAsync.when(
            data: (data) {
              final maxVal = data.fold<double>(
                0,
                (a, b) => a > b.expense ? a : b.expense,
              );
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
              final niceInterval = _niceInterval(maxY);
              final chartNeedsWan = maxVal >= Formatters.wanThreshold;
              final scheme = theme.colorScheme;
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: SizedBox(
                  height: 200,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final chartWidth = constraints.maxWidth;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          KeyedSubtree(
                            key: _chartKey,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (e) =>
                                  _onPointerDown(e, chartWidth, data),
                              onPointerUp: (_) => _onPointerEnd(),
                              onPointerCancel: (_) => _onPointerEnd(),
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceBetween,
                                  groupsSpace: 4,
                                  maxY: maxY,
                                  minY: 0,
                                  barTouchData: BarTouchData(enabled: false),
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
                                        reservedSize: 24,
                                        getTitlesWidget: (value, _) {
                                          final i = value.toInt();
                                          if (i < 0 || i >= 7) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              WeekdayExpenseChart
                                                  ._weekdayLabels[i],
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  barGroups: [
                                    for (int i = 0; i < 7; i++)
                                      BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _appeared
                                                ? data[i].expense
                                                : 0,
                                            // 高亮最大值柱,其它浅灰
                                            color:
                                                data[i].expense == maxVal &&
                                                    maxVal > 0
                                                ? AppStatus.error
                                                : AppGray.g200,
                                            width: 18,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(2),
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
                            // 顶部周几 label
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
                                    '周${WeekdayExpenseChart._weekdayLabels[_touchedIdx!]}',
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

  void _onPointerDown(
    PointerDownEvent event,
    double chartWidth,
    List<WeekdayExpense> data,
  ) {
    const reservedLeft = 38.0;
    final innerDx = event.localPosition.dx - reservedLeft;
    if (innerDx < 0) return;
    const n = 7;
    const barWidth = 18.0;
    const groupSpacing = 4.0;
    final totalGroupWidth = n * barWidth + (n - 1) * groupSpacing;
    final innerWidth = chartWidth - reservedLeft;
    final eachSpace = (innerWidth - totalGroupWidth) / (n + 1);
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < n; i++) {
      final groupStart =
          reservedLeft + eachSpace * (i + 1) + i * (barWidth + groupSpacing);
      final groupCenter = groupStart + barWidth / 2;
      final dist = (event.localPosition.dx - groupCenter).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    final groupStart =
        reservedLeft +
        eachSpace * (bestIdx + 1) +
        bestIdx * (barWidth + groupSpacing);
    final groupCenter = groupStart + barWidth / 2;
    setState(() {
      _touchedIdx = bestIdx;
      _touchedCenterX = groupCenter - reservedLeft;
      _touchedValue = data[bestIdx].expense;
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

class _AquaInCurve extends Curve {
  const _AquaInCurve();
  @override
  double transformInternal(double t) => Curves.easeOutCubic.transform(t);
}
