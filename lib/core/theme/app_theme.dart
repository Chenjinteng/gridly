// lib/core/theme/app_theme.dart
// Light + Dark ThemeData 装配
// 严格按 design/THEME.md §6.1 M3 ColorScheme 映射表
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

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
      // 2026-10-11 UAT:浅色模式选中 tab 用品牌金 #F5BC1F (AppBrand.gold),
      // 不用默认的 onSurface (charcoal),跟品牌"金+青+炭"主色对齐。
      // 暗色模式保持默认 onSurface (cream) 不动 —— 那里配色已经够清晰。
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppBrand.gold : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppBrand.gold : scheme.onSurfaceVariant,
          );
        }),
      ),
    );
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
    );
  }
}
