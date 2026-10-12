// lib/core/widgets/animated_pie_chart.dart
// 圆环 / 仪表盘风格进度环 —— 全部用 CustomPainter 自绘,不用 fl_chart。
//
// 2026-10-12 重写语义(第 7 版,commit 50):
//   - v1-v5 全用 fl_chart,用户反馈"打开瞬间有底色 + 切换卡顿"
//   - v6 commit 49 改 CustomPainter 自绘 + Color.lerp(transparent → 实色):
//     没了底色,但 user 反馈\"过程中好像会有色差\"—— Color.lerp 在 ratio=0.5
//     时颜色半透明,在浅/深背景下被\"洗白\",看起来不像实色
//   - v7 (本版) 参考 ColorOS 17 健康 App 步数环(同款 Apple Activity Ring
//     风格) 的做法:
//       - 实色填充,**没有 alpha 渐变**——颜色从出现瞬间就是满色,彻底
//         解决色差问题
//       - 每扇区角度从 0 涨到 full,顺时针连贯扫,8 个扇区依次出现
//       - 扇区之间留 1.2° 小间隙,既方便肉眼区分段,又不喧宾夺主
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
//   - Sweep 从 startDegreeOffset(-90°=12 点)顺时针 0°→360°
//   - 每扇区累计角度 = cumDeg,sectorEnd = cumDeg + sectorDeg
//   - 距离 startDegreeOffset 的 sweep 位置:
//     - sweepRel < sectorStart  → ratio = 0(不画)
//     - sweepRel > sectorEnd    → ratio = 1(完整)
//     - 中间                    → ratio = (sweepRel - sectorStart) / sectorDeg
//   - 实色绘制:`sec.color` 直接给 paint.color,**没有 transparent 渐变**。
//     ratio 仅控制 angular extent(从 0 涨到 sectorDeg - _kGapDeg)
//   - 间隙:每扇区在 visual 上两侧各缩 0.6°,既可分辨边界又不破坏连贯感
//   - duration 2400ms,8 个扇区每个 ~300ms(剔除 1.2° 间隙后完整填充)
//   - key 变化触发 widget 重新 mount → 重画
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

  /// 总动画时长(commit 50,从 v6 2400ms 保持):
  ///   8 个扇区每个有 ~300ms 独立填充时间,user 能清楚看到"扫到一个,
  ///   出一个颜色"的先后顺序。aquaIn 阻尼前快后慢,收尾自然减速。
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

  /// 扇区之间留 1.2° 间隔(两侧各 0.6°)。
  /// ColorOS 17 健康 App 步数环同款 visual rhythm —— 扇区界限清晰,
  /// 但间隙小得刚好看到而不是被"切断"。
  static const double _kGapDeg = 1.2;
  static const double _kHalfGapDeg = _kGapDeg / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径按 box 限制,防止 outer > maxOuter 越界
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);

    final total = sections.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return; // 空数据兜底:什么都不画

    final sweepDeg = sweepProgress * 360;
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
        // 实色填充(不 fade)—— ColorOS 17 Health ring / Apple Activity 风格。
        // 一旦该扇区被扫到,瞬间就是满色,过程中无色差
        final paint = Paint()
          ..color = sec.color
          ..style = PaintingStyle.fill;

        // 绘制 visual extent = sectorDeg * ratio - gap,
        // 即使 sectorDeg 很小时 gap 上限也不让它变负
        final maxDrawSweep = math.max(0.0, sectorDeg - _kGapDeg);
        final drawSweep = maxDrawSweep * ratio;

        if (drawSweep > 0) {
          final path = buildAnnulusPath(
            center: center,
            outer: outer,
            inner: inner,
            startDeg: sectorStart + _kHalfGapDeg,
            sweepDeg: drawSweep,
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
