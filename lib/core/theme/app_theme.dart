// lib/core/theme/app_theme.dart
// Light + Dark ThemeData 装配
// 严格按 design/THEME.md §6.1 M3 ColorScheme 映射表
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';
import 'gridly_palette.dart';

/// 2026-10-11 UAT:PopupMenu 默认浅灰白底 + 圆角极小,跟 ink 黑主题 +
/// range_tabs 的 teal 选中态对比突兀。定制 popupMenuTheme:
///   - 背景:surfaceContainerHigh(M3 卡片层),暗主题下为 #1A2029
///   - 圆角:brMd(12px),跟卡片系列一致
///   - 选中项:primary 12% alpha bg + primary text(跟 range_tabs 同语义)
///   - 边框:outlineVariant 0.5px,增加深色主题下的可见性
PopupMenuThemeData _buildPopupMenuTheme(ColorScheme scheme) {
  return PopupMenuThemeData(
    color: scheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.brMd,
      side: BorderSide(color: scheme.outlineVariant, width: 0.5),
    ),
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.4),
    textStyle: TextStyle(
      color: scheme.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    position: PopupMenuPosition.under,
  );
}

class AppTheme {
  AppTheme._();

  /// M3 ColorScheme 映射表(见 THEME.md §6.1)
  static ColorScheme _lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: AppBrand.teal,
      onPrimary: Colors.white,
      primaryContainer: AppSecondary.lightTeal,
      onPrimaryContainer: AppBrand.ink,

      secondary: AppBrand.gold,
      onSecondary: AppBrand.ink,
      secondaryContainer: AppSecondary.softGold,
      onSecondaryContainer: AppBrand.ink,

      tertiary: AppSecondary.cream,
      onTertiary: AppBrand.ink,

      error: AppStatus.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: AppStatus.error,

      surface: Colors.white,
      onSurface: AppBrand.charcoal,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppGray.g50,
      surfaceContainer: AppGray.g100,
      surfaceContainerHigh: AppGray.g200,
      surfaceContainerHighest: AppGray.g200,
      onSurfaceVariant: AppGray.g600,
      outline: AppGray.g200,
      outlineVariant: AppGray.g100,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppBrand.ink,
      onInverseSurface: AppSecondary.cream,
      inversePrimary: AppSecondary.lightTeal,
    );
  }

  static ColorScheme _darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: AppSecondary.lightTeal,    // Dark 下用浅青,提高对比度
      onPrimary: AppBrand.ink,
      primaryContainer: AppBrand.teal,
      onPrimaryContainer: AppBrand.ink,

      secondary: AppBrand.gold,
      onSecondary: AppBrand.ink,
      secondaryContainer: Color(0xFF7A5A0F),  // 深金
      onSecondaryContainer: AppSecondary.softGold,

      tertiary: AppSecondary.cream,
      onTertiary: AppBrand.ink,

      error: AppStatus.error,
      onError: Colors.white,
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),

      surface: AppBrand.ink,
      onSurface: AppSecondary.cream,
      surfaceContainerLowest: Color(0xFF05080B),
      surfaceContainerLow: Color(0xFF0D1116),
      surfaceContainer: Color(0xFF131820),
      surfaceContainerHigh: Color(0xFF1A2029),
      surfaceContainerHighest: Color(0xFF222933),
      onSurfaceVariant: AppGray.g400,
      outline: AppGray.g600,
      outlineVariant: Color(0xFF222933),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppGray.g50,
      onInverseSurface: AppBrand.ink,
      inversePrimary: AppBrand.teal,
    );
  }

  static ThemeData light() {
    final scheme = _lightScheme();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: const TextTheme(
        displayLarge: AppTypography.displayL,
        displayMedium: AppTypography.displayM,
        headlineMedium: AppTypography.h1,
        titleLarge: AppTypography.h2,
        titleMedium: AppTypography.h3,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.bodySm,
        labelSmall: AppTypography.caption,
      ),
      fontFamily: fontFamilyZh,
      popupMenuTheme: _buildPopupMenuTheme(scheme),
      // D71.4:nav bar 选中色从 GridlyPalette.accent 读
      //   默认=AppBrand.gold(2026-10-11 UAT 拍的),保持原样
      extensions: const [GridlyPalette.lightDefault],
    )._applyPaletteGridly();
  }

  static ThemeData dark() {
    final scheme = _darkScheme();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: const TextTheme(
        displayLarge: AppTypography.displayL,
        displayMedium: AppTypography.displayM,
        headlineMedium: AppTypography.h1,
        titleLarge: AppTypography.h2,
        titleMedium: AppTypography.h3,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.bodySm,
        labelSmall: AppTypography.caption,
      ),
      fontFamily: fontFamilyZh,
      popupMenuTheme: _buildPopupMenuTheme(scheme),
      // D71.4:nav bar / tab bar 选中色都读 GridlyPalette.accent
      //   默认=AppBrand.gold,跟原版一致
      extensions: const [GridlyPalette.darkDefault],
    )._applyPaletteGridly();
  }

  // ============================================================
  // 粉色主题(D71.1 加 · 2026-10-19,D71.2 全面粉化)
  //   跟默认主题结构完全一致,把 AppBrand/部分 AppSecondary 替换为 AppPinkBrand
  //   4 种组合(浅+默认 / 浅+粉 / 深+默认 / 深+粉)由 app.dart 根据 mode × palette 选
  //   D71.2:surface 系列全部粉化,卡片底色直接走 scheme.surfaceContainer* 自动跟随 palette
  // ============================================================
  static ColorScheme _pinkLightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: AppPinkBrand.teal,
      onPrimary: Colors.white,
      primaryContainer: AppPinkBrand.lightTeal,
      onPrimaryContainer: AppPinkBrand.ink,

      secondary: AppPinkBrand.gold,
      onSecondary: AppPinkBrand.ink,
      secondaryContainer: AppPinkBrand.softGold,
      onSecondaryContainer: AppPinkBrand.ink,

      tertiary: AppPinkBrand.cream,
      onTertiary: AppPinkBrand.ink,

      error: AppStatus.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: AppStatus.error,

      // D71.2:scaffold 底色=暖白(代替默认纯白),用户进 app 第一眼就粉
      surface: AppPinkBrand.cream,
      onSurface: AppPinkBrand.charcoal,
      // D71.2:卡片分层全粉化,所有 Container/Card/Dialog/Sheet 默认底色自动跟随
      surfaceContainerLowest: Color(0xFFFCF5F9),  // 极浅,接近白但带粉调
      surfaceContainerLow: Color(0xFFFEE9F0),     // 卡片 1 层
      surfaceContainer: Color(0xFFFFDCE7),        // 卡片 2 层(明显粉)
      surfaceContainerHigh: Color(0xFFFFCFDF),    // 卡片 3 层
      surfaceContainerHighest: Color(0xFFFFC2D6), // 卡片 4 层(最深粉)
      onSurfaceVariant: Color(0xFF8B5A6E),        // 粉调灰文字
      outline: Color(0xFFEE9FB6),                 // 粉调边框
      outlineVariant: Color(0xFFFFD9E5),          // 浅粉边
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppPinkBrand.ink,
      onInverseSurface: AppPinkBrand.cream,
      inversePrimary: AppPinkBrand.lightTeal,
    );
  }

  static ThemeData pinkLight() {
    final scheme = _pinkLightScheme();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: const TextTheme(
        displayLarge: AppTypography.displayL,
        displayMedium: AppTypography.displayM,
        headlineMedium: AppTypography.h1,
        titleLarge: AppTypography.h2,
        titleMedium: AppTypography.h3,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.bodySm,
        labelSmall: AppTypography.caption,
      ),
      fontFamily: fontFamilyZh,
      popupMenuTheme: _buildPopupMenuTheme(scheme),
      // D71.4:nav bar / tab bar 选中色从 GridlyPalette.accent 读(亮粉)
      extensions: const [GridlyPalette.lightPink],
    )._applyPaletteGridly();
  }

  /// D71.5:夜晚 + 粉色组合的 ThemeData
  ///   - 跟 dark() 几乎一样,但 inverseSurface 换成 palette.accent,
  ///     这样 button / FAB / "反色按钮" 底色 = 亮粉(原来 cream)
  ///   - onInverseSurface = 黑(亮粉底配黑字 readable)
  ///   - 其他色(secondary / nav bar 选中 / 阴影 tint)已经走 palette.accent
  ///   palette.accent 跟 inverseSurface 都是亮粉,UI 上看不出重复 ——
  ///   M3 token 语义保持(button bg = inverseSurface,选中 = secondary)
  static ThemeData darkWithPalette(GridlyPalette palette) {
    final baseScheme = _darkScheme();
    // D71.5.7:夜晚+粉色 = "保守粉"方案 — 文字回白色(cream),只保留
    //  按钮 / 选中 / 阴影是粉的
    //   - 之前 D71.5.3 把 onSurface / onSurfaceVariant 都换成粉,看起来太激进
    //   - 退回 onSurface = cream(正常白天文字色),onSurfaceVariant = AppGray.g400
    //   - inverseSurface / secondary / primary / tertiary 还是 palette.accent
    //     (按钮 / tab 选中 / AquaSwitch on / chart 高亮 / card 阴影都是粉)
    //   - GridlyPalette.darkPink.onInkSurface 也退回 cream(焦点卡主文字不粉)
    final scheme = baseScheme.copyWith(
      inverseSurface: palette.accent,    // 按钮底色=亮粉(保留)
      onInverseSurface: AppBrand.ink,   // 按钮字色=黑(保留)
      secondary: palette.accent,        // tab 选中 / chip 选中(保留)
      onSurface: AppSecondary.cream,    // ← 退回:所有正文文字回白色
      onSurfaceVariant: AppGray.g400,    // ← 退回:副文字回默认灰
      primary: palette.accent,          // AquaSwitch / chart 高亮(保留)
      onPrimary: AppBrand.ink,
      primaryContainer: AppPinkBrand.lightTeal,
      onPrimaryContainer: AppBrand.ink,
      tertiary: AppPinkBrand.lightTeal,
      onTertiary: AppBrand.ink,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: const TextTheme(
        displayLarge: AppTypography.displayL,
        displayMedium: AppTypography.displayM,
        headlineMedium: AppTypography.h1,
        titleLarge: AppTypography.h2,
        titleMedium: AppTypography.h3,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.bodySm,
        labelSmall: AppTypography.caption,
      ),
      fontFamily: fontFamilyZh,
      popupMenuTheme: _buildPopupMenuTheme(scheme),
      extensions: [palette],
    )._applyPaletteGridly();
  }
}

/// D71.4:把 GridlyPalette 里的 accent 应用到 nav bar / tab bar 选中色
///   ThemeData factory 末尾链式调用 ._applyPaletteGridly(),把硬编码
///   AppBrand.gold / AppPinkBrand.gold 都换成 palette.accent
///   - 不在 factory 内部直接用 `extensions: [palette]` + `accent: palette.accent`,
///     因为 ThemeData 构造器里读不到自己的 extensions(Dart 不支持)
///   - 改成链式 ._applyPaletteGridly() 方法,内部 copyWith 后再注入
extension _ApplyPaletteGridly on ThemeData {
  ThemeData _applyPaletteGridly() {
    final palette = extension<GridlyPalette>();
    if (palette == null) return this;
    return copyWith(
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? palette.accent
                : colorScheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? palette.accent
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.accent,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: palette.accent,
      ),
    );
  }
}
