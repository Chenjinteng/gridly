// lib/core/widgets/animated_pie_chart.dart
// 圆环 / 仪表盘风格进度环 —— CustomPainter 自绘,扇区端圆角 + 间隙分隔。
//
// 2026-10-12 重写语义(第 8 版,commit 51):
//   - v7 commit 50:fill 路径 + 1.2° 间距,但 radial 切边还是直角的,
//     视觉上"边界太硬"(user 反馈)
//   - v8 (本版) 改 stroke + StrokeCap.round —— ColorOS 17 健康 App
//     步数环(同款 Apple Activity Ring 风)做法:
//       - 每扇区是一笔弧(stroke)+ 两端 semicircle cap(StrokeCap.round
//         自动加),形状像"药丸"
//       - 弧路径在两端各缩 capAngular + 1.2°,让相邻 sector cap 不接触,
//         留 ~2.4° 可见间隙
//       - 实色填充,无 alpha 渐变
//       - sweep 0°→360°,扇区按顺序填充
//
// 总时长 2400ms,8 个扇区每个有 ~300ms 完整"长出"过程。
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//     ],
//     innerRadius: 46,  // 中心洞半径
//     outerRadius: 64,  // 外圈半径
//   )
//
// 实现要点:
//   - AnimationController + addPostFrameCallback forward(首次 mount 启动)
//   - 每扇区 stroke 弧 + 两端圆角 cap(paint.strokeCap = round)
//   - 弧路径:从 sectorStart+paddingDeg 扫到 sectorEnd-paddingDeg,中间
//     长度 = sectorDeg - 2*paddingDeg 严格保证 caps 不出 boundary
//   - paddingDeg = capAngular + 1.2°,capAngular = asin((outer-inner)/2 / midRadius)
//     弧度化度数;result:相邻 sector 的 caps 各退 1.2°,看到的就是背景间隙
//   - 顺序出颜色:从 12 点 (-90°) 顺时针,ratio 控制 path length 增长
//   - key 变化触发 widget 重新 mount → 重画
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.innerRadius = 52,
    this.outerRadius = 64,
    this.startDegreeOffset = -90,
  });

  /// 数据扇区(value / color 用上,radius 字段保留为兼容性但不参与绘制)
  final List<PieChartSectionData> sections;

  /// 中心洞半径(中心文字显示区)
  final double innerRadius;

  /// 外圈半径
  final double outerRadius;

  /// 起始角(默认 -90° = 12 点钟方向,顺时针绕)
  final double startDegreeOffset;

  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  /// 总动画时长(commit 51 保持 2400ms):
  ///   8 个扇区每个 ~300ms,user 能清楚看到"扫到一个,出一个颜色"
  ///   的顺序。aquaIn 阻尼前快后慢,收尾自然减速。
  static const Duration _kDuration = Duration(milliseconds: 2400);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kDuration);
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    // 首次 mount:启动动画。postFrameCallback 让父级先 build 完成,
    // 避免在 switch transition 中断动画。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        return CustomPaint(
          painter: _GaugePainter(
            sweepProgress: _t.value,
            sections: widget.sections,
            innerRadius: widget.innerRadius,
            outerRadius: widget.outerRadius,
            startDegreeOffset: widget.startDegreeOffset,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// 自绘 stroke + 软化端 sector —— 解决"两色块衔接不自然"问题。
///
/// 之前 v8 用 StrokeCap.round 自动加 full semicircle cap,radius = ringThickness/2。
/// 用户反馈\"圆角太圆, 两个色块的衔接不自然\" —— 两个 full cap 接触像两颗药丸
/// 贴一起,颜色边界粗暴。
///
/// v9 (本版):
///   - StrokeCap.butt:端点是平面切,不是圆球,根本避免 pill cap 突起
///   - 手动画小圆点(soft cap)在两个路径端点上,radius = ringThickness/4,
///     比 pill cap 小一半,只起"软化切边"作用,不抢戏
///   - 弧路径从 sectorStart 到 sectorEnd(平端对接),对端小圆点软化
///   - 1.0° 可见间隙让相邻 sector 间有清晰背景分割,不再"两球贴一起"
class _GaugePainter extends CustomPainter {
  final double sweepProgress;
  final List<PieChartSectionData> sections;
  final double innerRadius;
  final double outerRadius;
  final double startDegreeOffset;

  _GaugePainter({
    required this.sweepProgress,
    required this.sections,
    required this.innerRadius,
    required this.outerRadius,
    required this.startDegreeOffset,
  });

  /// 扇区间的可见间隙(总 paddingDeg 的一部分)
  static const double _kClearanceDeg = 1.0;

  /// 端点软化小圆点半径相对环厚度的比例
  /// 0.25 = ringThickness/4,比 full cap(radius = ringThickness/2)小一半
  /// 看起来像"软切边"而不是"药丸"
  static const double _kSoftCapRatio = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径按 box 限制,防止 outer > maxOuter 越界
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);
    final middleRadius = (outer + inner) / 2;
    final ringThickness = outer - inner;
    final softCapRadius = ringThickness * _kSoftCapRatio;

    final total = sections.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return; // 空数据兜底:什么都不画

    final sweepDeg = sweepProgress * 360;
    var cumDeg = startDegreeOffset;

    for (final sec in sections) {
      final sectorDeg = sec.value / total * 360;
      final sectorStart = cumDeg;
      final sectorEnd = cumDeg + sectorDeg;

      final sweepRel = sweepDeg;

      double ratio;
      if (sweepRel <= sectorStart - startDegreeOffset) {
        ratio = 0;
      } else if (sweepRel >= sectorEnd - startDegreeOffset) {
        ratio = 1;
      } else {
        ratio = (sweepRel - (sectorStart - startDegreeOffset)) / sectorDeg;
      }

      if (ratio > 0) {
        // StrokeCap.butt + 小圆点 —— 根本避免 pill cap
        final stroke = Paint()
          ..color = sec.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringThickness
          ..strokeCap = StrokeCap.butt;

        // 弧路径从 sectorStart + clearanceDeg 到 sectorEnd - clearanceDeg
        // ratio 控制 path 实际长度,使 leading edge 跟 sweep position 走
        final drawStart = sectorStart + _kClearanceDeg;
        final maxDrawSweep = math.max(0.0, sectorDeg - 2 * _kClearanceDeg);
        final drawSweep = maxDrawSweep * ratio;

        if (drawSweep > 0) {
          final startRad = drawStart * math.pi / 180;
          final endRad = (drawStart + drawSweep) * math.pi / 180;

          // 1. 主弧(平端)
          final path = Path()
            ..addArc(
              Rect.fromCircle(center: center, radius: middleRadius),
              startRad,
              drawSweep * math.pi / 180,
            );
          canvas.drawPath(path, stroke);

          // 2. 两个端点小圆点(软化切边,不是 pill cap)
          // ratio < 1 时只画起点的 cap(leading edge 在 path 末端,不画)
          final capPaint = Paint()
            ..color = sec.color
            ..style = PaintingStyle.fill;

          // 起点 cap (trailing edge)
          canvas.drawCircle(
            Offset(
              center.dx + middleRadius * math.cos(startRad),
              center.dy + middleRadius * math.sin(startRad),
            ),
            softCapRadius,
            capPaint,
          );

          // 终点 cap (leading edge) —— 只在 ratio >= 1 时画
          if (ratio >= 1.0) {
            canvas.drawCircle(
              Offset(
                center.dx + middleRadius * math.cos(endRad),
                center.dy + middleRadius * math.sin(endRad),
              ),
              softCapRadius,
              capPaint,
            );
          }
        }
      }

      cumDeg += sectorDeg;
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.sweepProgress != sweepProgress ||
      old.sections != sections ||
      old.innerRadius != innerRadius ||
      old.outerRadius != outerRadius ||
      old.startDegreeOffset != startDegreeOffset;
}

/// 计算 sections 的内容 hash,用作 AnimatedPieChart 的 ValueKey。
/// sections 数据变化 → hash 变化 → widget 重新 mount → 重画。
Key pieChartKeyForSections(List<PieChartSectionData> sections) {
  final h = Object.hashAll(
      sections.map((s) => Object.hash(s.value, s.color)));
  return ValueKey('pie-$h');
}
