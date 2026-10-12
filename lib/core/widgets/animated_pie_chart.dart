// lib/core/widgets/animated_pie_chart.dart
// 圆环 / 仪表盘风格进度环 —— CustomPainter 自绘,**无圆角**平切端。
//
// 2026-10-12 重写语义(第 10 版,commit 54):
//   v6 commit 49:fill partial annulus,扫角从 0° → 360°,实色无色差
//   v7 commit 50:实色 + 1.2° 间隙,user 反馈"色差+边界太硬"
//   v8 commit 51:stroke + StrokeCap.round,圆角端(Apple Activity 风)
//   v9 commit 52:缩环厚度 18 → 12 让 caps 小一点,user 还是嫌"太圆"
//   v10 commit 53:StrokeCap.butt + 路径端点小圆点软化,user 反馈"太奇怪"
//   v11 (本版):撤掉所有"圆角/软化"做法 ——
//     - 完全平端切(StrokeCap.butt),没有 pill cap,没有小圆点
//     - 1.0° 可见间隙让相邻 sector 之间有清晰背景分割
//     - 环厚度从 12 加宽到 14(user 反馈"线条再宽一点点")
//
// 动画逻辑保留:
//   sweep 0° → 360° 顺时针扫(累计角度推进)
//   实色填充,无 alpha 渐变
//   duration 2400ms,8 个扇区每个 ~300ms 独立填充时间
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//     ],
//     innerRadius: 50,  // 中心洞半径(环厚度 = outerRadius - innerRadius)
//     outerRadius: 64,
//   )
//
// 实现要点:
//   - AnimationController + addPostFrameCallback forward(首次 mount 启动)
//   - 每扇区路径从 sectorStart + clearanceDeg 到 sectorEnd - clearanceDeg
//   - ratio 控制 path 实际长度,使 leading edge 跟 sweep position 走
//   - key 变化触发 widget 重新 mount → 重画
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.innerRadius = 50,
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

  /// 总动画时长(commit 54 保持 2400ms):
  ///   8 个扇区每个 ~300ms 独立填充时间,user 能清楚看到"扫到一个,
  ///   出一个颜色"的顺序。aquaIn 阻尼前快后慢,收尾自然减速。
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

/// 自绘 stroke 平切端 sector —— 不做任何圆角处理。
///
/// commit 54 撤掉 v10 的手动小圆点软化(看起来奇怪)。现在只剩:
///   - stroke 弧(StrokeCap.butt 平端切)
///   - 1.0° 可见间隙让相邻 sector 之间背景透出
///   - 完全没有 pill cap、没有 endpoint dot,只是干净的 sector 切片
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

  /// 扇区间的可见间隙(commit 54 保持 1.0°)
  static const double _kClearanceDeg = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 半径按 box 限制,防止 outer > maxOuter 越界
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);
    final middleRadius = (outer + inner) / 2;
    final ringThickness = outer - inner;

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
        // Stroke 平端(StrokeCap.butt)—— 无圆角、无小圆点
        final stroke = Paint()
          ..color = sec.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringThickness
          ..strokeCap = StrokeCap.butt;

        // 弧路径从 sectorStart + clearanceDeg 到 sectorEnd - clearanceDeg
        // 留 clearanceDeg 让相邻 sector 间有 ~2° 背景可见缝
        final drawStart = sectorStart + _kClearanceDeg;
        final maxDrawSweep = math.max(0.0, sectorDeg - 2 * _kClearanceDeg);
        final drawSweep = maxDrawSweep * ratio;

        if (drawSweep > 0) {
          final path = Path()
            ..addArc(
              Rect.fromCircle(center: center, radius: middleRadius),
              drawStart * math.pi / 180,
              drawSweep * math.pi / 180,
            );
          canvas.drawPath(path, stroke);
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
