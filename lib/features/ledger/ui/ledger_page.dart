// lib/features/ledger/ui/ledger_page.dart
// 流水(读):筛选 chip 行 + 按日分组 ListView + 空状态
//   - 类型筛选(全部/支出/收入)
//   - 月份筛选(全部 + 最近 12 月)
//   - 分类筛选(根据类型动态列出)
//   - 搜索关键字(匹配 note 和分类名)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../application/transactions_providers.dart';
import 'widgets/transaction_tile.dart';

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        ref.read(ledgerSearchQueryProvider.notifier).state = '';
      }
    });
  }

  /// 最近 12 个月(含本月),按时间倒序
  static List<int> _recentMonthKeys() {
    final now = DateTime.now();
    final list = <int>[];
    var y = now.year;
    var m = now.month;
    for (var i = 0; i < 12; i++) {
      list.add(y * 100 + m);
      m--;
      if (m == 0) {
        m = 12;
        y--;
      }
    }
    return list;
  }

  static String _formatMonthKey(int key) {
    final y = key ~/ 100;
    final m = key % 100;
    return '$y 年 $m 月';
  }

  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredTransactionsByDayProvider);
    final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final typeFilter = ref.watch(ledgerTypeFilterProvider);
    final monthFilter = ref.watch(ledgerMonthFilterProvider);
    final categoryFilter = ref.watch(ledgerCategoryFilterProvider);

    final catsForType = typeFilter == 'all'
        ? allCats
        : allCats.where((c) => c.type == typeFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜备注 / 分类',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppGray.g400),
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (v) =>
                    ref.read(ledgerSearchQueryProvider.notifier).state = v,
              )
            : const Text('流水'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            typeFilter: typeFilter,
            monthFilter: monthFilter,
            categoryFilter: categoryFilter,
            catsForType: catsForType,
            monthKeys: _recentMonthKeys(),
            formatMonthKey: _formatMonthKey,
            onTypeChanged: (v) =>
                ref.read(ledgerTypeFilterProvider.notifier).state = v,
            onMonthChanged: (v) =>
                ref.read(ledgerMonthFilterProvider.notifier).state = v,
            onCategoryChanged: (v) =>
                ref.read(ledgerCategoryFilterProvider.notifier).state = v,
          ),
          Expanded(
            child: filteredAsync.when(
              data: (grouped) {
                if (grouped.isEmpty) {
                  return _EmptyState(searching: _searching);
                }
                final days = grouped.keys.toList()
                  ..sort((a, b) => b.compareTo(a));
                return ListView.builder(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.s2, bottom: AppSpacing.s6),
                  itemCount: days.length,
                  itemBuilder: (context, i) {
                    final day = days[i];
                    final txs = grouped[day]!;
                    return _DaySection(day: day, transactions: txs);
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败:$e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// 筛选 chip bar —— 类型 / 月份 / 分类 三段,横向滚动
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.typeFilter,
    required this.monthFilter,
    required this.categoryFilter,
    required this.catsForType,
    required this.monthKeys,
    required this.formatMonthKey,
    required this.onTypeChanged,
    required this.onMonthChanged,
    required this.onCategoryChanged,
  });

  final String typeFilter;
  final int? monthFilter;
  final int? categoryFilter;
  final List<Category> catsForType;
  final List<int> monthKeys;
  final String Function(int) formatMonthKey;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<int?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s2,
        ),
        child: Row(
          children: [
            // 类型
            ..._buildTypeChips(context),
            const _Divider(),
            // 月份
            ..._buildMonthChips(context),
            const _Divider(),
            // 分类
            ..._buildCategoryChips(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTypeChips(BuildContext context) {
    const items = [
      ('all', '全部'),
      ('expense', '支出'),
      ('income', '收入'),
    ];
    return items
        .map((e) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s1),
              child: _chip(
                context,
                label: e.$2,
                selected: typeFilter == e.$1,
                onTap: () => onTypeChanged(e.$1),
              ),
            ))
        .toList();
  }

  List<Widget> _buildMonthChips(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s1),
        child: _chip(
          context,
          label: '全部月份',
          selected: monthFilter == null,
          onTap: () => onMonthChanged(null),
        ),
      ),
      for (final key in monthKeys)
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s1),
          child: _chip(
            context,
            label: formatMonthKey(key),
            selected: monthFilter == key,
            onTap: () => onMonthChanged(key),
          ),
        ),
    ];
  }

  List<Widget> _buildCategoryChips(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.only(right: AppSpacing.s1),
        child: _chip(
          context,
          label: '全部分类',
          selected: categoryFilter == null,
          onTap: () => onCategoryChanged(null),
        ),
      ),
      for (final c in catsForType)
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s1),
          child: _chip(
            context,
            label: c.name,
            selected: categoryFilter == c.id,
            onTap: () => onCategoryChanged(c.id),
            leadingColor: Color(c.color),
          ),
        ),
    ];
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? leadingColor,
  }) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerLow;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1 + 2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brLg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: leadingColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      child: Container(
        width: 0.5,
        height: 16,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});
  final bool searching;

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
            child: Icon(
              searching ? Icons.search_off_outlined : Icons.inbox_outlined,
              size: 36,
              color: AppBrand.teal,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            searching ? '没找到匹配的流水' : '还没有流水',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            searching ? '试试其他筛选条件' : '点中央的"+"记一笔',
            style: const TextStyle(color: AppGray.g600, fontSize: 12),
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