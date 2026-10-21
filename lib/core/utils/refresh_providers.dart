// lib/core/utils/refresh_providers.dart
// 广谱刷新 helper —— 一处 invalidate,所有依赖流水的 provider 同步更新
//
// 触发场景:
//   - 用户在记一页保存了一笔 → add_transaction_page 调用
//   - 用户在流水页长按删了一笔 → transaction_tile 调用
//   - 用户在任何页面下拉刷新 → RefreshIndicator 调用
//   - 用户进入 stats tab → StatsPage.initState 主动调一次
//     (commit 84 加,防 Riverpod cache + 兜底打开报表那一刻拉最新)
//   - 用户在 BudgetSheet 配置 / 调整分类子额度 → BudgetSheet 调
//     (commit 91 加,family 的所有 month 都失效)
//
// 涉及的页面:
//   - 流水页(allTransactionsByDayProvider / filteredTransactionsByDayProvider)
//   - 首页(月度汇总 monthTransactionsProvider)
//   - 报表(statsTransactionsProvider / expenseByCategoryProvider /
//     topExpensesProvider / monthlyTrendProvider /
//     dailyExpenseTrendProvider / yearlyExpenseTrendProvider /
//     monthlyYoYProvider / yearlyYoYProvider / yearlyMonthlyTrendProvider /
//     categoryCompareProvider / weekdayExpenseProvider / expenseByAssetProvider)
//   - 分类页 / 关于页(allCategoriesProvider)
//   - 分类预算(categoryBudgetsForMonthProvider /
//     categoryBudgetUsageForMonthProvider / budgetOverviewForMonthProvider)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ledger/application/transactions_providers.dart';
import '../../features/stats/application/stats_providers.dart';
import 'asset_balance_provider.dart';
import 'budget_provider.dart';

void refreshAllData(WidgetRef ref) {
  ref.invalidate(allTransactionsByDayProvider);
  ref.invalidate(filteredTransactionsByDayProvider);
  ref.invalidate(monthTransactionsProvider);
  ref.invalidate(statsTransactionsProvider);
  ref.invalidate(expenseByCategoryProvider);
  // 2026-10-21 D64.92 补:Top 10 支出的「金额」「笔数」两个 tab 共用的 provider
  //   (之前叫 expenseByCategoryCountProvider,D64.92 改名并扩展成完整统计)
  ref.invalidate(expenseCategoryStatsProvider);
  ref.invalidate(topExpensesProvider);
  ref.invalidate(monthlyTrendProvider);
  // 2026-10-12 commit 84 补:之前漏了 commit 73 加的 dailyExpenseTrendProvider
  // (本月每日柱状图) + commit 78 加的 yearlyExpenseTrendProvider(本年 1-12 月
  // 柱状图),user 反馈"edit 了 7 月历史支出,12 月趋势没变"就是这两个 provider
  // 没 invalidate,继续用旧缓存。以后 stats 新增 bar / line chart provider
  // 也要同步加到这里。
  ref.invalidate(dailyExpenseTrendProvider);
  ref.invalidate(yearlyExpenseTrendProvider);
  // 2026-10-16 D64.83 补:D63 / D62.3 / D62.4 / D64.21d 加的 6 个 provider
  //   之前漏加,user 编辑流水后报表这些 dashboard 都用旧缓存(跟 commit 84
  //   同模式 bug 重复犯)
  //   - monthlyYoYProvider:range_summary 本月维度同比箭头
  //   - yearlyYoYProvider:range_summary 本年维度同比箭头
  //   - yearlyMonthlyTrendProvider:本年维度 1-12 月收入支出柱
  //   - categoryCompareProvider:类别对比卡(本月 vs 上月各类别)
  //   - weekdayExpenseProvider:周几支出 7 柱
  //   - expenseByAssetProvider:按支付账户支出圆环
  ref.invalidate(monthlyYoYProvider);
  ref.invalidate(yearlyYoYProvider);
  ref.invalidate(yearlyMonthlyTrendProvider);
  ref.invalidate(categoryCompareProvider);
  ref.invalidate(weekdayExpenseProvider);
  ref.invalidate(expenseByAssetProvider);
  ref.invalidate(allCategoriesProvider);
  // 2026-10-11 UAT bug fix:分类管理里 add/update/delete 后,记一笔页的分类
  // 选择器必须同步刷新;之前只 invalidate allCategoriesProvider,family 的
  // categoriesByTypeProvider 还是缓存,新分类选不到。
  ref.invalidate(categoriesByTypeProvider);
  // 2026-10-12 commit 91 补:分类预算 family provider
  //   - add/update/delete transaction 后,分类支出汇总变 → 必须 invalidate
  //     实际支出(usage)和预算总览(overview)
  //   - BudgetSheet 改完子额度 → invalidate budgets 和 overview
  ref.invalidate(categoryBudgetsForMonthProvider);
  ref.invalidate(categoryBudgetUsageForMonthProvider);
  ref.invalidate(budgetOverviewForMonthProvider);
  // 2026-10-12 commit 110 加:流水变动影响资产 currentBalance
  //   - add / update / delete 一笔 expense 或 income → 那个账户余额变
  //   - balance 类型流水(动资产但不算月度收支)也算变动 → 必加 invalidate
  ref.invalidate(assetBalancesProvider);
  ref.invalidate(assetBalanceProvider);
  ref.invalidate(assetTotalsProvider);
}
