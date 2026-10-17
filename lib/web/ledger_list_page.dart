// lib/web/ledger_list_page.dart
// LAN_WEB v2.0.0 P3 commit 4 ledger list + 月度汇总卡片(真实数据)
// P3 commit 5:加记一笔 FAB → showModalBottomSheet
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'add_ledger_sheet.dart';
import 'api_client.dart';
import 'sessions_page.dart';

class LedgerListPage extends StatefulWidget {
  const LedgerListPage({super.key, required this.api, required this.onLogout});

  final WebApiClient api;
  final VoidCallback onLogout;

  @override
  State<LedgerListPage> createState() => _LedgerListPageState();
}

class _LedgerListPageState extends State<LedgerListPage> {
  late Future<_LedgerData> _future;
  _LedgerData? _lastData; // 最近一次成功加载的数据(给 FAB 用)
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _refresh();
  }

  void _refresh() {
    _future = _load();
  }

  Future<_LedgerData> _load() async {
    // 并行拉 3 个:流水 + 分类 + 月度汇总
    final results = await Future.wait([
      widget.api.listLedgers(pageSize: 100),
      widget.api.listCategories(),
      widget.api.monthlyStats(_year, _month),
    ]);
    return _LedgerData(
      ledgers: results[0] as List<Map<String, dynamic>>,
      categories: results[1] as List<Map<String, dynamic>>,
      monthly: results[2] as Map<String, dynamic>,
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month > 12) {
        _month = 1;
        _year++;
      } else if (_month < 1) {
        _month = 12;
        _year--;
      }
    });
    _refresh();
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (!mounted) return;
    widget.onLogout();
  }

  Future<void> _openAddSheet(_LedgerData data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (ctx) => AddLedgerSheet(
        api: widget.api,
        categories: data.categories,
        onSaved: () {
          // 保存成功,刷新当前数据
          if (mounted) setState(_refresh);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('gridly · 流水'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.devices_other_rounded),
            tooltip: '已配对设备',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionsPage(api: widget.api),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: '注销',
            onPressed: _logout,
          ),
        ],
      ),
      body: FutureBuilder<_LedgerData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              error: snap.error.toString(),
              onRetry: () => setState(_refresh),
            );
          }
          final data = snap.data!;
          _lastData = data; // cache for FAB
          final catMap = {
            for (final c in data.categories) c['id'] as int: c,
          };
          return RefreshIndicator(
            onRefresh: () async {
              setState(_refresh);
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MonthPicker(
                  year: _year,
                  month: _month,
                  onPrev: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                const SizedBox(height: 12),
                _MonthlyCard(monthly: data.monthly),
                const SizedBox(height: 16),
                Text(
                  '流水(${data.ledgers.length} 条)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (data.ledgers.isEmpty)
                  const _EmptyHint()
                else
                  ...data.ledgers.map((l) => _LedgerTile(
                        ledger: l,
                        category: catMap[l['categoryId'] as int?],
                      )),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _lastData != null
          ? FloatingActionButton.extended(
              onPressed: () => _openAddSheet(_lastData!),
              icon: const Icon(Icons.add_rounded),
              label: const Text('记一笔'),
            )
          : null,
    );
  }
}

/// 月份选择器(上 / 下月份切换)
class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.year,
    required this.month,
    required this.onPrev,
    required this.onNext,
  });
  final int year;
  final int month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = year == now.year && month == now.month;
    final label = '$year 年 $month 月';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: onPrev,
            ),
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: isCurrentMonth ? null : onNext,
            ),
          ],
        ),
      ),
    );
  }
}

/// 月度汇总卡片
class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.monthly});
  final Map<String, dynamic> monthly;

  @override
  Widget build(BuildContext context) {
    final income = (monthly['income'] as num?)?.toDouble() ?? 0;
    final expense = (monthly['expense'] as num?)?.toDouble() ?? 0;
    final balance = (monthly['balance'] as num?)?.toDouble() ?? 0;
    final txCount = monthly['transactionCount'] as int? ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本月汇总',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _StatItem(
                  label: '收入',
                  value: income,
                  color: Colors.green.shade700,
                  icon: Icons.arrow_downward_rounded,
                )),
                Expanded(child: _StatItem(
                  label: '支出',
                  value: expense,
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.arrow_upward_rounded,
                )),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatItem(
                  label: '结余',
                  value: balance,
                  color: balance >= 0
                      ? Colors.blue.shade700
                      : Theme.of(context).colorScheme.error,
                  icon: Icons.account_balance_wallet_rounded,
                )),
                Expanded(child: _StatItem(
                  label: '笔数',
                  value: txCount.toDouble(),
                  isInt: true,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  icon: Icons.receipt_long_rounded,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isInt = false,
  });
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool isInt;

  @override
  Widget build(BuildContext context) {
    final display = isInt
        ? value.toInt().toString()
        : '¥${value.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          display,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

/// 单条流水 tile
class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.ledger, required this.category});
  final Map<String, dynamic> ledger;
  final Map<String, dynamic>? category;

  @override
  Widget build(BuildContext context) {
    final amount = (ledger['amount'] as num).toDouble();
    final type = ledger['type'] as String;
    final isExpense = type == 'expense';
    final color = isExpense ? Theme.of(context).colorScheme.error : Colors.green.shade700;
    final sign = isExpense ? '-' : '+';
    final occurredAt = DateTime.parse(ledger['occurredAt'] as String);
    final note = ledger['note'] as String? ?? '';
    final catColor = category != null ? Color(category!['color'] as int) : Colors.grey;
    final catName = category?['name'] as String? ?? '(未知分类)';
    final catIconKey = category?['icon'] as String? ?? 'category_outlined';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: catColor.withValues(alpha: 0.15),
          child: Icon(_iconFor(catIconKey), color: catColor, size: 20),
        ),
        title: Text(
          catName,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        subtitle: note.isNotEmpty
            ? Text(note, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign¥${amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              DateFormat('MM-dd HH:mm').format(occurredAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String key) {
    // 跟 gridly 移动端 CategoryIcons 一一对齐
    switch (key) {
      case 'restaurant': return Icons.restaurant_rounded;
      case 'directions_bus': return Icons.directions_bus_rounded;
      case 'shopping_bag': return Icons.shopping_bag_rounded;
      case 'home': return Icons.home_rounded;
      case 'medical_services': return Icons.medical_services_rounded;
      case 'school': return Icons.school_rounded;
      case 'sports_esports': return Icons.sports_esports_rounded;
      case 'flight': return Icons.flight_rounded;
      case 'pets': return Icons.pets_rounded;
      case 'celebration': return Icons.celebration_rounded;
      case 'work': return Icons.work_rounded;
      case 'redeem': return Icons.redeem_rounded;
      case 'savings': return Icons.savings_rounded;
      case 'card_giftcard': return Icons.card_giftcard_rounded;
      case 'handshake': return Icons.handshake_rounded;
      case 'more_horiz': return Icons.more_horiz_rounded;
      case 'category_outlined': return Icons.category_outlined;
      default: return Icons.circle_outlined;
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '本月还没有流水',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '在 gridly app 里记一笔,这里就能看到',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerData {
  _LedgerData({
    required this.ledgers,
    required this.categories,
    required this.monthly,
  });
  final List<Map<String, dynamic>> ledgers;
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic> monthly;
}
