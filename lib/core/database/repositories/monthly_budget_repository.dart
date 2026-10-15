// lib/core/database/repositories/monthly_budget_repository.dart
// 月度总额度 Repository —— 业务层唯一接触 MonthlyBudgets DAO 的地方
//
// 2026-10-15 D64.21b 加:跟 CategoryBudgetRepository(分类子额度)镜像结构,
//   区别是 MonthlyBudgets 存总额度(每月 1 行),不是分类子额度(N 分类 × M 月)。
//
// 设计要点:
//   - 双写来源:MonthlyBudgetNotifier 调 set(value) 时,同时落 SharedPreferences
//     和 monthly_budgets 表(当月)。SharedPreferences 保留 = 离线 fallback 快速读,
//     monthly_budgets 表 = 历史档案(给报表"全年预算管理" tab 用)。
//   - onConflict:doUpdate = (year, month) 联合唯一约束冲突时,update amount/updatedAt
//     而不是 abort。Drift 用 `mode: InsertMode.insertOrReplace` 或手写 upsert。
import 'package:drift/drift.dart';

import '../app_database.dart';

class MonthlyBudgetRepository {
  MonthlyBudgetRepository(this._db);
  final AppDatabase _db;

  /// 取某年 12 个月的总额度,缺失月份补 0(UI 层画图友好)
  Future<List<MonthlyBudgetEntry>> yearHistory(int year) async {
    final rows = await (_db.select(
      _db.monthlyBudgets,
    )..where((b) => b.year.equals(year))).get();
    final byMonth = {for (final r in rows) r.month: r};

    final out = <MonthlyBudgetEntry>[];
    for (var m = 1; m <= 12; m++) {
      final r = byMonth[m];
      out.add(
        MonthlyBudgetEntry(
          year: year,
          month: m,
          amount: r?.amount ?? 0,
        ),
      );
    }
    return out;
  }

  /// Upsert 某年某月的总额度
  /// 唯一约束 (year, month) 保证不会重复插入
  Future<void> upsert({
    required int year,
    required int month,
    required double amount,
  }) async {
    await _db
        .into(_db.monthlyBudgets)
        .insert(
          MonthlyBudgetsCompanion.insert(
            year: year,
            month: month,
            amount: amount,
            updatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// 查某年某月是否已有记录(给 MonthlyBudgetNotifier 启动回填当月用)
  Future<MonthlyBudgetEntry?> byMonth(int year, int month) async {
    final row = await (_db.select(_db.monthlyBudgets)..where(
          (b) => b.year.equals(year) & b.month.equals(month),
        ))
        .getSingleOrNull();
    if (row == null) return null;
    return MonthlyBudgetEntry(
      year: row.year,
      month: row.month,
      amount: row.amount,
    );
  }
}

/// 总额度按月 entry —— 返 UI 层画图/列表用
/// 跟 Drift 生成的 MonthlyBudget 数据类分开(那个带 id / updatedAt 等 DB 字段),
/// 这里只暴露报表需要的最小字段,防止 UI 层被 ORM 类绑定。
class MonthlyBudgetEntry {
  const MonthlyBudgetEntry({
    required this.year,
    required this.month,
    required this.amount,
  });
  final int year;
  final int month;
  final double amount;
}
