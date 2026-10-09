// lib/features/home/ui/home_page.dart
// 首页:本月汇总 + 最近 5 条流水 + 下拉刷新
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../ledger/application/transactions_providers.dart';
import '../../ledger/ui/widgets/monthly_summary.dart';
import '../../ledger/ui/widgets/transaction_tile.dart';
import 'widgets/budget_progress.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('格子记账'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(monthTransactionsProvider);
          ref.invalidate(allTransactionsByDayProvider);
          ref.invalidate(allCategoriesProvider);
        },
        child: ListView(
          children: const [
            MonthlySummary(),
            SizedBox(height: AppSpacing.s2),
            BudgetProgress(),
            _RecentHeader(),
            _RecentList(),
            SizedBox(height: AppSpacing.s6),
          ],
        ),
      ),
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s1,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '最近',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupedAsync = ref.watch(allTransactionsByDayProvider);
    return groupedAsync.when(
      data: (grouped) {
        if (grouped.isEmpty) {
          return const _EmptyHint();
        }
        final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
        final recent = <Transaction>[];
        for (final d in days) {
          recent.addAll(grouped[d]!);
          if (recent.length >= 5) break;
        }
        return Column(
          children: recent
              .take(5)
              .map((t) => TransactionTile(transaction: t))
              .toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.s6),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Text(
          '加载失败:$e',
          style: const TextStyle(color: AppStatus.error),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppBrand.teal.withValues(alpha: 0.1),
                borderRadius: AppRadius.brLg,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 32,
                color: AppBrand.teal,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            const Text('还没有流水', style: TextStyle(fontSize: 14)),
            const SizedBox(height: AppSpacing.s1),
            const Text(
              '点中央 + 记第一笔',
              style: TextStyle(fontSize: 12, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}
