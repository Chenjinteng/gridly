// lib/features/stats/ui/stats_page.dart
// 报表:视角 tabs (支出/收入/资产) → 时间范围 tabs → 汇总 → 内容
// 下拉刷新:广谱 invalidate 所有依赖 provider(流水 / 月度汇总 / 分类)
//
// 视角路由:
//   expense → 现有 CategoryPie + TopExpenses + MonthlyTrend
//   income  → 镜像 IncomePie(2026-10-11 UAT 新增)
//   assets  → 占位(UAT 时只是"留切换入口",内容后续)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import 'widgets/category_pie.dart';
import 'widgets/income_pie.dart';
import 'widgets/monthly_trend.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';
import 'widgets/stats_view_tabs.dart';
import 'widgets/top_expenses.dart';
import '../application/stats_providers.dart' hide MonthlyTrend;

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(statsViewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('报表')),
      body: RefreshIndicator(
        onRefresh: () async => refreshAllData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.s6),
          children: [
            // 视角切换:最顶(2026-10-11 新增)
            const StatsViewTabs(),
            // 时间范围(本月/本年)
            const RangeTabs(),
            // 汇总(收入/支出/结余)— 三个视角共享,因为它就是"窗口内总览"
            const RangeSummary(),
            const SizedBox(height: AppSpacing.s3),
            // 视角特定内容
            ..._viewContent(view),
          ],
        ),
      ),
    );
  }

  List<Widget> _viewContent(StatsView view) {
    switch (view) {
      case StatsView.expense:
        return const [
          CategoryPie(),
          SizedBox(height: AppSpacing.s3),
          TopExpenses(),
          SizedBox(height: AppSpacing.s3),
          MonthlyTrend(),
        ];
      case StatsView.income:
        return const [
          IncomePie(),
          SizedBox(height: AppSpacing.s3),
          MonthlyTrend(),
        ];
      case StatsView.assets:
        // 占位:用户 2026-10-11 只要求"先留切换按钮,内容先留空"
        // 等后续资产功能(账户余额 / 资产负债结构)落地时再替换
        return const [_AssetsPlaceholder()];
    }
  }
}

class _AssetsPlaceholder extends StatelessWidget {
  const _AssetsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s6,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: AppGray.g400,
            ),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              '资产结构',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s2),
            const Text(
              '即将上线',
              style: TextStyle(fontSize: 13, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}
