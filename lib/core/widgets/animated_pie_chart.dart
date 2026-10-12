// lib/core/widgets/animated_pie_chart.dart
// 圆环 / 仪表盘风格进度环 —— 全部用 CustomPainter 自绘,不用 fl_chart。
//
// 2026-10-12 重写语义(第 6 版,commit 49):
//   - 之前 v1-v5 都用 fl_chart 的 PieChart,无论 value=0 时,fl_chart 都会
//     渲染一条隐形 ring outline / track,导致打开页面瞬间看到"底色"
//     (灰圈)再出色条 — user 反复反馈,不是干净的 gauge 体验
//   - v6 (本版):完全自绘,CustomPainter + 手绘 partial annulus path。
//     sweep progress = 0 时**什么也不画**(没底色、没 outline、没 swap
//     animation),sweep 经过扇区时该段才"长"出来,色从透明渐变到实色。
//     像 Apple Activity ring / ColorOS 17 控制中心 wifi/蓝牙圆环效果。
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
//   - Cumulative sweep angle,从 startDegreeOffset(-90°=12 点)顺时针绕
//     - 总 sweep = 0°→360°
//     - 每个扇区按累计角度位置分段:`start = cumDeg`,`end = cumDeg + sectorDeg`
//     - sweep < start → 完全不画;start ≤ sweep ≤ end → 画 partial 弧 + 颜色 fade in;
//       sweep > end → 完整扇区 + 完整颜色
//   - duration 2400ms,8 个扇区每个 ~300ms,fade in 过程清晰可见
//   - key 变化触发 widget 重新 mount → 重画(切月份 / 视角由父级 key 控制)
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.innerRadius = 46,
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

  /// 总动画时长(commit 49,从 2000ms 拉到 2400ms):
  ///   2400ms 让 8 个扇区每个有 ~300ms 独立 fade-in 时间,user 能清楚看到
  ///   "扫到一个,出一个颜色" 的先后顺序。aquaIn 阻尼前快后慢,收尾自然减速。
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

/// 自绘 partial annulus path — 给定中心 / 外圈半径 / 内圈半径 / 起始角 /
/// 扫过角度,返回一个闭合 donut slice 路径。clockwise 顺时针方向。
Path buildAnnulusPath({
  required Offset center,
  required double outer,
  required double inner,
  required double startDeg,
  required double sweepDeg,
}) {
  final outerRect = Rect.fromCircle(center: center, radius: outer);
  final innerRect = Rect.fromCircle(center: center, radius: inner);
  final startRad = startDeg * math.pi / 180;
  final sweepRad = sweepDeg * math.pi / 180;
  final endRad = startRad + sweepRad;

  final startOuter = Offset(
    center.dx + outer * math.cos(startRad),
    center.dy + outer * math.sin(startRad),
  );
  final endInner = Offset(
    center.dx + inner * math.cos(endRad),
    center.dy + inner * math.sin(endRad),
  );

  final path = Path()..moveTo(startOuter.dx, startOuter.dy);
  // 外圈顺时针弧
  path.arcTo(outerRect, startRad, sweepRad, false);
  // 连线到内圈终点
  path.lineTo(endInner.dx, endInner.dy);
  // 内圈逆时针弧回起点
  path.arcTo(innerRect, endRad, -sweepRad, false);
  path.close();
  return path;
}

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

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径按 box 限制,防止 outer > maxOuter 越界
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);

    final total = sections.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return; // 空数据兜底:什么都不画

    // sweep progress 0..1 → 0°..360° 顺时针
    final sweepDeg = sweepProgress * 360;
    // cumDeg 累加扇区累角度,起点 = startDegreeOffset (-90° = 12 点)
    var cumDeg = startDegreeOffset;

    for (final sec in sections) {
      final sectorDeg = sec.value / total * 360;
      final sectorStart = cumDeg;
      final sectorEnd = cumDeg + sectorDeg;

      // 距离 startDegreeOffset 的相对 sweep 位置
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
        // 颜色 fade-in:从 transparent 渐变到实色
        final color = Color.lerp(
          Colors.transparent,
          sec.color,
          ratio.clamp(0.0, 1.0).toDouble(),
        )!;
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        // 自绘 partial annulus path —— 没底色、没 outline、没 swap 残留
        final path = buildAnnulusPath(
          center: center,
          outer: outer,
          inner: inner,
          startDeg: sectorStart,
          sweepDeg: sectorDeg * ratio,
        );
        canvas.drawPath(path, paint);
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
