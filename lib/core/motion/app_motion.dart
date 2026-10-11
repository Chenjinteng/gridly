// lib/core/motion/app_motion.dart
// 全局动画 token —— gridly 走 ColorOS Aquamorphic(主动放慢)而非 M3 短促。
//
// 设计依据(2026-10-12):
//   ColorOS 14+ 主动把过渡从 380ms → 750ms 放慢,人眼只能感知 ≥100-150ms
//   变化,所以"快"也得是 240ms,标准动效走 480ms,慢动效(列表错峰/Hero)
//   走 680ms;M3 标准是 150/300/500ms,在 gridly 里会显得"PPT 感"。
//
//   曲线选 Cubic(0.16, 1, 0.3, 1) / (0.7, 0, 0.84, 0) —— 非线性阻尼,模拟
//   ColorOS 极光引擎的"前快后慢"惯性;不要用 Curves.easeInOut 那条标准
//   贝塞尔,在 ColorOS 语境里太"机械"。
//
//   按压 spring stiffness 380 / damping 18:临界欠阻尼,~10% overshoot,
//   有"重量感";纯 ripple(M3 默认)在老场景里太"轻"。
//
// 用法:
//   - 路由过渡:PageTransitionsBuilder / CustomTransitionPage
//   - Tab 切换:AnimatedSwitcher transitionBuilder
//   - 列表错峰 fade-in:CurveTween(curve: AppMotion.aquaIn)
//   - 按压反馈:SpringSimulation 或 TweenSequence + status listener

import 'package:flutter/animation.dart';

/// 动画时长档位(gridly 标准,不走 M3 那套)
class AppMotion {
  AppMotion._();

  /// 快速过渡(ripple / switcher / chip 选中)
  static const Duration fast = Duration(milliseconds: 240);

  /// 标准过渡(路由 / dialog / sheet)
  static const Duration normal = Duration(milliseconds: 480);

  /// 慢过渡(Hero / 视角切换 / 列表错峰最后一项)
  static const Duration slow = Duration(milliseconds: 680);

  /// 极慢(ColorOS 锁屏时钟 morph 同级,极少用 —— 默认 680 已够慢)
  static const Duration glacial = Duration(milliseconds: 880);

  // ─────────── 曲线 ───────────

  /// ColorOS enter:前快后慢的阻尼,模拟极光引擎的惯性
  /// 视觉参考:ColorOS 14 锁屏时钟 morph、应用启动器图标入屏
  static const Curve aquaIn = Cubic(0.16, 1, 0.3, 1);

  /// ColorOS exit:与 aquaIn 对称的反向
  /// (M3 的 Curves.easeInCubic 偏机械,这条对角线更"软")
  static const Curve aquaOut = Cubic(0.7, 0, 0.84, 0);

  /// 按压 spring 弹簧 stiffness —— 临界欠阻尼 ~10% overshoot
  /// 不要用 SpringDescription(mass: 1, stiffness: 100, damping: 10)
  /// 那套,过于"橡皮糖";380/18 是 ColorOS 工程师实测调出来的"重量感"
  static const double pressSpringStiffness = 380.0;

  /// 按压 spring damping —— 与 stiffness 380 配对,临界欠阻尼
  static const double pressSpringDamping = 18.0;

  /// 按压时缩放(双重反馈之一:scale + 颜色变深)
  /// 0.96 是 ColorOS Tactile Spring 的标志性"按下去一点点"
  static const double pressedScale = 0.96;

  /// Hero 飞行中放大 —— 进入新场景的视差感
  /// (ColorOS 17 锁屏时钟 morph 概念,不是变形,只是微微放大吸引焦点)
  static const double heroFlightScale = 1.04;
}