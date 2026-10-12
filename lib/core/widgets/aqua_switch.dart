// lib/core/widgets/aqua_switch.dart
// 拟物风开关 — 替 Material Switch,跟 ColorOS Aquamorphic 调性合
//
// 设计动机 (commit 65):
//   - Flutter Material 3 Switch 默认 52x32,在 mobile settings 列表里太大,
//     跟左侧 14sp title + 11sp subtitle 不协调;且是 M3 flat 风格,跟
//     gridly 一直追求的"色彩 + 立体感"调性脱节。
//   - 自绘 AquaSwitch = 44x26(小 ~20%),off 时 track 用 outlineVariant
//     边框模拟"刻进卡片"的凹槽,on 时 track 用 primary 外发光 + thumb
//     drop shadow + 顶部 highlight = 凸起的圆球。
//
// 用法
//   AquaSwitch(
//     value: amountVisible,
//     onChanged: (v) => ref.read(provider.notifier).set(v),
//   )
//
// 行为
//   - tap 整个 widget 切换 value;不依赖外部 GestureDetector
//   - 切换时 AppHaptics.tap() 反馈(16ms,切 tap 不是切 select — 单次)
//   - thumb 滑动 + track 颜色过渡都是 240ms AppMotion.fast + aquaIn,
//     跟 range_tabs pill / perspective segmented 动画语汇统一
//
// 几何
//   - trackWidth = 44, trackHeight = 26, thumb = 20x20,thumb 边距 3
//   - 没有显式扩大 tap area(44x26 < M3 minimum 48x48),靠父 ListTile
//     自带的 dense + contentPadding 撑足 48 vertical 热区
//   - dense ListTile 内显示:trailing 由 ListTile 居中,AquaSwitch 整体
//     占据 44x26 不撑大
import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../motion/app_motion.dart';

class AquaSwitch extends StatelessWidget {
  const AquaSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  // 几何常量在编译期确定,build 内 const 化让 Flutter 能复用 RenderObject
  static const double _trackWidth = 44;
  static const double _trackHeight = 26;
  static const double _thumbDiameter = 20;
  static const double _thumbPadding = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Track color + border:
    //   off: surfaceContainerHigh(比卡片 surfaceContainerLow 略亮,有微小
    //        高度差)+ outlineVariant 边框 = "凹陷进卡片"的视觉
    //   on:  primary 满色 + 外发光 shadow = "凸起浮在卡片上"
    final trackColor = value
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHigh;
    final trackBorder = value
        ? Colors.transparent
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    // Thumb color:off 是 onSurface 0.85 alpha 灰白(不抢眼),on 是 pure white(干净跳眼)
    final thumbColor = value
        ? Colors.white
        : theme.colorScheme.onSurface.withValues(alpha: 0.85);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onChanged(!value);
      },
      // 整个 widget = tap target(dense ListTile 内 trailing 已默认 vertical 居中)
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.aquaIn,
        width: _trackWidth,
        height: _trackHeight,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(_trackHeight / 2),
          border: Border.all(color: trackBorder, width: 0.5),
          boxShadow: [
            // off: 上下方向微小阴影,让 track 在卡片上"贴"着而非漂
            if (!value)
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            // on: primary 颜色发光,给 track"凸起+发光"的双重拟物感
            if (value)
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: AppMotion.fast,
              curve: AppMotion.aquaIn,
              // thumb 圆心 x:
              //   off: thumbPadding + thumbDiameter/2 = 13
              //   on:  trackWidth - thumbPadding - thumbDiameter/2 = 31
              left: value
                  ? _trackWidth - _thumbDiameter - _thumbPadding
                  : _thumbPadding,
              top: _thumbPadding,
              // bottom: _thumbPadding 控 thumb 高度;width: thumbDiameter
              // 让 RenderBox 自己算 thumbRender size,不用 ScrollPadding 这套
              width: _thumbDiameter,
              height: _thumbDiameter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: thumbColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    // 凸起:drop shadow(下方) + 顶部 highlight(白)叠加
                    // dark mode 阴影更深,light mode 顶部 highlight 更亮
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.22,
                      ),
                      blurRadius: 3,
                      offset: const Offset(0, 1.5),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.22 : 0.55,
                      ),
                      blurRadius: 1,
                      offset: const Offset(0, -0.6),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
