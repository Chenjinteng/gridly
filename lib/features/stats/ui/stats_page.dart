// lib/features/stats/ui/stats_page.dart
// 报表:时间范围 Tab + 汇总 + 分类饼图 + 12 月趋势
// 下拉刷新:广谱 invalidate 所有依赖 provider(流水 / 月度汇总 / 分类)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import 'widgets/category_pie.dart';
import 'widgets/monthly_trend.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';
import 'widgets/top_expenses.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('报表')),
      body: RefreshIndicator(
        onRefresh: () async => refreshAllData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.s6),
          children: const [
            RangeTabs(),
            RangeSummary(),
            SizedBox(height: AppSpacing.s3),
            CategoryPie(),
            SizedBox(height: AppSpacing.s3),
            TopExpenses(),
            SizedBox(height: AppSpacing.s3),
            MonthlyTrend(),
          ],
        ),
      ),
    );
  }
}
