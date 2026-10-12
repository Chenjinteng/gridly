// lib/core/database/tables/category_budgets.dart
// 分类月度预算表 —— 给具体分类分配子额度(基于总额度)
//
// 2026-10-12 commit 90 加:
//   user 反馈"月度预算只是总额度,想基于总额度自由分配不同分类的额度"
//     - 总额度 = monthlyBudget(SharedPreferences,commit 之前已存在)
//     - 分类子额度 = 本表 category_budgets
//     - 共享剩余池:总额度 - 所有分类子额度总和 = 剩余池,未配置分类共享
//     - 周期:每月重置(按 year + month 联合唯一约束)
//
// Schema:
//   - id (autoIncrement, primary key)
//   - category_id (FK -> categories.id)
//   - year + month (联合唯一: 同一分类同月只能有一条子额度)
//   - amount (real, 子额度值,单位:元)
import 'package:drift/drift.dart';

import 'categories.dart';

class CategoryBudgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  RealColumn get amount => real()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// 同一分类同月只能有一条预算(否则多个子额度逻辑混乱)
  @override
  List<Set<Column>> get uniqueKeys => [
        {categoryId, year, month},
      ];
}
