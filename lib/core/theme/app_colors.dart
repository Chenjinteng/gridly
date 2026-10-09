// lib/core/theme/app_colors.dart
// 配色规范来源:design/THEME.md v1.0
// 修改任何颜色前先查 THEME.md,不要直接覆盖本文件
import 'package:flutter/material.dart';

/// 品牌主色(三色)
class AppBrand {
  AppBrand._();
  static const Color ink = Color(0xFF0F1419);       // 炭黑 · 主背景(Dark)
  static const Color charcoal = Color(0xFF1F2329);  // 炭灰 · 主文字
  static const Color gold = Color(0xFFF5BC1F);      // 金黄 · 收入 / CTA
  static const Color teal = Color(0xFF14B8A6);      // 明亮青 · 支出 / 流动
}

/// 辅助色
class AppSecondary {
  AppSecondary._();
  static const Color softGold = Color(0xFFFFEAA7);  // 浅金
  static const Color lightTeal = Color(0xFFA7F3E0); // 浅青
  static const Color cream = Color(0xFFF5F1E8);     // 米白
}

/// 中性灰阶
class AppGray {
  AppGray._();
  static const Color g50 = Color(0xFFFAFAFA);
  static const Color g100 = Color(0xFFF4F4F5);
  static const Color g200 = Color(0xFFE4E4E7);
  static const Color g400 = Color(0xFFA1A1AA);
  static const Color g600 = Color(0xFF52525B);
  static const Color g900 = Color(0xFF18181B);
}

/// 状态色
class AppStatus {
  AppStatus._();
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
}

/// 记账语义色 —— 业务层用
class AppSemantic {
  AppSemantic._();
  static const Color income = AppBrand.gold;       // 收入 → 金
  static const Color expense = AppBrand.teal;      // 支出 → 青
  static const Color balance = AppBrand.ink;       // 结余 → 炭黑
  static const Color overBudget = AppStatus.error; // 超支 → 红
}
