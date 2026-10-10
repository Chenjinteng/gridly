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
  static const Color expense = AppStatus.error;    // 支出 → 红(警示,刺眼)
  static const Color balance = AppBrand.ink;       // 结余 → 炭黑
  static const Color overBudget = AppStatus.error; // 超支 → 红
}

/// 分类语义色 —— 用于报表圆环 / 图例 / 流水列表图标背景的"分类"维度区分
/// 不与 AppSemantic.expense / income 冲突(那是文字色,这里是分类色)
/// 命名按"业务领域"而非"颜色",避免一处改名到处跟改
/// 调色板参照支付宝记账本 + 微信记账本的分类习惯
class AppCategory {
  AppCategory._();
  // === 支出 11 类(自定义 / 其他用中性灰) ===
  static const Color food = AppStatus.warning;          // 餐饮 — 橙
  static const Color transport = AppStatus.info;        // 交通 — 蓝
  static const Color shopping = Color(0xFFEC4899);      // 购物 — 粉
  static const Color housing = Color(0xFF92400E);       // 居住 — 棕
  static const Color telecom = Color(0xFF06B6D4);       // 通讯 — 青
  static const Color medical = AppStatus.error;         // 医疗 — 红(警示,和支出文字色同系但允许)
  static const Color education = Color(0xFF8B5CF6);       // 教育 — 紫
  static const Color entertainment = AppStatus.success; // 娱乐 — 绿
  static const Color home = Color(0xFFD97706);          // 居家 — 棕橙
  static const Color beauty = Color(0xFFF43F5E);        // 美妆 — 玫红
  static const Color pet = Color(0xFFFB923C);           // 宠物 — 浅橙

  // === 收入 4 类(退款用中性灰) ===
  static const Color salary = AppBrand.gold;            // 工资 — 金(主收入)
  static const Color bonus = Color(0xFFFFC107);         // 奖金 — 亮金
  static const Color invest = AppStatus.success;        // 理财 — 绿(收益)
  static const Color parttime = Color(0xFFA855F7);      // 兼职 — 紫

  // === 中性 ===
  static const Color neutral = AppGray.g400;           // 其他 / 退款

  /// 自定义分类调色板 —— Python 导入脚本按 name hash 在这里分散取色
  /// 不要把分类专属色(food/transport/...)放进来,只放"通用色",
  /// 保证预置 12 类在报表里仍独占语义色
  static const List<int> hashPalette = [
    0xFFFB923C,  // 浅橙
    0xFFEC4899,  // 粉
    0xFF06B6D4,  // 青
    0xFFA855F7,  // 紫
    0xFFD97706,  // 棕橙
    0xFFF43F5E,  // 玫红
    0xFF6366F1,  // 靛
    0xFF14B8A6,  // 青绿
    0xFFEAB308,  // 柠檬黄
    0xFF84CC16,  // 草绿
    0xFF0891B2,  // 深青
    0xFF7C3AED,  // 深紫
  ];
}
