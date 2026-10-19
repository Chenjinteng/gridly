// lib/core/theme/card_shadows.dart
// 卡片阴影统一管理 —— dark mode 自动切换黑/白阴影色
//
// 三档:
// - [dark] 用于黑底卡片(月度汇总 / 报表 range summary):
//   浅色模式下黑底白底反差大,需要重阴影"浮起来"。
// - [light] 用于白底卡片(预算 / 设置主题 / 流水 / 分类 / 趋势 / 饼图 / Top10 / 隐私):
//   白底本身较浅,重阴影视觉过载。
// - [pill] 极轻单层阴影,用于小尺寸 pill/button(TypeToggle / 行动 row pill / 保存按钮):
//   2026-10-13 P7 user UAT:"切换以及所有按钮要增加一点点投影,不然没立体感"
//   单层 black alpha 0.04 + blur 4 + offset (0, 1),刚好离开白纸面。
//
// D71.4:深色模式阴影 tint 走 GridlyPalette.accent
//   - 默认 = AppBrand.gold(暖金光感)
//   - 粉色 = AppPinkBrand.gold(粉色光感)
//   - 之前 dark mode shadow 统一硬编码 gold → 夜晚+粉色时 tint 自动换成粉
//   - 浅色模式保持黑(传统投影)
import 'package:flutter/material.dart';

import 'gridly_palette.dart';

class CardShadows {
  CardShadows._();

  /// 黑底卡(月度汇总卡 / range summary)
  static List<BoxShadow> dark(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = Theme.of(context).extension<GridlyPalette>();
    // 深色模式用 palette.accent 做暖色光感(默认金 / 粉色亮粉),
    // 浅色模式保持黑(传统投影)
    final color = isDark && palette != null ? palette.accent : Colors.black;
    return [
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.06 : 0.12),
        blurRadius: 8,
        // 右下投影:模拟光从左上打来,卡浮起来的浮雕感
        offset: const Offset(3, 5),
      ),
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.03 : 0.06),
        blurRadius: 10,
        offset: const Offset(8, 12),
      ),
    ];
  }

  /// 白底卡(预算 / 设置主题 / Top10 / 流水 / 分类 / 月度趋势 / 饼图 / 隐私)
  static List<BoxShadow> light(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = Theme.of(context).extension<GridlyPalette>();
    final color = isDark && palette != null ? palette.accent : Colors.black;
    return [
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.06 : 0.05),
        blurRadius: 6,
        offset: const Offset(2, 3),
      ),
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.03 : 0.025),
        blurRadius: 8,
        offset: const Offset(4, 7),
      ),
    ];
  }

  /// 极轻单层 pill 阴影(2026-10-13 P7 加)
  /// - 适用:小尺寸 pill / 按钮(TypeToggle 外层 / 行动 row 3 pill / 保存按钮)
  /// - 视觉:刚好离开纸面,有立体感但不抢戏
  /// - 浅色:black alpha 0.04 + blur 4 + offset (0, 1)
  /// - 深色:palette.accent alpha 0.08(暖光感,默认金 / 粉亮粉)
  static List<BoxShadow> pill(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = Theme.of(context).extension<GridlyPalette>();
    final color = isDark && palette != null ? palette.accent : Colors.black;
    return [
      BoxShadow(
        color: color.withValues(alpha: isDark ? 0.08 : 0.04),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }
}