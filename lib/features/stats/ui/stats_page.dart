// lib/features/stats/ui/stats_page.dart
// 报表:AppBar(报表 title + 视角 dropdown)→ 时间范围 tabs → 汇总 → 内容
//
// 视角选择放在 AppBar 右端(2026-10-11 UAT:\"不要增加一个 row,放在
// 与报表 title 同一级别即可,用下拉\"),不占 body 高度。下拉选完
// 后正文自动 switch,眼睛也不用离开页面顶部。
//
// 下拉刷新:广谱 invalidate 所有依赖 provider(流水 / 月度汇总 / 分类)
//
// 视角路由:
//   expense → CategoryPie + TopExpenses + MonthlyTrend
//   income  → IncomePie + MonthlyTrend
//   assets  → 占位(2026-10-11 资产功能预留)
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
import 'widgets/top_expenses.dart';
import '../application/stats_providers.dart' hide MonthlyTrend;

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(statsViewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('报表'),
        actions: [
          // 视角下拉 —— 与 title 同一行(AppBar 右侧 actions)
          _ViewMenu(
            current: view,
            onChange: (v) =>
                ref.read(statsViewProvider.notifier).state = v,
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAllData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.s6),
          children: [
            // 时间范围(本月/本年) —— 现在是该页 body 的最顶
            const RangeTabs(),
            // 汇总(收入/支出/结余)— 三个视角共享(它是"窗口内总览")
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
        return const [_AssetsPlaceholder()];
    }
  }
}

/// AppBar 右侧的视角 dropdown
/// - 显示当前 view 文字 + expand_more icon(常驻可见)
/// - 点击弹出 3 项菜单,选中后 onChange 回调立刻更新 provider
/// - 这里不监听 widget 自身 rebuild 状态,current 是 build 参数,onChange
///   触发后父级 StatsPage 会因 watch 重新 build,current 自动同步
class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.current, required this.onChange});

  final StatsView current;
  final ValueChanged<StatsView> onChange;

  String get _currentLabel => switch (current) {
        StatsView.expense => '支出',
        StatsView.income => '收入',
        StatsView.assets => '资产',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<StatsView>(
      tooltip: '切换视角',
      initialValue: current,
      onSelected: onChange,
      itemBuilder: (_) => const [
        PopupMenuItem(value: StatsView.expense, child: Text('支出')),
        PopupMenuItem(value: StatsView.income, child: Text('收入')),
        PopupMenuItem(value: StatsView.assets, child: Text('资产')),
      ],
      // 用 child 自定义触发器:text + chevron,看起来像"标签下拉"
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
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
