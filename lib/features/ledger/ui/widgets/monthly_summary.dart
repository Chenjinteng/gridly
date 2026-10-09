// lib/features/ledger/ui/widgets/monthly_summary.dart
// 月度汇总三色块:结余 / 收入 / 支出
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/transactions_providers.dart';

class MonthlySummary extends ConsumerWidget {
  const MonthlySummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本月结余',
            style: TextStyle(color: AppGray.g400, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            '¥${Formatters.amount(summary.balance)}',
            style: const TextStyle(
              color: AppSecondary.cream,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Expanded(
                child: _Block(
                  label: '收入',
                  amount: summary.income,
                  color: AppBrand.gold,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: _Block(
                  label: '支出',
                  amount: summary.expense,
                  color: AppBrand.teal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s2,
        horizontal: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppGray.g400, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            '¥${Formatters.amount(amount)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
