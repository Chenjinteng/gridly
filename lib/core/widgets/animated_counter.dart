// lib/core/widgets/animated_counter.dart
// 数字 count-up 滚动 widget —— 数字从当前值平滑过渡到目标值。
//
// ColorOS 风数字组件(Calculator / 钱包 / 报表汇总)的标志性入场:
// 数字变化时从旧值滚动到新值,有"重量感",而不是"啪"地一下换掉。
//
// 用法
//   AnimatedCounter(value: 16540.32, prefix: '¥')
//   AnimatedCounter(value: balance, formatter: (v) => Formatters.amount(v))
//
// 行为
//   - 首次 build:value 自身从 0 滚动到位(target 由 widget.value 决定,360ms)
//   - didUpdateWidget:值变化时,从旧值滚动到新值(支持数据更新时的滚动)
//   - unbounded controller:value 可以 > 1(如金额几万、几十万),不会被 clamp
//
// 性能
//   - 一个值变化触发一次 controller.animateTo,内部 Tween 平滑插值
//   - AnimatedBuilder 在每个 frame 触发 rebuild,数字本身是 String.format,无重计算
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 360),
    this.curve = AppMotion.aquaIn,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.maxLines = 1,
    this.softWrap = false,
    this.overflow = TextOverflow.visible,
    this.textAlign = TextAlign.start,
    this.formatter,
  });

  /// 目标值。变化时会从当前值平滑滚动到新值
  final double value;

  /// 单次滚动时长(默认 360ms,ColorOS 数字组件标准)
  final Duration duration;

  /// 滚动曲线(默认 aquaIn,ColorOS 阻尼曲线)
  final Curve curve;

  /// 前缀(默认空,常用 "¥")
  final String prefix;

  /// 后缀(默认空,常用 "%")
  final String suffix;

  /// 文字样式,Text widget 标准
  final TextStyle? style;

  final int maxLines;
  final bool softWrap;
  final TextOverflow overflow;
  final TextAlign textAlign;

  /// 自定义格式化回调:把 double → 字符串。
  /// 默认 `value.toStringAsFixed(2)`,业务场景建议传 Formatters.amount(v)
  final String Function(double v)? formatter;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // unbounded:value 可以是任意 double(金额可能几万、几十万)
    _ctrl = AnimationController.unbounded(vsync: this, value: 0);
    // 首次入场:从 0 滚动到目标值。postFrameCallback 避免在 build 中调用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ctrl.animateTo(widget.value, duration: widget.duration, curve: widget.curve);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 值变化时:从 _ctrl.value(当前动画位置)滚动到新 widget.value
    if (widget.value != oldWidget.value) {
      _ctrl.stop();
      _ctrl.animateTo(
        widget.value,
        duration: widget.duration,
        curve: widget.curve,
      );
    }
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
        final v = _ctrl.value;
        final text = widget.prefix +
            (widget.formatter != null
                ? widget.formatter!(v)
                : v.toStringAsFixed(2)) +
            widget.suffix;
        return Text(
          text,
          style: widget.style,
          maxLines: widget.maxLines,
          softWrap: widget.softWrap,
          overflow: widget.overflow,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}