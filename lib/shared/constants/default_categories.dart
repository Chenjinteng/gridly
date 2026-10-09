// lib/shared/constants/default_categories.dart
// 默认分类:支出 12 类 + 收入 5 类
// 配色严格按 design/THEME.md §3.5 记账语义映射
//   - 支出 → teal 系
//   - 收入 → gold 系
//   - 中性类(其他/退款) → 灰
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
  final String icon;          // icon key,对应 _iconMap
  final Color color;
  final String type;          // 'expense' | 'income'
  final int sortOrder;
}

/// 8 种预设几何图标(对应 design/THEME.md §6.7 分类图标)
/// key 是 icon 字符串,P1+ 在 UI 里用 key 查对应 IconData
class CategoryIcons {
  CategoryIcons._();
  static final Map<String, IconData> map = {
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

  /// 支出 12 类
  static const List<DefaultCategory> expense = [
    DefaultCategory(name: '餐饮', icon: 'circle',    color: AppBrand.teal,        type: 'expense', sortOrder: 0),
    DefaultCategory(name: '交通', icon: 'triangle',  color: AppBrand.teal,        type: 'expense', sortOrder: 1),
    DefaultCategory(name: '购物', icon: 'square',    color: AppBrand.teal,        type: 'expense', sortOrder: 2),
    DefaultCategory(name: '居住', icon: 'hexagon',   color: AppBrand.teal,        type: 'expense', sortOrder: 3),
    DefaultCategory(name: '通讯', icon: 'diamond',   color: AppBrand.teal,        type: 'expense', sortOrder: 4),
    DefaultCategory(name: '医疗', icon: 'star',      color: AppBrand.teal,        type: 'expense', sortOrder: 5),
    DefaultCategory(name: '教育', icon: 'pentagon',  color: AppBrand.teal,        type: 'expense', sortOrder: 6),
    DefaultCategory(name: '娱乐', icon: 'category',  color: AppBrand.teal,        type: 'expense', sortOrder: 7),
    DefaultCategory(name: '居家', icon: 'square',    color: AppBrand.teal,        type: 'expense', sortOrder: 8),
    DefaultCategory(name: '美妆', icon: 'diamond',   color: AppBrand.teal,        type: 'expense', sortOrder: 9),
    DefaultCategory(name: '宠物', icon: 'circle',    color: AppBrand.teal,        type: 'expense', sortOrder: 10),
    DefaultCategory(name: '其他', icon: 'circle',    color: AppGray.g400,         type: 'expense', sortOrder: 99),
  ];

  /// 收入 5 类
  static const List<DefaultCategory> income = [
    DefaultCategory(name: '工资', icon: 'star',      color: AppBrand.gold,        type: 'income', sortOrder: 0),
    DefaultCategory(name: '奖金', icon: 'star',      color: AppBrand.gold,        type: 'income', sortOrder: 1),
    DefaultCategory(name: '理财', icon: 'diamond',   color: AppBrand.gold,        type: 'income', sortOrder: 2),
    DefaultCategory(name: '兼职', icon: 'pentagon',  color: AppBrand.gold,        type: 'income', sortOrder: 3),
    DefaultCategory(name: '退款', icon: 'square',    color: AppGray.g400,         type: 'income', sortOrder: 99),
  ];
}
