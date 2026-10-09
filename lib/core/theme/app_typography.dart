// lib/core/theme/app_typography.dart
// 字阶规范来源:design/THEME.md §4
import 'package:flutter/material.dart';

/// 字体家族(跨端)
const String fontFamilyZh = 'PingFang SC';
const String fontFamilyEn = 'SF Pro Display';
const String fontFamilyMono = 'SF Mono';

class AppTypography {
  AppTypography._();

  static const TextStyle displayL = TextStyle(
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const TextStyle displayM = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 10,
    height: 14 / 10,
    fontWeight: FontWeight.w400,
  );
}
