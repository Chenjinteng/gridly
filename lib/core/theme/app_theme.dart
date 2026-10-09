// lib/core/theme/app_theme.dart
// Light + Dark ThemeData 装配
// 严格按 design/THEME.md §6.1 M3 ColorScheme 映射表
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

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
    );
  }
}
