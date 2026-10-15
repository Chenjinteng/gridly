// lib/core/database/tables/monthly_budgets.dart
// 月度总额度历史表 —— 给报表"全年预算管理" tab 提供按月总额度数据
//
// 2026-10-15 D64.21a 加:user UAT 反馈"全年报表要展示 12 个月的预算走势",
//   当前总额度只存 SharedPreferences 单值('monthly_budget'),没有 (year, month) 历史。
//   - 跟 CategoryBudgets(分类子额度)的区别:
//     - CategoryBudgets:每个分类每个月的子额度,共 N×12 行
//     - MonthlyBudgets:每个月一个总额度,共 12 行/年
//   - 跟 SharedPreferences 的关系:
//     - SharedPreferences 单值保持不动,作为"当月快速读 + 离线 fallback"
//     - MonthlyBudgets 表作为历史档案,每次 set 总额度时双写
//   - onUpgrade v7 → v8:createTable + 启动时 SharedPreferences 兜底回填当月 1 行
//     (老 user 升级时没有历史月份数据,只把现值落当月,避免幻觉回填)
//
// Schema:
//   - id (autoIncrement, primary key)
//   - year + month (联合唯一: 同一月只能有一条总额度)
//   - amount (real, 月度总额度,单位:元)
//   - updatedAt (datetime, 最后一次落库时间)
import 'package:drift/drift.dart';

class MonthlyBudgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  RealColumn get amount => real()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// 同一月只能有一条总额度(set 时按 (year, month) upsert)
  @override
  List<Set<Column>> get uniqueKeys => [
    {year, month},
  ];
}
