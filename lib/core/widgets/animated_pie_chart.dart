// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 整个圆环顺时针扫角 + 颜色 fade in。
//
// 2026-10-12 重写语义(第 5 版,commit 48):
//   - v1: value * progress(每扇区按比例同时增长)→ 用户反馈"生硬"
//   - v2: TweenAnimationBuilder 12s 扫描角 → 用户说"切换时卡一下直接切"
//   - v3: SpringSimulation 扫描角 + 启动延迟 → 用户反馈"不是扫角,
//        想要色条从无到有的展开"
//   - v4: 每扇区独立 stagger grow → 用户反馈"还是没看到从 0 到 360
//        的 sweep 过程,太快了"(色块分别长,不是连贯扫角)
//   - v5 (本版):单 sweep,累计角度追踪,扇区按累计角度比 vs sweep 比例
//        显示,被扫到的扇区 value 0→full + 颜色透明→实色。
//        视觉上是连续顺时针扫过去,ColorOS 17 控制中心 wifi/蓝牙圆环
//        + Apple Activity ring 风格的"充能"动画。
//
// 总时长 2000ms(aquaIn 阻尼,前快后慢),让用户清楚看到 0°→360° 全过程。
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//     ],
//   )
//
// 实现要点:
//   - AnimationController + addPostFrameCallback forward(首次 mount 启动)
//   - key 变化触发 widget 重新 mount → 重画(切月份 / 视角由父级 key 控制)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.sectionsSpace = 2,
    this.centerSpaceRadius = 46,
    this.startDegreeOffset = -90,
  });

  /// 原始 sections(全部为最终目标 value)
  final List<PieChartSectionData> sections;
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

  /// 总动画时长(commit 48,user 反馈"还是太快"):
  ///   2000ms,ColorOS 17 控制中心圆环 sweep 同级。1300ms 看不清 0°→360°
  ///   整个过程,2000ms 慢到用户能从 12 点位置顺时针绕一圈回到 12 点。
  /// 配合 aquaIn 阻尼曲线(前快后慢),收尾自然减速。
  static const Duration _kDuration = Duration(milliseconds: 2000);

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
        final t = _t.value;

        // 累计角度 sweep —— 跟 v4 不同,这里用"单一 sweep 角 0°→360°",
        // 每个扇区根据自己所在的累计角度位置决定显示比例:
        //   - sweep ≤ start:扇区完全没被扫到(value=0,color=transparent)
        //   - sweep ≥ end:扇区已扫完(value=full,color=full)
        //   - 在 start~end 之间:value * (sweep-start)/sectorDeg,color 按
        //     ratio 在 transparent ↔ 实色之间插值
        // 整体视觉是扇区按 cumulativeAngle 顺序逐个被"扫过去"展开。
        final total = widget.sections
            .fold<double>(0, (sum, s) => sum + s.value);

        if (total <= 0) {
          // 防御:空数据时直接原样画 PieChart,避免除以 0
          return PieChart(PieChartData(
            sectionsSpace: widget.sectionsSpace,
            centerSpaceRadius: widget.centerSpaceRadius,
            startDegreeOffset: widget.startDegreeOffset,
            sections: widget.sections,
          ));
        }

        final sweepDeg = t * 360;
        var cumDeg = 0.0;
        final animated = <PieChartSectionData>[];
        for (final s in widget.sections) {
          final sectorDeg = s.value / total * 360;
          final start = cumDeg;
          final end = cumDeg + sectorDeg;

          final double ratio;
          if (sweepDeg <= start) {
            ratio = 0;
          } else if (sweepDeg >= end) {
            ratio = 1;
          } else {
            ratio = (sweepDeg - start) / sectorDeg;
          }

          animated.add(PieChartSectionData(
            value: s.value * ratio,
            color: Color.lerp(Colors.transparent, s.color, ratio)!,
            title: s.title,
            radius: s.radius,
          ));
          cumDeg += sectorDeg;
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
