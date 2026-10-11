// lib/core/theme/card_shadows.dart
// 卡片阴影统一管理 —— dark mode 自动切换黑/白阴影色
//
// 两档:
// - [dark] 用于黑底卡片(月度汇总 / 报表 range summary):
//   浅色模式下黑底白底反差大,需要重阴影"浮起来"。
// - [light] 用于白底卡片(预算 / 设置主题 / 流水 / 分类 / 趋势 / 饼图 / Top10 / 隐私):
//   白底本身较浅,重阴影视觉过载。
//
// dark mode 自动用白色阴影(否则黑阴影在黑底上不可见)。
import 'package:flutter/material.dart';

import 'app_colors.dart';

class CardShadows {
  CardShadows._();

  /// 黑底卡(月度汇总卡 / range summary)
  static List<BoxShadow> dark(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深色模式用品牌金(AppBrand.gold)做暖色光感,呼应 Ink/Gold/Teal 三色;
    // 浅色模式保持黑(传统投影)
    final color = isDark ? AppBrand.gold : Colors.black;
    return [
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.15 : 0.12),
        blurRadius: 14,
        // 右下投影:模拟光从左上打来,卡浮起来的浮雕感
        offset: const Offset(3, 5),
      ),
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.08 : 0.06),
        blurRadius: 18, // 收一档:32→18,减少扩散
        offset: const Offset(8, 12),
      ),
    ];
  }

  /// 白底卡(预算 / 设置主题 / Top10 / 流水 / 分类 / 月度趋势 / 饼图 / 隐私)
  static List<BoxShadow> light(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppBrand.gold : Colors.black;
    return [
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.10 : 0.05),
        blurRadius: 8,
        offset: const Offset(2, 3),
      ),
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.05 : 0.025),
        blurRadius: 12, // 收一档:16→12
        offset: const Offset(4, 7),
      ),
    ];
  }
}