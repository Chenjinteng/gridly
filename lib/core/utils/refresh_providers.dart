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
import '../../features/settings/application/investment_providers.dart';
import 'asset_balance_provider.dart';
import 'budget_provider.dart';

// 2026-10-22 D64.93:核心刷新逻辑抽成 refreshAllDataWith(只依赖 invalidate 能力)
//   - WidgetRef / ProviderContainer 都有 invalidate,但两者类型不兼容
//     (Riverpod 2.6 的 WidgetRef **不** implements Ref),所以不能直接用 Ref 收口
//   - 抽出来后,这份"哪些 provider 必须刷"的清单**可以被单测直接验证** ——
//     D64.93 那个 bug 就是清单漏了 provider 这种静默错误,已经第三次犯了
//     (commit 84 / D64.83 / D64.93),没有测试就只能靠人肉发现
void refreshAllData(WidgetRef ref) => refreshAllDataWith(ref.invalidate);

/// 广谱刷新核心 —— 传一个 invalidate 回调即可(WidgetRef / ProviderContainer 都行)
void refreshAllDataWith(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(allTransactionsByDayProvider);
  invalidate(filteredTransactionsByDayProvider);
  invalidate(monthTransactionsProvider);
  // 2026-10-22 D64.93 补:transactionByIdProvider —— 编辑页取单笔流水用的
  //   之前漏在清单外 → provider 缓存里还是**编辑前**的对象,再打开编辑页显示旧金额
  //   (user UAT:32.5 改成 28,流水和资产都显示 28,但再开编辑页还是 32.5)
  //   这跟 commit 84 / D64.83 是同一个模式,第三次犯了。
  invalidate(transactionByIdProvider);
  // 2026-10-22 D64.93 补:investmentNetTotalProvider —— 投资看板的累计净收益
  //   它直接跑 SQL 聚合(repo.investmentAggregated()),**不 watch 任何流水 provider**
  //   → 不会级联刷新,编辑投资流水后累计净收益一直显示旧值
  //   (investmentMonthlyProvider 不用加:它 watch 了 allCategoriesProvider,
  //    allCategoriesProvider 在清单里 → 会自动级联重算,已实测确认)
  invalidate(investmentNetTotalProvider);
  invalidate(statsTransactionsProvider);
  invalidate(expenseByCategoryProvider);
  // 2026-10-21 D64.92 补:Top 10 支出的「金额」「笔数」两个 tab 共用的 provider
  //   (之前叫 expenseByCategoryCountProvider,D64.92 改名并扩展成完整统计)
  invalidate(expenseCategoryStatsProvider);
  invalidate(topExpensesProvider);
  invalidate(monthlyTrendProvider);
  // 2026-10-12 commit 84 补:之前漏了 commit 73 加的 dailyExpenseTrendProvider
  // (本月每日柱状图) + commit 78 加的 yearlyExpenseTrendProvider(本年 1-12 月
  // 柱状图),user 反馈"edit 了 7 月历史支出,12 月趋势没变"就是这两个 provider
  // 没 invalidate,继续用旧缓存。以后 stats 新增 bar / line chart provider
  // 也要同步加到这里。
  invalidate(dailyExpenseTrendProvider);
  invalidate(yearlyExpenseTrendProvider);
  // 2026-10-16 D64.83 补:D63 / D62.3 / D62.4 / D64.21d 加的 6 个 provider
  //   之前漏加,user 编辑流水后报表这些 dashboard 都用旧缓存(跟 commit 84
  //   同模式 bug 重复犯)
  //   - monthlyYoYProvider:range_summary 本月维度同比箭头
  //   - yearlyYoYProvider:range_summary 本年维度同比箭头
  //   - yearlyMonthlyTrendProvider:本年维度 1-12 月收入支出柱
  //   - categoryCompareProvider:类别对比卡(本月 vs 上月各类别)
  //   - weekdayExpenseProvider:周几支出 7 柱
  //   - expenseByAssetProvider:按支付账户支出圆环
  invalidate(monthlyYoYProvider);
  invalidate(yearlyYoYProvider);
  invalidate(yearlyMonthlyTrendProvider);
  invalidate(categoryCompareProvider);
  invalidate(weekdayExpenseProvider);
  invalidate(expenseByAssetProvider);
  invalidate(allCategoriesProvider);
  // 2026-10-11 UAT bug fix:分类管理里 add/update/delete 后,记一笔页的分类
  // 选择器必须同步刷新;之前只 invalidate allCategoriesProvider,family 的
  // categoriesByTypeProvider 还是缓存,新分类选不到。
  invalidate(categoriesByTypeProvider);
  // 2026-10-12 commit 91 补:分类预算 family provider
  //   - add/update/delete transaction 后,分类支出汇总变 → 必须 invalidate
  //     实际支出(usage)和预算总览(overview)
  //   - BudgetSheet 改完子额度 → invalidate budgets 和 overview
  invalidate(categoryBudgetsForMonthProvider);
  invalidate(categoryBudgetUsageForMonthProvider);
  invalidate(budgetOverviewForMonthProvider);
  // 2026-10-12 commit 110 加:流水变动影响资产 currentBalance
  //   - add / update / delete 一笔 expense 或 income → 那个账户余额变
  //   - balance 类型流水(动资产但不算月度收支)也算变动 → 必加 invalidate
  invalidate(assetBalancesProvider);
  invalidate(assetBalanceProvider);
  invalidate(assetTotalsProvider);
}
