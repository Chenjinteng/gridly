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
//       流动资金 ratio = 9990 / 10000 = 0.999 (99.9% 半径,几乎贴边)(D64.40 改"流动资金")
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
//
// 2026-10-16 D64.33 改:
//   - 6 维 → 5 维,去掉 receivable(债务)轴 —— 跟净资产口径对齐
//     (净资产 = 5 段真资产 + max(0, receivable),debt 不能进"我实际拥有"雷达)
//   - painter 用 entries.length 自动适配 5 边形:
//     n=5 → 5 grid 圈(同心 5 边形)+ 5 spoke + 5 label + 数据多边形 5 顶
//     原始算法不变,仅 entries 缩短 1 项
//
// 2026-10-16 D64.38 改:
//   - user UAT 反馈"雷达图实际是'我的资产构成',5 个角想加(百分比)表示占比"
//   - 修法:`_RadarEntry` 加 `percent` 字段(预计算,基于 5 段 sum 作分母),
//     painter `_drawLabel` 改 2 行布局 — 上行原 label(类型名 w600 11sp),
//     下行百分比例如"75%"(w500 10sp + onSurfaceVariant 灰)
//   - 分母 = 5 段真资产 sum(cash_flow + investment + benefit + fixed_asset + other),
//     跟净资产卡 D64.36 的"总资产"口径一致(不含 receivable 负债段)
//   - 视觉:类型名 + 百分比 形成"标签 = 段名 + 占总资产比例",跟净资产卡
//     末尾'总资产 ¥XXX' 串起来形成'每段占总资产 X%' 直观图
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/widgets/once_visible.dart';

class AssetsRadar extends ConsumerStatefulWidget {
  const AssetsRadar({super.key});

  @override
  ConsumerState<AssetsRadar> createState() => _AssetsRadarState();
}

class _AssetsRadarState extends ConsumerState<AssetsRadar> {
  // 2026-10-16 D64.89 改:viewport-aware 触发走 OnceVisible wrapper
  //   - 之前 inline _appeared / _chartKey / _scrollPos / _checkInView 50+ 行 boilerplate
  //   - 跟 asset_allocation_chart / expense_analysis._AccountTab 完全同款
  //   - 改:OnceVisible(builder: (ctx, appeared) => ...) 一行替代,3 处共用

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalsAsync = ref.watch(assetTotalsProvider);
    return OnceVisible(
      builder: (context, appeared) => Container(
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
                // D64.34:删 trailing "正负值都反映"
                //   - 原因:花呗归到 receivable(债务)段后,cash_flow 不再有花呗
                //     欠款导致的负值,5 段基本都是"我有 X"的语义
                //   - 5 段资产理论上仍可负(如全部花光),但语义已经统一成"我实际拥有",
                //     不再有"正负都反映"的争议
                const SizedBox.shrink(),
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
                // D64.33:5 维雷达图,顺序按日常查看频度,跟总览卡 5 段一致
                // (debt/receivable 已摘出 —— 净资产口径不包含"我欠的"或"应收未到")
                //
                // D64.38:算 5 段真资产 sum 作分母,每段算百分比
                //   - 分母跟净资产卡 D64.36 "总资产"口径一致(不含 receivable 负债段)
                //   - 某段为负(如流动资金花光成负,D64.40 cash_flow 改"流动资金"):百分比自然为负,反映"负贡献"
                //   - 5 段全 0 走空态 early-return,不会到这里
                // D64.40:5 段 label 改走 AppSegment.labelFor,统一中文命名(流动资金/投资/福利/不动产/其它)
                final totalAssets =
                    totals.totalCashFlow +
                    totals.totalInvestment +
                    totals.totalBenefit +
                    totals.totalFixedAsset +
                    totals.totalOther;
                double pctOf(double v) =>
                    totalAssets == 0 ? 0 : (v / totalAssets) * 100;
                final entries = <_RadarEntry>[
                  _RadarEntry(
                    label: AppSegment.labelFor('cash_flow'),
                    value: totals.totalCashFlow,
                    // D71.2:跟随 palette(浅粉 → 深粉,默认 → 青绿)
                    color: theme.colorScheme.primary,
                    percent: pctOf(totals.totalCashFlow),
                  ),
                  _RadarEntry(
                    label: AppSegment.labelFor('investment'),
                    value: totals.totalInvestment,
                    // D71.2:跟随 palette(浅粉 → 亮粉,默认 → 金黄)
                    color: theme.colorScheme.secondary,
                    percent: pctOf(totals.totalInvestment),
                  ),
                  _RadarEntry(
                    label: AppSegment.labelFor('benefit'),
                    value: totals.totalBenefit,
                    color: AppStatus.success,
                    percent: pctOf(totals.totalBenefit),
                  ),
                  _RadarEntry(
                    label: AppSegment.labelFor('fixed_asset'),
                    value: totals.totalFixedAsset,
                    color: AppStatus.info,
                    percent: pctOf(totals.totalFixedAsset),
                  ),
                  _RadarEntry(
                    label: AppSegment.labelFor('other'),
                    value: totals.totalOther,
                    color: AppGray.g600,
                    percent: pctOf(totals.totalOther),
                  ),
                ];
                // 极端 case:5 个都 0 → 显示空态(generic,所有 entries 都 0)
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
                  tween: Tween(begin: 0.0, end: appeared ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: AppMotion.aquaIn,
                  builder: (context, progress, _) {
                    return SizedBox(
                      height: 280,
                      child: AnimatedOpacity(
                        opacity: appeared ? 1.0 : 0.0,
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
                            // D64.38:百分比 label style(下行,小字灰)
                            percentStyle: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            primary: theme.colorScheme.primary,
                            primaryFill: theme.colorScheme.primary.withValues(alpha: 0.18),
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
    ),
    );
  }
}

/// 雷达图单维数据
///   - value:原始金额,用于 radius 归一化
///   - percent:占 5 段真资产 sum 的百分比(D64.38),用于 2 行 label 下行显示
class _RadarEntry {
  const _RadarEntry({
    required this.label,
    required this.value,
    required this.color,
    required this.percent,
  });
  final String label;
  final double value;
  final Color color;

  /// 占 5 段真资产 sum 的百分比(可能为负,反映"负贡献"段)
  final double percent;
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
    required this.percentStyle,
    required this.primary,
    required this.primaryFill,
  });

  final List<_RadarEntry> entries;
  final double maxValue;
  final double progress;
  final Color gridColor;
  final TextStyle labelStyle;
  // D64.38:百分比样式(下行 label,小字灰)
  final TextStyle percentStyle;
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
    //   D64.38:2 行布局 — 上行原 label(类型名),下行百分比 "75%"
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * angleStep;
      final labelR = radius * (1 + _labelOffset);
      final labelPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );
      _drawLabel(canvas, labelPos, entries[i], angle);
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
  ///
  /// D64.38:2 行布局 — 上行原 label(类型名 w600 11sp),下行 percent(百分比 w500 10sp 灰)
  ///   - 两个 TextPainter 分别 layout,组合高度 = labelH + percentH
  ///   - anchor 偏移仍按 angle 调整,但 dy 改为基于组合高度的一半
  ///   - 视觉上"流动资金 75%" 紧凑显示,label 占主,percent 副(D64.40 cash_flow 改"流动资金")
  void _drawLabel(
    Canvas canvas,
    Offset labelPos,
    _RadarEntry entry,
    double angle,
  ) {
    final percentText = '${entry.percent.round()}%';
    final labelTp = TextPainter(
      text: TextSpan(text: entry.label, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final percentTp = TextPainter(
      text: TextSpan(text: percentText, style: percentStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // 整体宽 = 两行宽的较大值(同行对齐用 max 宽,标签居中)
    final totalW = labelTp.width > percentTp.width
        ? labelTp.width
        : percentTp.width;
    // 整体高 = labelH + 2px gap + percentH
    final totalH = labelTp.height + 2 + percentTp.height;

    // 算 anchor 偏移(基于整体宽高,而非单行)
    double dx = 0, dy = 0;
    if (angle > -math.pi * 5 / 6 && angle < -math.pi / 6) {
      // 上方(顶部 60° 范围):anchor bottomCenter → label 在 pt 上方
      dy = -totalH / 2;
    } else if (angle > math.pi / 6 && angle < math.pi * 5 / 6) {
      // 下方(底部 60° 范围):anchor topCenter → label 在 pt 下方
      dy = totalH / 2;
    } else {
      dy = 0;
    }
    // 水平 anchor:右侧 spokes anchor 偏左,左侧 spokes anchor 偏右
    if (angle > -math.pi / 6 && angle < math.pi / 6) {
      // 右侧(0° 方向 ±30°)
      dx = totalW / 2;
    } else if (angle > math.pi * 5 / 6 || angle < -math.pi * 5 / 6) {
      // 左侧(180° 方向 ±30°)
      dx = -totalW / 2;
    } else {
      dx = 0;
    }

    // 整体左上角 = labelPos - 整体宽高/2 + (dx, dy)
    //   - dx/dy 是为了让组合 label 的"远端"沿 spoke 方向更远离端点
    final topLeft = Offset(
      labelPos.dx - totalW / 2 + dx,
      labelPos.dy - totalH / 2 + dy,
    );

    // 上行 label:水平居中于 topLeft + 0..totalW
    labelTp.paint(
      canvas,
      Offset(topLeft.dx + (totalW - labelTp.width) / 2, topLeft.dy),
    );
    // 下行 percent:水平居中,紧贴上行(gap 2px)
    percentTp.paint(
      canvas,
      Offset(
        topLeft.dx + (totalW - percentTp.width) / 2,
        topLeft.dy + labelTp.height + 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) {
    return old.maxValue != maxValue ||
        old.progress != progress ||
        old.gridColor != gridColor ||
        old.labelStyle != labelStyle ||
        old.percentStyle != percentStyle ||
        old.primary != primary ||
        old.entries != entries;
  }
}
