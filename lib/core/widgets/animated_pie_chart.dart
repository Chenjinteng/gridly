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
    this.innerRadius = 48,
    this.outerRadius = 64,
    this.startDegreeOffset = -90,
    this.play = true,
  });

  /// 数据扇区(value / color 用上,radius 字段保留为兼容性但不参与绘制)
  final List<PieChartSectionData> sections;

  /// 中心洞半径(中心文字显示区)
  final double innerRadius;

  /// 外圈半径
  final double outerRadius;

  /// 起始角(默认 -90° = 12 点钟方向,顺时针绕)
  final double startDegreeOffset;

  /// 2026-10-15 D63.1 加:viewport-aware 触发
  ///   - 默认 true(向后兼容,initState 后立即 forward)
  ///   - false 时 widget mount 但不 forward;parent 通过 setState 改为 true
  ///     时由 didUpdateWidget 触发 forward(用于 viewport-aware 触发场景)
  ///   跟 AnimatedOverBudgetChart.play 同款设计
  final bool play;

  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  /// 总动画时长(commit 57 再加快:1800ms → 1200ms)
  ///   user 反馈"再快一点,到 1200 试试"
  ///   8 个扇区每个 ~150ms 填充,aquaIn 阻尼前快后慢保留
  static const Duration _kDuration = Duration(milliseconds: 1200);

  /// 2026-10-15 D63.1 加:防止 _play 被重复调用
  bool _appeared = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kDuration);
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    // play=true 时首次 mount 启动;play=false 时等 didUpdateWidget 触发。
    if (widget.play) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedPieChart old) {
    super.didUpdateWidget(old);
    // play 由 false 变 true → 触发 forward(viewport-aware 场景)
    if (widget.play && !_appeared) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  /// 一次性 forward,触发后不再重播
  void _play() {
    if (_appeared) return;
    _appeared = true;
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Shadow 配色:dark mode 下用白色微透(给环勾出暗背景下的立体感),
    // light mode 用黑色微透(经典 drop shadow)。透给 _GaugePainter 让
    // sector 之前先画一整圈 blur。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.22);
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
            shadowColor: shadowColor,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// 自绘 stroke 平切端 sector + 整圈投影 —— 给环加一点立体感。
///
/// commit 58 (本版) 在 sector 之前先画一整圈 blur 微下移 shadow,
/// 然后每个 sector 覆盖在上面。视觉上看 sectors 之下有一圈淡淡的
/// 投影,像"环悬浮在卡片上"。sector 间隙(1.0°)允许 shadow 透出来,
/// 显出环轮廓但不让 sectors 之间糊。
///
///   - shadow:MaskFilter.blur sigma=3.5 + 下移 1.5px,半透明黑/白
///     (dark mode 用白,light mode 用黑)给一点 3D 立体感
///   - sectors:stroke + StrokeCap.butt 平端切,无圆角
///   - 1.0° 可见间隙让相邻 sector 之间背景透出
class _GaugePainter extends CustomPainter {
  final double sweepProgress;
  final List<PieChartSectionData> sections;
  final double innerRadius;
  final double outerRadius;
  final double startDegreeOffset;
  final Color shadowColor;

  _GaugePainter({
    required this.sweepProgress,
    required this.sections,
    required this.innerRadius,
    required this.outerRadius,
    required this.startDegreeOffset,
    required this.shadowColor,
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

    // Shadow paint 提到循环外:不依赖 sector 颜色,只跟 ring / shadow 有关。
    // 每个 sector 走自己的"先画自身 drawn 部分的 shadow,再画 stroke"流程,
    // 这样 sweep = 0 时 shadow 完全不存在,sweep 推进时 shadow 跟着 sector 一起出。
    final shadowPaint = Paint()
      ..color = shadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5);

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

          // 1. 阴影(每个 sector 自己带 —— 只画 drawn 部分,跟 sweep 走)
          //   commit 60 修复:之前整圈一次性画 shadow 在 sectors 之下,
          //   sweep = 0 时已经有完整阴影显示。现在按 sector 拆开,sweep = 0
          //   时啥都没有,sweep 推进时阴影跟着 sector 一起出现
          canvas.save();
          canvas.translate(0, 1.5);
          canvas.drawPath(path, shadowPaint);
          canvas.restore();

          // 2. 主弧(stroke 平端)—— 在自身 shadow 之上
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
  final h = Object.hashAll(sections.map((s) => Object.hash(s.value, s.color)));
  return ValueKey('pie-$h');
}

/// 2026-10-12 commit 100 加:支持 multi-turn 的圆环动画(过预算场景)
///
/// 跟 [AnimatedPieChart] 的区别:
///   - AnimatedPieChart 假设 sections 之和 = 1(单圈),`sweepDeg = 0..360°`
///   - 本 widget 允许 sections 之和 > 1(过预算转多圈),
///     `sweepDeg = 0..360° × totalTurns`
///
///   用法(预算圆环):
///     已花 ¥10000 → 占 1.0 圈(value = 1.0)
///     超额 ¥96015 → 占 9.6 圈(value = 9.6)
///     圆环从 0° 顺时针转:第 1 圈走已花,之后继续走超额,直到转完 10.6 圈
///
/// 实现沿用 _GaugePainter 思路,只是 sweepDeg 公式不同;
/// 为避免影响 AnimatedPieChart 的 shouldRepaint 行为,painter 单独写。
class AnimatedOverBudgetChart extends StatefulWidget {
  const AnimatedOverBudgetChart({
    super.key,
    required this.sections,
    this.innerRadius = 48,
    this.outerRadius = 64,
    this.startDegreeOffset = -90,
    this.play = true,
  });

  /// 数据扇区。**value 是"圈数"** — 例如 1.0 = 1 圈(360°),0.86 = 309.6°
  final List<PieChartSectionData> sections;
  final double innerRadius;
  final double outerRadius;
  final double startDegreeOffset;

  /// commit 102 加:是否启动扫角动画。
  ///   - 默认 true(向后兼容,initState 后立即 forward)
  ///   - false 时 widget mount 但不 forward;parent 通过 setState 改为 true
  ///     时由 didUpdateWidget 触发 forward(用于 viewport-aware 触发场景)
  final bool play;

  @override
  State<AnimatedOverBudgetChart> createState() =>
      _AnimatedOverBudgetChartState();
}

class _AnimatedOverBudgetChartState extends State<AnimatedOverBudgetChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  static const Duration _kBaseDuration = Duration(milliseconds: 2000);

  /// 每多 1 圈 +300ms,最多加成 5 圈(封顶 3500ms 防止太长)
  /// commit 102 改:user 反馈 1200ms 太短 + 200ms/圈太短,看起来"唰一下"就转完。
  ///   现在基础 2000ms + 300ms/圈,9 圈预算约 4100ms,跟"转多圈"的视觉重量匹配
  static const double _kExtraPerTurnMs = 300;
  static const double _kExtraMaxTurns = 5;

  /// commit 102 加:防止 _play 被重复调用
  bool _appeared = false;

  @override
  void initState() {
    super.initState();
    final totalTurns = _totalTurns();
    final extraTurns = (totalTurns - 1).clamp(0.0, _kExtraMaxTurns);
    final ms =
        _kBaseDuration.inMilliseconds + (extraTurns * _kExtraPerTurnMs).round();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    // commit 102 改:play=true 时 initState 后立即 forward;
    //   play=false 时由 parent 触发(didUpdateWidget 调 _play)
    if (widget.play) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedOverBudgetChart old) {
    super.didUpdateWidget(old);
    // play 由 false 变 true → 触发 forward(viewport-aware 场景)
    if (widget.play && !_appeared) {
      _play();
    }
  }

  /// 一次性 forward,触发后不再重播
  void _play() {
    if (_appeared) return;
    _appeared = true;
    _ctrl.forward();
  }

  double _totalTurns() =>
      widget.sections.fold<double>(0.0, (s, e) => s + e.value);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.22);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        return CustomPaint(
          painter: _OverBudgetGaugePainter(
            sweepProgress: _t.value,
            sections: widget.sections,
            innerRadius: widget.innerRadius,
            outerRadius: widget.outerRadius,
            startDegreeOffset: widget.startDegreeOffset,
            shadowColor: shadowColor,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// 多圈版本的 _GaugePainter。
///   关键差异:`sweepDeg = sweepProgress * 360 * totalTurns`,
///   sectorDeg 直接 = sec.value * 360(因为 sec.value 已经是"圈数")。
class _OverBudgetGaugePainter extends CustomPainter {
  final double sweepProgress;
  final List<PieChartSectionData> sections;
  final double innerRadius;
  final double outerRadius;
  final double startDegreeOffset;
  final Color shadowColor;

  _OverBudgetGaugePainter({
    required this.sweepProgress,
    required this.sections,
    required this.innerRadius,
    required this.outerRadius,
    required this.startDegreeOffset,
    required this.shadowColor,
  });

  static const double _kClearanceDeg = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxOuter = math.min(size.width, size.height) / 2;
    final outer = math.min(outerRadius, maxOuter);
    final inner = math.min(innerRadius, outer - 4);
    final middleRadius = (outer + inner) / 2;
    final ringThickness = outer - inner;

    final totalTurns = sections.fold<double>(0.0, (s, e) => s + e.value);
    if (totalTurns <= 0) return;

    // progress 0 → 1 → 扫过 totalTurns 圈
    final sweepDeg = sweepProgress * 360 * totalTurns;
    var cumDeg = startDegreeOffset;

    final shadowPaint = Paint()
      ..color = shadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5);

    for (final sec in sections) {
      // sectorDeg 直接由 value(圈数)算出,不再除以 total
      final sectorDeg = sec.value * 360;
      final sectorStart = cumDeg;
      final sectorEnd = cumDeg + sectorDeg;

      double ratio;
      if (sweepDeg <= sectorStart - startDegreeOffset) {
        ratio = 0;
      } else if (sweepDeg >= sectorEnd - startDegreeOffset) {
        ratio = 1;
      } else {
        final denom = (sectorEnd - sectorStart).abs();
        ratio = denom < 1e-6
            ? 1.0
            : (sweepDeg - (sectorStart - startDegreeOffset)) / sectorDeg;
      }

      if (ratio > 0) {
        final stroke = Paint()
          ..color = sec.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringThickness
          ..strokeCap = StrokeCap.butt;

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

          canvas.save();
          canvas.translate(0, 1.5);
          canvas.drawPath(path, shadowPaint);
          canvas.restore();

          canvas.drawPath(path, stroke);
        }
      }

      cumDeg += sectorDeg;
    }
  }

  @override
  bool shouldRepaint(_OverBudgetGaugePainter old) =>
      old.sweepProgress != sweepProgress ||
      old.sections != sections ||
      old.innerRadius != innerRadius ||
      old.outerRadius != outerRadius ||
      old.startDegreeOffset != startDegreeOffset;
}
