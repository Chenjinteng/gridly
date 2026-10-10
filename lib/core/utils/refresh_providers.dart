// lib/core/utils/refresh_providers.dart
// 广谱刷新 helper —— 一处 invalidate,所有依赖流水的 provider 同步更新
//
// 触发场景:
//   - 用户在记一页保存了一笔 → add_transaction_page 调用
//   - 用户在流水页长按删了一笔 → transaction_tile 调用
//   - 用户在任何页面下拉刷新 → RefreshIndicator 调用
//
// 涉及的页面:
//   - 流水页(allTransactionsByDayProvider / filteredTransactionsByDayProvider)
//   - 首页(月度汇总 monthTransactionsProvider)
//   - 报表(statsTransactionsProvider / expenseByCategoryProvider /
//     topExpensesProvider / monthlyTrendProvider)
//   - 分类页 / 关于页(allCategoriesProvider)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ledger/application/transactions_providers.dart';
import '../../features/stats/application/stats_providers.dart';

void refreshAllData(WidgetRef ref) {
  ref.invalidate(allTransactionsByDayProvider);
  ref.invalidate(filteredTransactionsByDayProvider);
  ref.invalidate(monthTransactionsProvider);
  ref.invalidate(statsTransactionsProvider);
  ref.invalidate(expenseByCategoryProvider);
  ref.invalidate(topExpensesProvider);
  ref.invalidate(monthlyTrendProvider);
  ref.invalidate(allCategoriesProvider);
}