// lib/features/stats/ui/widgets/range_summary.dart
// 当前时间窗的汇总(收入/支出/结余 三色块)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class RangeSummary extends ConsumerWidget {
  const RangeSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSummaryProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: '收入',
              amount: s.income,
              color: AppBrand.gold,
            ),
          ),
          Container(width: 1, height: 32, color: AppGray.g600),
          Expanded(
            child: _Stat(
              label: '支出',
              amount: s.expense,
              color: AppBrand.teal,
            ),
          ),
          Container(width: 1, height: 32, color: AppGray.g600),
          Expanded(
            child: _Stat(
              label: '结余',
              amount: s.balance,
              color: AppSecondary.cream,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppGray.g400, fontSize: 11),
        ),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            '¥${Formatters.amount(amount)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
