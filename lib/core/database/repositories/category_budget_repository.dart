// lib/core/database/repositories/category_budget_repository.dart
// 分类月度预算 Repository —— 业务层唯一接触 CategoryBudgets DAO 的地方
//
// 2026-10-12 commit 90 加:
//   - 数据来源:CategoryBudgets 表(category_id, year, month, amount)
//   - 共享剩余池逻辑在 UI 层算,Repository 只负责存读
//   - 业务规则(已配置总额度不能超过月度总额度)在 BudgetSheet UI 层校验
import 'package:drift/drift.dart';

import '../app_database.dart';

class CategoryBudgetRepository {
  CategoryBudgetRepository(this._db);
  final AppDatabase _db;

  /// 取某年某月所有分类的子额度
  /// 返回 `Map<categoryId, amount>`,不在 Map 里的分类 = 没配置子额度
  Future<Map<int, double>> byMonth(int year, int month) async {
    final rows = await (_db.select(
      _db.categoryBudgets,
    )..where((b) => b.year.equals(year) & b.month.equals(month))).get();
    return {for (final b in rows) b.categoryId: b.amount};
  }

  /// Upsert(有就更新 amount / updatedAt,没有就 insert)
  /// 唯一约束 (category_id, year, month) 保证不会重复插入
  Future<void> upsert({
    required int categoryId,
    required int year,
    required int month,
    required double amount,
  }) async {
    final existing =
        await (_db.select(_db.categoryBudgets)..where(
              (b) =>
                  b.categoryId.equals(categoryId) &
                  b.year.equals(year) &
                  b.month.equals(month),
            ))
            .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(_db.categoryBudgets)
          .insert(
            CategoryBudgetsCompanion.insert(
              categoryId: categoryId,
              year: year,
              month: month,
              amount: amount,
            ),
          );
    } else {
      await (_db.update(
        _db.categoryBudgets,
      )..where((b) => b.id.equals(existing.id))).write(
        CategoryBudgetsCompanion(
          amount: Value(amount),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// 删除某年某月某分类的子额度
  /// amount=0 时由 UI 触发删除(回到共享池)
  Future<void> delete({
    required int categoryId,
    required int year,
    required int month,
  }) async {
    await (_db.delete(_db.categoryBudgets)..where(
          (b) =>
              b.categoryId.equals(categoryId) &
              b.year.equals(year) &
              b.month.equals(month),
        ))
        .go();
  }
}
