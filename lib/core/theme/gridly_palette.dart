// lib/core/theme/gridly_palette.dart
//
// D71.3 加:GridlyPalette ThemeExtension
//   暴露给 widget 用的"深色高对比卡片 / 强调色"专用 token:
//   - inkSurface: 重点卡 / 强调按钮底色(永远是 dark)
//   - onInkSurface: 在 inkSurface 上的"主文字 / icon"色
//   - accent: 强调色(nav bar 选中 / tab bar 指示器 / card_shadows 阴影 tint)
//     · 默认: AppBrand.gold (金黄 #F5BC1F)
//     · 粉色: AppPinkBrand.gold (亮粉 #FF5C8A)
//   - accentContainer: 强调色容器色(secondaryContainer)
//
// D71.4 决策:4 个 palette 组合,分别对应 4 种模式
//   - lightDefault:白天 + 默认 → 原版(白底 / 黑 ink 卡 / 金强调)
//   - lightPink:白天 + 粉色 → 粉色主题(粉底 / 深紫红 ink 卡 / 亮粉强调)
//   - darkDefault:夜晚 + 默认 → 原 dark(黑底 / 黑 ink 卡 / 金强调)
//   - darkPink:夜晚 + 粉色 → 黑底 / 黑 ink 卡 / 粉强调(阴影/发光都换成粉色)
//   - user 反馈"白天 / 夜晚 / 跟随系统"3 个主题 ×"默认 / 粉色"2 个色调 = 4 组合
//   - "夜晚 + 粉色"不全屏粉化,只把高光 / 阴影 / tab 选中色等强调色换成粉,
//     卡片 / 底色 / scaffold 保持黑色
//
// 跟 theme.colorScheme 的区别:
//   - colorScheme.inverseSurface: 跟随 brightness 翻转 → 适合 FAB / 按钮
//   - colorScheme.secondary: 内置色,跟 brightness + palette 都有关
//     但 nav bar / tab bar 在 light 模式下"选中 = gold"是写死的,不跟 palette 走
//   - GridlyPalette.accent: palette 决定(dark vs light 不影响),专门给
//     nav bar 选中 / tab indicator / card shadow tint 用

import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class GridlyPalette extends ThemeExtension<GridlyPalette> {
  const GridlyPalette({
    required this.inkSurface,
    required this.onInkSurface,
    required this.accent,
    required this.accentContainer,
  });

  /// 重点信息卡 / 强调按钮底色(永远 dark)
  final Color inkSurface;

  /// 在 inkSurface 上的"主文字 / icon"色(永远 light)
  final Color onInkSurface;

  /// 强调色(nav bar 选中 / tab indicator / card shadow tint)
  final Color accent;

  /// 强调色容器色(secondaryContainer)
  final Color accentContainer;

  /// 白天 + 默认品牌色(白 surface / 黑 ink 卡 / 金强调)
  static const lightDefault = GridlyPalette(
    inkSurface: AppBrand.ink,
    onInkSurface: AppSecondary.cream,
    accent: AppBrand.gold,
    accentContainer: AppSecondary.softGold,
  );

  /// 白天 + 粉色(粉 surface / 深紫红 ink 卡 / 亮粉强调)
  ///   D71.5.11:回归 #4A1942 冷紫(默认设计稿)
  ///   - inkSurface = AppPinkBrand.ink (冷紫 #4A1942)
  ///   - onInkSurface = AppPinkBrand.cream (米白)
  ///   - 焦点卡底色 + 文字跟默认主题同套视觉系统(冷紫 ink + cream 字)
  static const lightPink = GridlyPalette(
    inkSurface: AppPinkBrand.ink,
    onInkSurface: AppPinkBrand.cream,
    accent: AppPinkBrand.gold,
    accentContainer: AppPinkBrand.softGold,
  );

  /// 夜晚 + 默认(黑 surface / 黑 ink 卡 / 金强调)
  static const darkDefault = GridlyPalette(
    inkSurface: AppBrand.ink,
    onInkSurface: AppSecondary.cream,
    accent: AppBrand.gold,
    accentContainer: AppSecondary.softGold,
  );

  /// 夜晚 + 粉色(黑 surface / 黑 ink 卡 / 粉强调 — 只换阴影 / tab 选中,
  ///   卡片底色仍是黑,不全屏粉化)
  ///   D71.5.7:onInkSurface 退回 cream(白色字体)
  ///   焦点卡主文字白色,只有按钮 / 选中 / 阴影是粉
  static const darkPink = GridlyPalette(
    inkSurface: AppBrand.ink,
    onInkSurface: AppSecondary.cream,
    accent: AppPinkBrand.gold,
    accentContainer: AppPinkBrand.softGold,
  );

  @override
  GridlyPalette copyWith({
    Color? inkSurface,
    Color? onInkSurface,
    Color? accent,
    Color? accentContainer,
  }) {
    return GridlyPalette(
      inkSurface: inkSurface ?? this.inkSurface,
      onInkSurface: onInkSurface ?? this.onInkSurface,
      accent: accent ?? this.accent,
      accentContainer: accentContainer ?? this.accentContainer,
    );
  }

  @override
  GridlyPalette lerp(ThemeExtension<GridlyPalette>? other, double t) {
    if (other is! GridlyPalette) return this;
    return GridlyPalette(
      inkSurface: Color.lerp(inkSurface, other.inkSurface, t)!,
      onInkSurface: Color.lerp(onInkSurface, other.onInkSurface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
    );
  }
}