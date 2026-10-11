// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 自带扇区从 0 角度展开到目标值的动画。
//
// 背景
//   fl_chart 0.69.2 的 PieChartData 没有 swapAnimationDuration 参数
//   (高版本才有),我们用 AnimationController 控制 sections value 的
//   "乘数 progress",从 0 走到 1,实现扇区展开效果。
//
// ColorOS 风
//   - 时长 800ms(比 M3 默认 300ms 长,有"重量感")
//   - 曲线 aquaIn(非线性阻尼,前快后慢)
//   - 首次 mount 时 progress 从 0 走到 1;后续 sections 数据变化由父级触发
//     (目前通过 widget key 重 mount 实现)
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//       PieChartSectionData(value: 50, color: Colors.blue, radius: 18),
//     ],
//   )
//
// 实现
//   StatefulWidget + AnimationController,initState 用 addPostFrameCallback
//   forward。父级切月份 / 视角时,使用 ValueKey(基于 sections 内容的 hash),
//   sections 数据变化 → key 变化 → widget 重新 mount → 重新 forward →
//   扇区再次展开。
//
// 2026-10-12 fix:之前用 TweenAnimationBuilder,在外层 StaggeredFadeIn 包裹下,
// 外层 stagger 360ms 内 tap 时内层 TweenAnimationBuilder 已走完 800ms,
// 用户看不到扇区展开。换回 AnimationController + initState forward,
// 通过 key 变化触发重新 mount 重画(数据变化时)。
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

class _AnimatedPieChartState extends State<AnimatedPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    // 首次 mount:扇区从 0 展开到目标。postFrameCallback 让第一帧先 paint progress=0,
    // 然后 forward 平滑展开。
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
        final progress = _t.value;
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

/// 计算 sections 的内容 hash,用作 AnimatedPieChart 的 ValueKey。
/// sections 数据变化 → hash 变化 → widget 重新 mount → 扇区重新展开。
/// 但只在父级有需要时调用(比如 StatsPage 切月份 / 视角时)。
Key pieChartKeyForSections(List<PieChartSectionData> sections) {
  final h = Object.hashAll(
      sections.map((s) => Object.hash(s.value, s.color)));
  return ValueKey('pie-$h');
}