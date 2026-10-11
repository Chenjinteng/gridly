// lib/core/theme/app_radius.dart
// 圆角规范来源:design/THEME.md §5.1
// LOGO 圆角 = rXl(24),App 内主要容器向 LOGO 看齐
import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;       // LOGO 同款,主要容器向 LOGO 看齐
  static const double full = 9999;

  // 预制 BorderRadius,直接用
  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  // pill 胶囊形:用超大值(Flutter 自动 clamp 到边长一半)= 任意长方形都成胶囊
  // (2026-10-11 加:流水 tile 左滑 edit/delete 按钮统一成 pill)
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(full));
}
