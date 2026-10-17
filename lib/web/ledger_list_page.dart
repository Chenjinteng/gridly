// lib/web/ledger_list_page.dart
// LAN_WEB v2.0.0 P3 commit 3 ledger list 占位页
//
// P3 commit 4 会接 /api/ledgers 真实数据;现在先显示连接成功 + log out
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class LedgerListPage extends StatefulWidget {
  const LedgerListPage({super.key, required this.api, required this.onLogout});

  final WebApiClient api;
  final VoidCallback onLogout;

  @override
  State<LedgerListPage> createState() => _LedgerListPageState();
}

class _LedgerListPageState extends State<LedgerListPage> {
  late Future<Map<String, dynamic>> _healthFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _healthFuture = widget.api.health();
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (!mounted) return;
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('gridly · 流水'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.devices_other_rounded),
            tooltip: '已配对设备',
            onPressed: () {
              // P3 commit 6 接管
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: '注销',
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '已配对到 gridly',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '当前时间 $dateStr',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FutureBuilder<Map<String, dynamic>>(
                  future: _healthFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (snap.hasError) {
                      return Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '获取 server 信息失败:${snap.error}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      );
                    }
                    final h = snap.data!;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Server 状态',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _kv(context, '版本', 'v${h['version']}+${h['build']}'),
                            _kv(context, '阶段', h['phase']?.toString() ?? '?'),
                            _kv(context, 'DB schema', h['dbSchemaVersion']?.toString() ?? '?'),
                            _kv(context, '流水条数', h['transactions']?.toString() ?? '?'),
                            _kv(context, '分类数', h['categories']?.toString() ?? '?'),
                            _kv(context, '资产数', h['assets']?.toString() ?? '?'),
                            _kv(context, '已运行', '${h['uptimeSeconds']} 秒'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'P3 commit 4 会在这里加流水列表 + 月度汇总卡片',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(v, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
