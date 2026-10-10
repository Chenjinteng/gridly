// lib/features/ledger/ui/ledger_page.dart
// 流水(读):按日分组 ListView + 空状态
// 月度汇总卡只放在首页(避免流水顶部冗余)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../application/transactions_providers.dart';
import 'widgets/transaction_tile.dart';

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupedAsync = ref.watch(allTransactionsByDayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('流水')),
      body: groupedAsync.when(
        data: (grouped) {
          if (grouped.isEmpty) {
            return const _EmptyState();
          }
          final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
          return ListView.builder(
            padding: const EdgeInsets.only(top: AppSpacing.s2, bottom: AppSpacing.s6),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final txs = grouped[day]!;
              return _DaySection(day: day, transactions: txs);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppBrand.teal.withValues(alpha: 0.1),
              borderRadius: AppRadius.brLg,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 36,
              color: AppBrand.teal,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          const Text('还没有流水', style: TextStyle(fontSize: 16)),
          const SizedBox(height: AppSpacing.s1),
          const Text(
            '点中央的"+"记一笔',
            style: TextStyle(color: AppGray.g600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.transactions});
  final DateTime day;
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final dailyExpense = transactions
        .where((t) => t.type == 'expense')
        .fold<double>(0, (sum, t) => sum + t.amount);
    final dailyIncome = transactions
        .where((t) => t.type == 'income')
        .fold<double>(0, (sum, t) => sum + t.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s1,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.dayHeader(day),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppGray.g600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  if (dailyIncome > 0)
                    Text(
                      '+¥${Formatters.amount(dailyIncome)} ',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppBrand.gold,
                      ),
                    ),
                  if (dailyExpense > 0)
                    Text(
                      '-¥${Formatters.amount(dailyExpense)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppStatus.error,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        ...transactions.map((t) => TransactionTile(transaction: t)),
      ],
    );
  }
}
