// lib/shared/constants/default_categories.dart
// 默认分类:支出 12 类 + 收入 5 类
// 配色:v3 起每个分类独占语义色(支付宝记账本风格),
// 用于报表圆环 / 图例 / 流水图标背景的"分类维度"区分
//   - 支出 → 11 类各色 + 其他用灰
//   - 收入 → 4 类各色 + 退款用灰
// 所有色都集中定义在 AppCategory(见 app_colors.dart),不在本文件硬编码
import 'package:gridly/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class DefaultCategory {
  const DefaultCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    required this.sortOrder,
  });
  final String name;
  final String icon;          // icon key,对应 CategoryIcons.map
  final Color color;
  final String type;          // 'expense' | 'income'
  final int sortOrder;
}

/// 分类图标库 —— key → IconData
/// v2 起每个分类都用语义化图标(餐饮 → 餐具,交通 → 公交...),
/// 一眼能看出区别。v1 的 7 个几何图标保留作为老数据 fallback。
class CategoryIcons {
  CategoryIcons._();
  static const Map<String, IconData> map = {
    // === v2 语义化图标(rounded,Material 3 推荐) ===
    // 支出
    'restaurant': Icons.restaurant_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'home': Icons.home_rounded,
    'phone_iphone': Icons.phone_iphone_rounded,
    'medical_services': Icons.medical_services_rounded,
    'school': Icons.school_rounded,
    'movie': Icons.movie_rounded,
    'chair': Icons.chair_rounded,
    'spa': Icons.spa_rounded,
    'pets': Icons.pets_rounded,
    'more_horiz': Icons.more_horiz_rounded,
    // 收入
    'payments': Icons.payments_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'savings': Icons.savings_rounded,
    'work': Icons.work_rounded,
    'replay': Icons.replay_rounded,

    // === v1 几何图标(老数据 fallback,不再用于系统分类) ===
    'circle': Icons.circle_rounded,
    'square': Icons.square_rounded,
    'triangle': Icons.change_history_rounded,
    'diamond': Icons.diamond_rounded,
    'star': Icons.star_rounded,
    'hexagon': Icons.hexagon_rounded,
    'pentagon': Icons.pentagon_rounded,
    'category': Icons.category_rounded,
  };
}

class DefaultCategories {
  DefaultCategories._();

  /// 支出 12 类 —— 每个分类一个独特图标 + 一个独特颜色
  static const List<DefaultCategory> expense = [
    DefaultCategory(name: '餐饮', icon: 'restaurant',        color: AppCategory.food,           type: 'expense', sortOrder: 0),
    DefaultCategory(name: '交通', icon: 'directions_bus',    color: AppCategory.transport,      type: 'expense', sortOrder: 1),
    DefaultCategory(name: '购物', icon: 'shopping_bag',      color: AppCategory.shopping,       type: 'expense', sortOrder: 2),
    DefaultCategory(name: '居住', icon: 'home',              color: AppCategory.housing,        type: 'expense', sortOrder: 3),
    DefaultCategory(name: '通讯', icon: 'phone_iphone',      color: AppCategory.telecom,        type: 'expense', sortOrder: 4),
    DefaultCategory(name: '医疗', icon: 'medical_services',  color: AppCategory.medical,        type: 'expense', sortOrder: 5),
    DefaultCategory(name: '教育', icon: 'school',            color: AppCategory.education,      type: 'expense', sortOrder: 6),
    DefaultCategory(name: '娱乐', icon: 'movie',             color: AppCategory.entertainment,  type: 'expense', sortOrder: 7),
    DefaultCategory(name: '居家', icon: 'chair',             color: AppCategory.home,           type: 'expense', sortOrder: 8),
    DefaultCategory(name: '美妆', icon: 'spa',               color: AppCategory.beauty,         type: 'expense', sortOrder: 9),
    DefaultCategory(name: '宠物', icon: 'pets',              color: AppCategory.pet,            type: 'expense', sortOrder: 10),
    DefaultCategory(name: '其他', icon: 'more_horiz',        color: AppCategory.neutral,        type: 'expense', sortOrder: 99),
  ];

  /// 收入 5 类 —— 每个分类一个独特图标 + 一个独特颜色
  static const List<DefaultCategory> income = [
    DefaultCategory(name: '工资', icon: 'payments',          color: AppCategory.salary,     type: 'income', sortOrder: 0),
    DefaultCategory(name: '奖金', icon: 'card_giftcard',     color: AppCategory.bonus,      type: 'income', sortOrder: 1),
    DefaultCategory(name: '理财', icon: 'savings',           color: AppCategory.invest,     type: 'income', sortOrder: 2),
    DefaultCategory(name: '兼职', icon: 'work',              color: AppCategory.parttime,   type: 'income', sortOrder: 3),
    DefaultCategory(name: '退款', icon: 'replay',            color: AppCategory.neutral,    type: 'income', sortOrder: 99),
  ];
}

/// v1 → v2 图标 key 迁移表,按 name 匹配老数据。
/// 老用户数据库里的系统分类可能是 v1 几何 key,这里按名字映射升级。
const Map<String, String> kIconMigrationV2 = {
  '餐饮': 'restaurant',
  '交通': 'directions_bus',
  '购物': 'shopping_bag',
  '居住': 'home',
  '通讯': 'phone_iphone',
  '医疗': 'medical_services',
  '教育': 'school',
  '娱乐': 'movie',
  '居家': 'chair',
  '美妆': 'spa',
  '宠物': 'pets',
  '其他': 'more_horiz',
  '工资': 'payments',
  '奖金': 'card_giftcard',
  '理财': 'savings',
  '兼职': 'work',
  '退款': 'replay',
};