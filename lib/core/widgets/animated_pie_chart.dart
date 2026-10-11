// lib/core/widgets/animated_pie_chart.dart
// fl_chart PieChart 扇区入场包装 —— 圆环从 0° 到 360° 扫描展开,带 spring。
//
// 2026-10-12 重写为 ColorOS 风格:
//   之前用 `AnimationController.forward()` + 曲线 aquaIn 推进,1200ms,
//   用户反馈"动画太生硬了"。ColorOS 17 圆环入场的视觉语言是:
//     - spring 物理(stiffness 80 / damping 18,临界欠阻尼)
//     - 终点 progress 轻微 overshoot(到达 ~1.04)再回弹到 1.0
//     - 总时长 ~700ms(比 M3 的 300ms 长,有"重量感")
//   改 SpringSimulation 替代 Tween,让圆环从起点"画"到完整圆时有
//   惯性,符合 ColorOS Tactile Spring 语言。
//
// 算法(同 commit 27 但 spring 驱动)
//   progress 0→1(实际可到 ~1.04 再回弹)映射到 scannedDegrees = progress * 360
//   每个扇区按自己累计起角 / 终角决定:
//     - 扫描角未到 → value=0(fl_chart skip)
//     - 扫描角扫过 → value * partialProgress(部分显示)
//     - 扫描角扫完 → value = 原值
//
// 用法
//   AnimatedPieChart(
//     sections: [
//       PieChartSectionData(value: 100, color: Colors.red, radius: 18),
//     ],
//   )
//
// 实现:SpringSimulation + key 变化触发重新 mount
//   - 首次 mount:initState → addPostFrameCallback start spring
//   - 切月份 / 视角:父级传 key 变化 → widget 重新 mount → 重画
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class AnimatedPieChart extends StatefulWidget {
  const AnimatedPieChart({
    super.key,
    required this.sections,
    this.sectionsSpace = 2,
    this.centerSpaceRadius = 46,
    this.startDegreeOffset = -90,
  });

  /// 原始 sections(全部为最终目标 value)。运行时根据 progress 计算每个扇区
  /// 当前该显示的部分 value
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

  /// ColorOS 圆环 spring 物理参数(2026-10-12 调):
  /// - mass 1.0(标准)
  /// - stiffness 120(快+有惯性,~500ms 完成)
  /// - damping 20(略过临界 ~5% overshoot)
  ///
  /// 之前用 stiffness 80 + damping 18,临界阻尼 ≈ 17.9,damping 18 几乎无
  /// overshoot 但耗时 ~800ms,跟 AnimatedSwitcher 680ms 叠加导致"顿挫"。
  /// 改 stiffness 120 + damping 20 后:~500ms 完成 + 轻微 overshoot,
  /// 跟 AnimatedSwitcher fade in 节奏对齐,切换时不再"卡"。
  static const SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 120.0,
    damping: 20.0,
  );

  @override
  void initState() {
    super.initState();
    // unbounded:true 终点可以超过 1(spring overshoot),不会 clamp
    _ctrl = AnimationController.unbounded(vsync: this, value: 0);
    // 首次 mount:spring 从 0 到 1 + 自然 overshoot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ctrl.animateWith(SpringSimulation(
          _kSpring,
          0.0,   // start
          1.0,   // end
          0.0,   // 初始 velocity = 0
        ));
      }
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
      animation: _ctrl,
      builder: (context, _) {
        // 2026-10-12:用 raw _ctrl.value(0→1 + overshoot → 1),不用 Tween。
        // spring 真实曲线由 SpringSimulation 决定,build 时直接拿 _ctrl.value。
        final progress = _ctrl.value.clamp(0.0, 1.0);
        // scannedDegrees 0 → 360 度。spring overshoot 期间 progress 临时 > 1,
        // 但我们 clamp 到 [0, 1] 防止扇区越过 360 度导致"重叠"绘制。
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
            // 正在扫,按部分显示
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