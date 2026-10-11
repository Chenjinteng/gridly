// lib/core/widgets/staggered_fade_in.dart
// 列表/容器错峰 fade-in 包裹 —— 首次入场时按 index 30ms 错峰 fade + 上推 8px,
// 360ms aquaIn 完成。后续数据变化 / 滚动新 item 不重放(由父级 enabled 控制)。
//
// ColorOS Luminous Rendering 风格:渐进出现,前一项还在淡入,后一项已经半透明
// 起步,而不是一次性全显示。整体感觉"在生长"而非"突然出现"。
//
// 用法
//   ListView(children: items.asMap().entries.map((e) =>
//     StaggeredFadeIn(index: e.key, enabled: !_appeared, child: e.value),
//   ).toList())
//
// 父级状态
//   - _appeared = false → 首次 mount,所有 StaggeredFadeIn 触发 stagger 动画
//   - _appeared = true  → 后续 build,enabled=false,直接显示,零开销
//
// 性能
//   - 每个 enabled=true 的 widget 持有独立 AnimationController(360ms 一次性)
//   - 完成后 dispose,不会持续占资源
//   - enabled=false 时直接 return child,跳过 AnimatedBuilder,零开销
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({
    super.key,
    required this.index,
    required this.enabled,
    required this.child,
  });

  /// 在同级列表里的位置(0, 1, 2, ...)。index * 30ms 是入场延迟
  final int index;

  /// true:触发 stagger fade-in(父级首次 mount 时)
  /// false:直接显示(后续 rebuild / filter 切换 / 滚动新 item)
  final bool enabled;

  final Widget child;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      value: 0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);

    if (widget.enabled) {
      // 真 stagger:index * 30ms 延迟后再 forward
      Future.delayed(Duration(milliseconds: widget.index * 30), () {
        if (mounted) _ctrl.forward();
      });
    } else {
      // 已 appeared:立刻跳到 1(完全显示),不再动画
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && _ctrl.value == 1.0) {
      // 已 displayed:跳过 AnimatedBuilder,零开销
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        return Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _t.value) * 8),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}