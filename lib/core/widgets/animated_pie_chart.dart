// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 圆环从 0° 到 360° "画"出来的扫描展开。
//
// 2026-10-12 重写语义:
//   之前用 `value * progress`(每个扇区按比例同时增长),用户反馈"想要
//   那种从 0 度到 360 度这样的展开"。新版本把整体进度 progress 映射到
//   扫描角度 scannedAngle = progress * 360,每个扇区根据自己累计
//   起角 / 终角,决定显示部分 / 未显示部分:
//     - 扫描角未到 → 扇区不显示(value=0,fl_chart skip)
//     - 扫描角扫过 → 扇区按部分比例(value * partialProgress)
//     - 扫描角扫完 → 扇区完全显示(value=原值)
//
// 视觉效果:圆环从 12 点钟(startDegreeOffset=-90)顺时针"画"到 360 度
// 完整圆,跟 ColorOS 17 锁屏时钟 morph 同款"扫描绘制"语言。
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//       PieChartSectionData(value: 50, color: Colors.blue, radius: 18),
//     ],
//   )
//
// 实现:AnimationController + key 变化触发重新 mount
//   - 首次 mount:initState → addPostFrameCallback forward
//   - 切月份 / 视角:父级传 key 变化 → widget 重新 mount → 重画
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.duration = const Duration(milliseconds: 1200),
    this.sectionsSpace = 2,
    this.centerSpaceRadius = 46,
    this.startDegreeOffset = -90,
  });

  /// 原始 sections(全部为最终目标 value)。运行时根据 progress 计算每个扇区
  /// 当前该显示的部分 value
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
    // 首次 mount:从 0° 开始画到 360°。postFrameCallback 让第一帧先 paint
    // progress=0(空圆环),然后 forward 平滑扫角展开
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
        // 整体扫描角度:0 → 360 度
        final scannedDegrees = progress * 360.0;

        // 计算每个扇区的累计起角 / 终角(基于最终 value 比例)
        final sumValues = widget.sections
            .fold<double>(0.0, (s, x) => s + x.value);
        if (sumValues <= 0) {
          // 全部 0,直接画空圆环
          return PieChart(
            PieChartData(
              sectionsSpace: widget.sectionsSpace,
              centerSpaceRadius: widget.centerSpaceRadius,
              startDegreeOffset: widget.startDegreeOffset,
              sections: const [],
            ),
          );
        }

        final animated = <PieChartSectionData>[];
        var cumulativeDegrees = 0.0;
        for (final s in widget.sections) {
          final sectorDegrees = (s.value / sumValues) * 360.0;
          final startDegrees = cumulativeDegrees;
          final endDegrees = cumulativeDegrees + sectorDegrees;
          double displayValue;
          if (scannedDegrees <= startDegrees) {
            // 扫描角未到此扇区,不显示
            displayValue = 0;
          } else if (scannedDegrees >= endDegrees) {
            // 扫描角已过,完全显示
            displayValue = s.value;
          } else {
            // 正在扫过,按比例
            final partialProgress =
                (scannedDegrees - startDegrees) / sectorDegrees;
            displayValue = s.value * partialProgress;
          }
          animated.add(PieChartSectionData(
            value: displayValue,
            color: s.color,
            title: s.title,
            radius: s.radius,
          ));
          cumulativeDegrees = endDegrees;
        }

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
Key pieChartKeyForSections(List<PieChartSectionData> sections) {
  final h = Object.hashAll(
      sections.map((s) => Object.hash(s.value, s.color)));
  return ValueKey('pie-$h');
}