// lib/core/utils/budget_provider.dart
// 月度预算 Provider(SharedPreferences 持久化总额度 + 数据库存分类子额度)
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/providers.dart';
import '../database/repositories/monthly_budget_repository.dart';

const _kBudgetKey = 'monthly_budget';

/// 2026-10-12 commit 90 加:分类月度预算
///   - SharedPreferences 存"总额度"(原有)
///   - 数据库 CategoryBudgets 表存"分类子额度"(新)
///   - 共享剩余池 = 总额度 - 所有已配置分类子额度总和,所有未配置分类共享这个池
///
/// 2026-10-15 D64.21b 改:MonthlyBudgetNotifier 双写 SharedPreferences + monthly_budgets
///   - 总额度不再只存 SharedPreferences 单值,每次 set 时按 (year, month) 同时
///     落 monthly_budgets 表,作为"全年预算管理"报表的历史数据源。
///   - 启动时读 SharedPreferences,如果当月 monthly_budgets 没记录 → 补一条
///     (老 user 升级时 onUpgrade v7→v8 不回填历史,D64.21a 设计决定只在启动
///     时由本 notifier 兜底回填当月 1 行,避免历史月份幻觉数据)。

class MonthlyBudgetNotifier extends StateNotifier<double> {
  MonthlyBudgetNotifier(this._ref) : super(0) {
    _loadFromDisk();
  }

  final Ref _ref;

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_kBudgetKey) ?? 0;
    if (value != state) state = value;

    // D64.21b:老 user 升级兜底 —— 当月 SharedPreferences 已有值但
    // monthly_budgets 表没记录时,补一条当月行(避免报表"全年预算" tab
    // 当月显示 0 但 home 顶部"还剩 ¥X"又显示有预算的不一致)。
    if (value > 0) {
      final repo = _ref.read(monthlyBudgetRepositoryProvider);
      final now = DateTime.now();
      final existing = await repo.byMonth(now.year, now.month);
      if (existing == null) {
        await repo.upsert(year: now.year, month: now.month, amount: value);
      }
    }
  }

  Future<void> set(double value) async {
    final normalized = value < 0 ? 0.0 : value;
    if (normalized == state) return;
    state = normalized;

    // 写 SharedPreferences(快读 + 离线 fallback)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBudgetKey, state);

    // D64.21b:同时落 monthly_budgets 表当月行 —— "全年预算" tab 历史数据源
    final repo = _ref.read(monthlyBudgetRepositoryProvider);
    final now = DateTime.now();
    await repo.upsert(year: now.year, month: now.month, amount: state);
  }
}

final monthlyBudgetProvider =
    StateNotifierProvider<MonthlyBudgetNotifier, double>((ref) {
      return MonthlyBudgetNotifier(ref);
    });

/// 分类预算 — 单分类的 summary
///   - 配置了子额度(isConfigured=true):amount = 该分类子额度
///   - 没配置(isConfigured=false):amount=0,共享池在 BudgetOverview 里看
class CategoryBudgetSummary {
  const CategoryBudgetSummary({
    required this.category,
    required this.amount,
    required this.spent,
  });

  final Category category;
  final double amount; // 子额度(0 = 没配置)
  final double spent; // 当月实际支出

  bool get isConfigured => amount > 0;
  double get remaining => amount - spent;
  double get progress => amount > 0 ? (spent / amount).clamp(0.0, 1.5) : 0.0;
}

/// 预算总览(给 BudgetSheet UI 用)
///   - totalBudget 总额度(SharedPreferences)
///   - allocated 已配置分类子额度总和
///   - poolRemaining 共享剩余池 = totalBudget - allocated
///   - unconfiguredSpent 未配置分类支出总和(从共享池里扣)
///   - items 每个分类的 summary
class BudgetOverview {
  const BudgetOverview({
    required this.totalBudget,
    required this.allocated,
    required this.poolRemaining,
    required this.unconfiguredSpent,
    required this.items,
  });

  final double totalBudget;
  final double allocated;
  final double poolRemaining;
  final double unconfiguredSpent;
  final List<CategoryBudgetSummary> items;

  /// 已配置分类(子额度 > 0)
  List<CategoryBudgetSummary> get configuredItems =>
      items.where((i) => i.isConfigured).toList();

  /// 未配置分类(共享剩余池)
  List<CategoryBudgetSummary> get unconfiguredItems =>
      items.where((i) => !i.isConfigured).toList();

  /// 共享池进度(未配置分类总支出 / 剩余池)
  double get poolProgress => poolRemaining > 0
      ? (unconfiguredSpent / poolRemaining).clamp(0.0, 1.5)
      : 0.0;
}

/// 一个月(year, month) 的查询 key —— family 用
class BudgetMonthKey {
  const BudgetMonthKey(this.year, this.month);
  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is BudgetMonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// 某年某月所有分类子额度(categoryId → amount)
final categoryBudgetsForMonthProvider =
    FutureProvider.family<Map<int, double>, BudgetMonthKey>((ref, key) async {
      final repo = ref.watch(categoryBudgetRepositoryProvider);
      return repo.byMonth(key.year, key.month);
    });

/// 某年某月所有分类的实际支出(categoryId → spent)
/// 共享 statsTransactionsProvider 的 statsWindowProvider? 不,这里是按"自然月"
/// 不是 stats 的 statsWindowProvider(后者可能选自定义月份)。直接按 (year, month)
/// 查数据库更直观。
final categoryBudgetUsageForMonthProvider =
    FutureProvider.family<Map<int, double>, BudgetMonthKey>((ref, key) async {
      final db = ref.watch(databaseProvider);
      final start = DateTime(key.year, key.month, 1);
      final end = DateTime(
        key.year,
        key.month + 1,
        1,
      ).subtract(const Duration(seconds: 1));
      final txs =
          await (db.select(db.transactions)..where(
                (t) =>
                    t.occurredAt.isBetweenValues(start, end) &
                    t.type.equals('expense'),
              ))
              .get();
      final byCategory = <int, double>{};
      for (final t in txs) {
        byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
      }
      return byCategory;
    });

/// 某年某月所有分类列表(按 type=expense + sortOrder 升序)
final expenseCategoriesForBudgetProvider =
    FutureProvider.family<List<Category>, BudgetMonthKey>((ref, _) async {
      final repo = ref.watch(categoryRepositoryProvider);
      return repo.byType('expense');
    });

/// 某年某月预算总览(给 BudgetSheet UI 用)
final budgetOverviewForMonthProvider =
    FutureProvider.family<BudgetOverview, BudgetMonthKey>((ref, key) async {
      final totalBudget = ref.watch(monthlyBudgetProvider);
      final budgets = await ref.watch(
        categoryBudgetsForMonthProvider(key).future,
      );
      final usage = await ref.watch(
        categoryBudgetUsageForMonthProvider(key).future,
      );
      final categories = await ref.watch(
        expenseCategoriesForBudgetProvider(key).future,
      );

      final items = categories
          .map(
            (c) => CategoryBudgetSummary(
              category: c,
              amount: budgets[c.id] ?? 0,
              spent: usage[c.id] ?? 0,
            ),
          )
          .toList();

      // 共享剩余池 = 总额度 - 已配置分类子额度总和
      final allocated = items
          .where((i) => i.isConfigured)
          .fold<double>(0.0, (sum, i) => sum + i.amount);
      final poolRemaining = (totalBudget - allocated).clamp(
        0.0,
        double.infinity,
      );
      final unconfiguredSpent = items
          .where((i) => !i.isConfigured)
          .fold<double>(0.0, (sum, i) => sum + i.spent);

      return BudgetOverview(
        totalBudget: totalBudget,
        allocated: allocated,
        poolRemaining: poolRemaining,
        unconfiguredSpent: unconfiguredSpent,
        items: items,
      );
    });

/// 2026-10-15 D64.21b 加:某年 12 月总额度历史 —— 报表"全年预算" tab 数据源
///   - 返 `List<MonthlyBudgetEntry>` (12 项,缺失月 amount=0)
///   - family 参数 = year(由 caller `statsCustomYearProvider` 传入)
final monthlyBudgetHistoryProvider =
    FutureProvider.family<List<MonthlyBudgetEntry>, int>((ref, year) async {
  final repo = ref.watch(monthlyBudgetRepositoryProvider);
  return repo.yearHistory(year);
});
