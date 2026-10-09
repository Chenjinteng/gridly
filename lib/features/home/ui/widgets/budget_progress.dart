// lib/features/home/ui/widgets/budget_progress.dart
// 预算进度条:已花 / 预算,颜色按状态
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ledger/application/transactions_providers.dart';

class BudgetProgress extends ConsumerWidget {
  const BudgetProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(monthlyBudgetProvider);
    if (budget <= 0) return const SizedBox.shrink();
    final summary = ref.watch(monthSummaryProvider);
    final spent = summary.expense;
    final percent = (spent / budget).clamp(0.0, 1.5);
    final state = _status(spent, budget);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '本月预算',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Text(
                _statusText(state, percent),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor(state),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: AppGray.g200,
              valueColor: AlwaysStoppedAnimation<Color>(_statusColor(state)),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已花 ¥${Formatters.amount(spent)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '预算 ¥${Formatters.amount(budget)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppGray.g600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _BudgetState _status(double spent, double budget) {
    final p = spent / budget;
    if (p < 0.8) return _BudgetState.ok;
    if (p <= 1.0) return _BudgetState.warning;
    return _BudgetState.over;
  }

  Color _statusColor(_BudgetState s) {
    return switch (s) {
      _BudgetState.ok => AppBrand.teal,
      _BudgetState.warning => AppStatus.warning,
      _BudgetState.over => AppStatus.error,
    };
  }

  String _statusText(_BudgetState s, double percent) {
    final pct = (percent * 100).toStringAsFixed(0);
    return switch (s) {
      _BudgetState.ok => '已用 $pct%',
      _BudgetState.warning => '接近预算 $pct%',
      _BudgetState.over => '已超预算 $pct%',
    };
  }
}

enum _BudgetState { ok, warning, over }
