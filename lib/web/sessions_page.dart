// lib/web/sessions_page.dart
// LAN_WEB v2.0.0 P3 commit 6 已配对设备管理页
//
// 列出除自己外的所有 active session(label + createdAt + lastSeenAt),
// 每个有「撤销」按钮(二次确认)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, required this.api});

  final WebApiClient api;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = widget.api.listActiveSessions();
  }

  Future<void> _revoke(String token, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销设备?'),
        content: Text('"$label" 会被踢出,需要重新配对才能再访问。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.revokeSession(token);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已撤销 "$label"')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撤销失败:${e.errorCode}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('已配对设备'),
        centerTitle: false,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载失败:${snap.error}'),
              ),
            );
          }
          final sessions = snap.data!;
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.devices_other_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '只有你一个设备配对',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '其他设备用 6 位配对码配对后会出现在这里',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_refresh);
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = sessions[i];
                final token = s['token'] as String;
                final label = s['label'] as String? ?? 'Device';
                final createdAt = DateTime.parse(s['createdAt'] as String);
                final lastSeenAt = DateTime.parse(s['lastSeenAt'] as String);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _iconForLabel(label),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(label),
                    subtitle: Text(
                      '上次活跃 ${_formatRelative(lastSeenAt)}\n'
                      '配对于 ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt)}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: '撤销',
                      onPressed: () => _revoke(token, label),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('iphone') || l.contains('ios') || l.contains('phone')) {
      return Icons.smartphone_rounded;
    }
    if (l.contains('ipad') || l.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    }
    if (l.contains('mac') || l.contains('desktop')) {
      return Icons.computer_rounded;
    }
    if (l.contains('chrome') || l.contains('browser') || l.contains('web')) {
      return Icons.language_rounded;
    }
    if (l.contains('android')) {
      return Icons.android_rounded;
    }
    return Icons.devices_other_rounded;
  }

  String _formatRelative(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return DateFormat('yyyy-MM-dd').format(t);
  }
}
