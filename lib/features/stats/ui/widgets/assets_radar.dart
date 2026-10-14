// lib/features/stats/ui/widgets/assets_radar.dart
// stats 资产视角 — 6 维自绘雷达图(CustomPainter 替换原 fl_chart RadarChart)
//
// 2026-10-13 P6 第 N 次改(2026-10-13 13:35 UAT:"雷达图没了,换成条形图,不行,
//   我就是要雷达图"):
//   - 之前用 fl_chart 0.69 RadarChart,发现算法特性导致差异视觉放大:
//     `centerValue = data.minEntry.value - (data.maxEntry.value - data.minEntry.value) / tickCount`
//     归一化 = (point.value - centerValue) / (data.maxEntry.value - centerValue)
//     当 6 段数据接近时(9990 vs 10000),差异被挤在最外 1 tick 内视觉放大
//   - 改方案 B:用 CustomPainter 自绘雷达图,**归一化用 `value / maxValue` 直接除**:
//       maxValue = max(values) = 10000
//       现金流 ratio = 9990 / 10000 = 0.999 (99.9% 半径,几乎贴边)
//       其它 ratio = 1.0 (贴最外圈)
//       0.1% 真实差异 → 0.1% 视觉差异,不再放大
//   - 自绘所有元素:6 边形 grid(4 圈)+ 6 spoke + 6 label + 数据多边形 + 6 entry 圆点
//   - TweenAnimationBuilder 0→1 让数据从中心撑开(1200ms aquaIn)
//
// 2026-10-12 P4 commit 加(P4 · 资产分布 + 雷达图):
//   - 原 fl_chart 6 维雷达图,viewport-aware 触发 fade-in
//
// 2026-10-13 P6 第 2 次改(UAT 反馈"雷达图不会动态"):
//   - 加 TweenAnimationBuilder 0→1 缩放,数据 values 乘以 progress
//
// 2026-10-13 P6 改 4 维 → 6 维(跟 asset_form 6 段同步)
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';

class AssetsRadar extends ConsumerStatefulWidget {
  const AssetsRadar({super.key});

  @override
  ConsumerState<AssetsRadar> createState() => _AssetsRadarState();
}

class _AssetsRadarState extends ConsumerState<AssetsRadar> {
  /// viewport-aware 触发(同款 pattern)
  bool _appeared = false;
  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final totalsAsync = ref.watch(assetTotalsProvider);
    return Container(
      key: _chartKey,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '资产分布',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '正负值都反映',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s3),
            child: totalsAsync.when(
              loading: () => const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Text(
                  '加载资产失败:$e',
                  style: const TextStyle(color: AppStatus.error),
                ),
              ),
              data: (totals) {
                // 6 段(顺序按日常查看频度,跟总览卡一致)
                final entries = <_RadarEntry>[
                  _RadarEntry(
                    label: '现金流',
                    value: totals.totalCashFlow,
                    color: AppBrand.teal,
                  ),
                  _RadarEntry(
                    label: '投资',
                    value: totals.totalInvestment,
                    color: AppBrand.gold,
                  ),
                  _RadarEntry(
                    label: '福利',
                    value: totals.totalBenefit,
                    color: AppStatus.success,
                  ),
                  _RadarEntry(
                    // 2026-10-14 D51 v2:从"债权"改"债务",跟 AppSegment.labelFor 同步
                    label: '债务',
                    value: totals.totalReceivable,
                    color: AppStatus.warning,
                  ),
                  _RadarEntry(
                    label: '不动产',
                    value: totals.totalFixedAsset,
                    color: AppStatus.info,
                  ),
                  _RadarEntry(
                    label: '其它',
                    value: totals.totalOther,
                    color: AppGray.g600,
                  ),
                ];
                // 极端 case:6 个都 0 → 显示空态
                if (entries.every((e) => e.value.abs() == 0)) {
                  return const SizedBox(
                    height: 280,
                    child: Center(
                      child: Text(
                        '还没有资产数据',
                        style: TextStyle(color: AppGray.g600, fontSize: 13),
                      ),
                    ),
                  );
                }
                // maxValue 用 abs 后的最大值(防止负值让 max 出奇)
                // 归一化用 `value / maxValue` 直接除(我们控制,不走 fl_chart 算法)
                final maxAbs = entries
                    .map((e) => e.value.abs())
                    .reduce((a, b) => a > b ? a : b);

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: _appeared ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: AppMotion.aquaIn,
                  builder: (context, progress, _) {
                    return SizedBox(
                      height: 280,
                      child: AnimatedOpacity(
                        opacity: _appeared ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 360),
                        curve: AppMotion.aquaIn,
                        child: CustomPaint(
                          painter: _RadarPainter(
                            entries: entries,
                            maxValue: maxAbs,
                            progress: progress,
                            gridColor: theme.colorScheme.outlineVariant,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            primary: AppBrand.teal,
                            primaryFill: AppBrand.teal.withValues(alpha: 0.18),
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 雷达图单维数据
class _RadarEntry {
  const _RadarEntry({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

/// 自绘 6 维雷达图
///   - 4 圈同心 6 边形 grid(0.25 / 0.5 / 0.75 / 1.0 比例)
///   - 6 spoke(从中心到外圈)
///   - 6 label(顶部 12% 偏移,沿 spoke 方向)
///   - 数据多边形 + fill(归一化 `value / maxValue`,乘以 progress 让从中心撑开)
///   - 6 entry 圆点(entryRadius 3)
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.entries,
    required this.maxValue,
    required this.progress,
    required this.gridColor,
    required this.labelStyle,
    required this.primary,
    required this.primaryFill,
  });

  final List<_RadarEntry> entries;
  final double maxValue;
  final double progress;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color primary;
  final Color primaryFill;

  /// grid 圈数(0.25 / 0.5 / 0.75 / 1.0)
  static const int _gridLevels = 4;

  /// label 离外圈的偏移比例(2026-10-13 P6 UAT:0.05 → 0.12,离端点更远)
  static const double _labelOffset = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 留 label 空间:radius 缩到 min * 0.4
    final radius = math.min(size.width, size.height) / 2 * 0.78;

    // 角度:6 个轴,顶部为 -π/2
    final n = entries.length;
    final angleStep = 2 * math.pi / n;

    // 1. 画 grid 圈(4 圈同心 6 边形)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (int level = 1; level <= _gridLevels; level++) {
      final r = radius * (level / _gridLevels);
      final path = _polygonPath(center, r, n, -math.pi / 2);
      canvas.drawPath(path, gridPaint);
    }

    // 2. 画 6 spoke(从中心到外圈)
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * angleStep;
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, gridPaint);
    }

    // 3. 画 6 label(沿 spoke 方向,外圈 +12% 偏移)
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * angleStep;
      final labelR = radius * (1 + _labelOffset);
      final labelPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );
      _drawLabel(canvas, labelPos, entries[i].label, angle);
    }

    // 4. 画数据多边形 + fill
    // 归一化:`value / maxValue`,乘以 progress 让从中心撑开
    // maxValue = 0 时(6 段都 0 走空态)不会到这里
    final dataPath = Path();
    final dataPoints = <Offset>[];
    for (int i = 0; i < n; i++) {
      final ratio = (entries[i].value.abs() / maxValue) * progress;
      final angle = -math.pi / 2 + i * angleStep;
      final r = radius * ratio;
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      dataPoints.add(pt);
      if (i == 0) {
        dataPath.moveTo(pt.dx, pt.dy);
      } else {
        dataPath.lineTo(pt.dx, pt.dy);
      }
    }
    dataPath.close();

    // fill
    canvas.drawPath(dataPath, Paint()..color = primaryFill);
    // border
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = primary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // 5. 画 6 entry 圆点
    final dotPaint = Paint()..color = primary;
    for (final pt in dataPoints) {
      canvas.drawCircle(pt, 3, dotPaint);
    }
  }

  /// 画 6 边形 path,起始角度 startAngle(默认 -π/2 即顶部)
  Path _polygonPath(Offset center, double radius, int n, double startAngle) {
    final path = Path();
    for (int i = 0; i < n; i++) {
      final angle = startAngle + i * 2 * math.pi / n;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  /// 画 label:在 labelPos 位置居中,根据 angle 调整 anchor
  ///   - 上方 (-π/2 ~ -π/6 + π/6):bottomCenter anchor
  ///   - 侧方:left/rightCenter anchor
  ///   - 下方 (-π/6 ~ 0 或 0 ~ π/6):topCenter anchor
  void _drawLabel(Canvas canvas, Offset labelPos, String text, double angle) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // 算 anchor 偏移:让 label 沿 spoke 方向离端点更远
    //   - angle 接近 -π/2 (顶部):label 在 pt 上方
    //   - angle 接近 0 (右侧):label 在 pt 右侧
    //   - angle 接近 π/2 (底部):label 在 pt 下方
    //   - 等等
    double dx = 0, dy = 0;
    if (angle > -math.pi * 5 / 6 && angle < -math.pi / 6) {
      // 上方(顶部 60° 范围):anchor bottomCenter
      dy = -textPainter.height / 2;
    } else if (angle > math.pi / 6 && angle < math.pi * 5 / 6) {
      // 下方(底部 60° 范围):anchor topCenter
      dy = textPainter.height / 2;
    } else {
      // 左侧(π/6 ~ π/6 中间,实际不会到这里因为 6 等分)
      dy = 0;
    }
    // 水平 anchor:右侧 spokes anchor 偏左,左侧 spokes anchor 偏右
    if (angle > -math.pi / 6 && angle < math.pi / 6) {
      // 右侧(0° 方向 ±30°)
      dx = textPainter.width / 2;
    } else if (angle > math.pi * 5 / 6 || angle < -math.pi * 5 / 6) {
      // 左侧(180° 方向 ±30°)
      dx = -textPainter.width / 2;
    } else {
      dx = 0;
    }

    final offset = Offset(
      labelPos.dx - textPainter.width / 2 + dx,
      labelPos.dy - textPainter.height / 2 + dy,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_RadarPainter old) {
    return old.maxValue != maxValue ||
        old.progress != progress ||
        old.gridColor != gridColor ||
        old.labelStyle != labelStyle ||
        old.primary != primary ||
        old.entries != entries;
  }
}
