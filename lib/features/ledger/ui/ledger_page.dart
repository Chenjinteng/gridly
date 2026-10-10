// lib/features/ledger/ui/ledger_page.dart
// 流水(读):3 个下拉筛选(类型 / 月份 / 分类)+ 搜索 + 按日分组 ListView + 空状态
// 分类支持多选(OR 关系),弹 modal bottom sheet
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

/// 筛选条 —— 3 个 dropdown 按钮横向均分,点击弹 modal bottom sheet 单选/多选
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
  final Set<int> categoryFilter;
  final List<Category> catsForType;
  final List<int> monthKeys;
  final String Function(int) formatMonthKey;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<Set<int>> onCategoryChanged;

  String _typeLabel() {
    switch (typeFilter) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      default:
        return '全部';
    }
  }

  String _monthLabel() =>
      monthFilter == null ? '全部' : formatMonthKey(monthFilter!);

  String _categoryLabel() {
    if (categoryFilter.isEmpty) return '全部';
    if (categoryFilter.length == 1) {
      final id = categoryFilter.first;
      for (final c in catsForType) {
        if (c.id == id) return c.name;
      }
    }
    return '已选 ${categoryFilter.length} 个';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DropdownField(
              label: '类型',
              value: _typeLabel(),
              active: typeFilter != 'all',
              onTap: () => _showTypePicker(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _DropdownField(
              label: '月份',
              value: _monthLabel(),
              active: monthFilter != null,
              onTap: () => _showMonthPicker(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _DropdownField(
              label: '分类',
              value: _categoryLabel(),
              active: categoryFilter.isNotEmpty,
              onTap: () => _showCategoryPicker(context),
            ),
          ),
        ],
      ),
    );
  }

  // ============ 弹层:类型(单选) ============
  Future<void> _showTypePicker(BuildContext context) async {
    const options = [
      ('all', '全部'),
      ('expense', '支出'),
      ('income', '收入'),
    ];
    final selected = await _showSingleSelectSheet<String>(
      context,
      title: '选择类型',
      options: options,
      currentValue: typeFilter,
    );
    if (selected != null) onTypeChanged(selected);
  }

  // ============ 弹层:月份(单选) ============
  Future<void> _showMonthPicker(BuildContext context) async {
    final options = <(int?, String)>[
      (null, '全部'),
      ...monthKeys.map((k) => (k, formatMonthKey(k))),
    ];
    final selected = await _showSingleSelectSheet<int?>(
      context,
      title: '选择月份',
      options: options,
      currentValue: monthFilter,
    );
    if (selected != null) onMonthChanged(selected);
  }

  // ============ 弹层:分类(多选) ============
  Future<void> _showCategoryPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => _MultiSelectCategorySheet(
        categories: catsForType,
        initial: categoryFilter,
      ),
    );
    if (selected != null) onCategoryChanged(selected);
  }
}

/// 单选弹层(类型 / 月份)—— 选完自动关闭
Future<T?> _showSingleSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T currentValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final (value, label) = options[i];
                    final selected = value == currentValue;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                          vertical: AppSpacing.s3,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 多选弹层(分类)—— 临时持有选择集合,点"确定"才提交
class _MultiSelectCategorySheet extends StatefulWidget {
  const _MultiSelectCategorySheet({
    required this.categories,
    required this.initial,
  });
  final List<Category> categories;
  final Set<int> initial;

  @override
  State<_MultiSelectCategorySheet> createState() =>
      _MultiSelectCategorySheetState();
}

class _MultiSelectCategorySheetState
    extends State<_MultiSelectCategorySheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择分类(可多选)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.categories.length,
                itemBuilder: (_, i) {
                  final c = widget.categories[i];
                  final checked = _selected.contains(c.id);
                  final color = Color(c.color);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(c.id);
                      } else {
                        _selected.add(c.id);
                      }
                    }),
                    child: Container(
                      color: checked
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (checked)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppBrand.ink,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.brLg,
                    ),
                  ),
                  child: Text(
                    _selected.isEmpty
                        ? '显示全部'
                        : '确定(${_selected.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Dropdown 样式按钮:label + value + 下拉箭头
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.brMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
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