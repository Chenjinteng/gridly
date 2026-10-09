// lib/features/stats/ui/widgets/range_tabs.dart
// 时间范围 Tab(本月 / 本年 / 全部)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../application/stats_providers.dart';

class RangeTabs extends ConsumerWidget {
  const RangeTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: SegmentedButton<StatsRange>(
        segments: const [
          ButtonSegment(value: StatsRange.thisMonth, label: Text('本月')),
          ButtonSegment(value: StatsRange.thisYear, label: Text('本年')),
          ButtonSegment(value: StatsRange.all, label: Text('全部')),
        ],
        selected: {range},
        onSelectionChanged: (s) {
          ref.read(statsRangeProvider.notifier).state = s.first;
        },
      ),
    );
  }
}
