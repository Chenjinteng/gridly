// lib/features/stats/ui/stats_page.dart
// 报表(P0 空壳) —— P2 实装:分类饼图 + 月度趋势折线
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('报表')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('P0 · 空壳', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s2),
            Text('报表(Stats)', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.s3),
            const Text('P2 实装:分类饼图 + 月度趋势折线(fl_chart)'),
          ],
        ),
      ),
    );
  }
}
