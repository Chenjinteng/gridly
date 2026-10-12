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

/// 自绘 stroke 圆角端 sector —— Apple Activity ring 风。
///
/// 每扇区是 stroke + rounded cap:
///   - 弧路径从 sectorStart + paddingDeg 划到 sectorEnd - paddingDeg
///   - paddingDeg = capAngular + 1.2°,保证:
///     - 两端 StrokeCap.round 自动加 cap,cap 圆心在路径端点
///     - cap 半径 = (outer - inner) / 2;cap angular 范围 ≈ capRadius / midRadius
///     - 缩小路径让 caps 完全在自己 sector 范围内,不延伸进相邻 sector
///     - 1.2° 多留隙让 background 在 cap-cap 之间可见 ~2.4°
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

  /// 扇区间的可见间隙(paddingDeg 的一部分)。
  /// 0.8° 是 v8 commit 51 的 1.2° 减下来 —— user 反馈"圆角端太圆",
  /// 改薄环厚度从 18 → 12(内圈 46 → 52)的同时把可见间距也收紧一点,
  /// 让 caps 不会过分突出
  static const double _kClearanceDeg = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径按 box 限制,防止 outer > maxOuter 越界
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);
    final middleRadius = (outer + inner) / 2;
    final ringThickness = outer - inner;
    final capRadius = ringThickness / 2;

    // cap Angular 范围(弧度→度):cap 是 circle,边界在 middleRadius 处
    // 切线方向最远 +asin(capRadius / middleRadius) 度
    final capAngularDeg = math.asin(capRadius / middleRadius) * 180 / math.pi;
    final paddingDeg = capAngularDeg + _kClearanceDeg;

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
        // Stroke 圆角端(ColorOS 17 Health / Apple Activity 风)
        final paint = Paint()
          ..color = sec.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringThickness
          ..strokeCap = StrokeCap.round;

        // 弧路径从 sectorStart + paddingDeg 到 sectorEnd - paddingDeg
        // ratio 控制 path 实际长度,使 leading edge 跟 sweep position 走
        final drawStart = sectorStart + paddingDeg;
        final maxDrawSweep = math.max(0.0, sectorDeg - 2 * paddingDeg);
        final drawSweep = maxDrawSweep * ratio;

        if (drawSweep > 0) {
          final path = Path()
            ..addArc(
              Rect.fromCircle(center: center, radius: middleRadius),
              drawStart * math.pi / 180,
              drawSweep * math.pi / 180,
            );
          canvas.drawPath(path, paint);
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
