// lib/core/haptics/app_haptics.dart
// 全局触觉反馈 token —— 封装 Flutter HapticFeedback API,按 ColorOS Tactile
// Haptics(2026-10-12 ColorOS 13+ O-Haptics / ColorOS 17 O-Haptic 2.0)语义命名。
//
// 设计依据
//   - ColorOS 13+ 引入 O-Haptics 统一触觉引擎,跨按键 / 列表 / 滑块 / 错误提示
//     都用同套"tactile language"。下面是 gridly 选用的 5 个基础语义:
//       tap      → KEYBOARD_TAP / lightImpact (40ms,低频,数字键)
//       select   → KEYBOARD_TAP / selectionClick (短促,tab/segment 切换)
//       success  → mediumImpact (60-80ms,中频,操作完成)
//       warning  → heavyImpact (120-200ms,高频,删除/失败)
//       nudge    → lightImpact (轻"嗯"一下,过阈值反馈)
//   - iOS 端 Taptic Engine 的 selection / impactLight/Medium/Heavy 与本套
//     大致对应,但 iOS 永远不做(gridly Android-only),只用 Android 行为。
//   - 集中封装好处:将来加"触感反馈开关"(settings 页面)或调强度,只改这一文件。
//
// 用法
//   - Numpad 每个按键 onTapDown / onTapUp 时调用 AppHaptics.tap()
//   - Tab / segment 切换时调用 AppHaptics.select()
//   - 保存成功 / 错误时调用 AppHaptics.success() / AppHaptics.warning()
//   - 滑动过阈值时调用 AppHaptics.nudge()

import 'package:flutter/services.dart';

class AppHaptics {
  AppHaptics._();

  /// 数字按键 / chip 选中 — 轻短振 (40ms)
  /// ColorOS "Tactile Tap":数字键 / 列表项点击的标准反馈
  static Future<void> tap() async {
    await HapticFeedback.lightImpact();
  }

  /// tab / segment 切换 — 短振 + selectionClick (selection 比 light 更"轻咔哒")
  /// ColorOS "Tactile Toggle":换页 / 切 tab 的标志性"咔哒"感
  static Future<void> select() async {
    await HapticFeedback.selectionClick();
  }

  /// 操作成功(保存成功 / 数值计算完成 / banner "已保存")— 中量振
  /// ColorOS "Success Pattern":操作完成的肯定反馈
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
  }

  /// 警告(删除 / 错误 / 失败)— 重量振
  /// ColorOS "Heavy Warning":删除 / 错误的高强度提醒
  static Future<void> warning() async {
    await HapticFeedback.heavyImpact();
  }

  /// 过阈值(滑动过 snap 阈值 / 长按 / 拖动过界)— 轻短振
  /// ColorOS "Threshold":用户操作"跨过了一个有意义的边界"的微反馈
  static Future<void> nudge() async {
    await HapticFeedback.lightImpact();
  }
}