// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 每个扇区从 0 长度"长"到目标长度。
//
// 2026-10-12 重写语义(第 4 版):
//   - v1: value * progress(每个扇区按比例同时增长)→ 用户反馈"生硬"
//   - v2: TweenAnimationBuilder 12s 扫描角 → 用户说"切换时卡一下直接切"
//   - v3: SpringSimulation 扫描角 + 启动延迟 → 用户反馈"不是扫角,
//        想要色条从无到有的展开"(本版)
//
// ColorOS 17 控制中心 wifi / 蓝牙圆环风格:
//   - 每个扇区独立从 0 角度"长"到目标角度(value * sectorProgress)
//   - 多个扇区按 stagger 依次开始(扇区 i 比 i-1 晚 60ms 启动)
//   - 总时长 ~900ms(aquaIn 阻尼曲线,前快后慢)
//
// 视觉效果:8 个分类色块依次"长"出来,前一个刚长到一半,下一个开始,
// 类似 ColorOS 17 控制中心圆环 morph 语言。
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
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

  /// 总动画时长(2026-10-12 调):配合 AnimatedSwitcher 1100ms fade,
  /// 让色条在 fade in 中后段长完(~80% 时已经画完)。1300ms 比 900ms 慢,
  /// 用户能清楚看到每个色条从 0 涨到目标的"蠕动"过程。
  /// 8 扇区总错峰:7 * 0.07 ≈ 490ms + 单扇区 0.6(780ms)= 1270ms,接近 1300ms。
  static const Duration _kDuration = Duration(milliseconds: 1300);

  /// 扇区之间错峰延迟(归一化 0~1,基于 _kDuration)
  /// 7 个间隔 × 0.07 ≈ 490ms,8 扇区错峰总时长
  static const double _kStaggerStep = 0.07;

  /// 单个扇区从 0 长到目标 value 用的归一化时长
  /// 0.6(780ms)比 0.5 更慢,色条"长出来"过程更明显
  static const double _kSectorDuration = 0.6;

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

        // 2026-10-12 改(色条从无到有展开):
        // 每个扇区独立 stagger grow,扇区 i 比 i-1 晚 _kStaggerStep 启动。
        // 每个扇区在 [startDelay, startDelay + _kSectorDuration] 区间内
        // sectorProgress 从 0 涨到 1,value = s.value * sectorProgress。
        // 总时长:_kStaggerStep * (n-1) + _kSectorDuration,8 扇区 ~1.0。
        final animated = <PieChartSectionData>[];
        for (var i = 0; i < widget.sections.length; i++) {
          final s = widget.sections[i];
          final startDelay = i * _kStaggerStep;
          final sectorProgress =
              ((t - startDelay) / _kSectorDuration).clamp(0.0, 1.0);
          animated.add(PieChartSectionData(
            value: s.value * sectorProgress,
            color: s.color,
            title: s.title,
            radius: s.radius,
          ));
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