// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 自带扇区从 0 角度展开到目标值的动画。
//
// 背景
//   fl_chart 0.69.2 的 PieChartData 没有 swapAnimationDuration 参数
//   (高版本才有),我们用 TweenAnimationBuilder 控制 sections value 的
//   "乘数 progress",从 0 走到 1,实现扇区展开效果。
//
// ColorOS 风
//   - 时长 800ms(比 M3 默认 300ms 长,有"重量感")
//   - 曲线 aquaIn(非线性阻尼,前快后慢)
//   - 首次 mount 时 progress 从 0 走到 1;后续 sections 数据变化,didUpdateWidget
//     会用新 progress=0 起步再 forward(让扇区重新展开),所以切月份 / 视角时
//     扇区也会"重新画"一次
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//       PieChartSectionData(value: 50, color: Colors.blue, radius: 18),
//     ],
//   )
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.duration = const Duration(milliseconds: 800),
    this.sectionsSpace = 2,
    this.centerSpaceRadius = 46,
    this.startDegreeOffset = -90,
  });

  /// 原始 sections(全部为最终目标 value)。包装后 value 会乘以 progress(0→1)
  final List<PieChartSectionData> sections;
  final Duration duration;
  final double sectionsSpace;
  final double centerSpaceRadius;
  final double startDegreeOffset;

  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart> {
  /// TweenAnimationBuilder 没有"按 this"的等价物,但 key 变化会让 widget
  /// 重建,新的 TweenAnimationBuilder 内部 tween 重新从 begin 起步。
  /// 用 sections 的内容哈希做 key(简化:用长度 + 第一个 value),data 变化时
  /// 触发"重新画"。
  Key _keyForSections(List<PieChartSectionData> ss) {
    final h = Object.hashAll(ss.map((s) => Object.hash(s.value, s.color)));
    return ValueKey('pie-$h');
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // 2026-10-12 用 TweenAnimationBuilder 替代 Controller + CurvedAnimation,
      // 因为 fl_chart 0.69.2 对 sections value 微小变化的渲染更新较敏感,
      // 直接用 builder-driven progress 更可靠。
      key: _keyForSections(widget.sections),
      tween: Tween<double>(begin: 0, end: 1),
      duration: widget.duration,
      curve: AppMotion.aquaIn,
      builder: (context, progress, _) {
        // progress 0→1:sections 的 value 按比例展开
        // value=0 时 fl_chart 会跳过该 section,配合 progress 从 0 起步,
        // 扇区从"无"展开到"全部"
        final animated = widget.sections
            .map((s) => PieChartSectionData(
                  value: s.value * progress,
                  color: s.color,
                  title: s.title,
                  radius: s.radius,
                ))
            .toList();
        return PieChart(
          PieChartData(
            sectionsSpace: widget.sectionsSpace,
            centerSpaceRadius: widget.centerSpaceRadius,
            startDegreeOffset: widget.startDegreeOffset,
            sections: animated,
          ),
        );
      },
    );
  }
}