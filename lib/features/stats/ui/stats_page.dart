// lib/features/stats/ui/stats_page.dart
// 报表:时间范围 Tab + 汇总 + 分类饼图 + 12 月趋势
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import 'widgets/category_pie.dart';
import 'widgets/monthly_trend.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('报表')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s6),
        children: const [
          RangeTabs(),
          RangeSummary(),
          SizedBox(height: AppSpacing.s3),
          CategoryPie(),
          SizedBox(height: AppSpacing.s3),
          MonthlyTrend(),
        ],
      ),
    );
  }
}
