// lib/features/settings/ui/widgets/lan_web_modals.dart
// LAN_WEB v2.0.0 P2 配对码 / 已配对设备 modal
//
// - PairingCodeModal:展示当前 6 位配对码 + 倒计时 + 刷新 + 复制
// - SessionsModal:列出已配对 active sessions + 单独撤销
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/server/auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/server_controller.dart';

/// 6 位配对码 modal
///
/// 1 秒倒计时自动刷新 UI;过期 0 秒自动调 refreshPairingCode
class PairingCodeModal extends ConsumerStatefulWidget {
  const PairingCodeModal({super.key});

  @override
  ConsumerState<PairingCodeModal> createState() => _PairingCodeModalState();
}

class _PairingCodeModalState extends ConsumerState<PairingCodeModal> {
  Timer? _timer;
  PairingCode? _code;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_code != null) {
        setState(() {
          _remaining = _code!.remainingSeconds;
        });
        if (_remaining <= 0) {
          _refresh();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final c = ref.read(lanWebControllerProvider.notifier).refreshPairingCode();
    setState(() {
      _code = c;
      _remaining = c.remainingSeconds;
    });
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 把手
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.s3),
              decoration: BoxDecoration(
                color: AppGray.g200,
                borderRadius: AppRadius.brSm,
              ),
            ),
          ),
          const Text(
            '局域网配对码',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s1),
          const Text(
            '在浏览器输入这 6 位码,7 天内 cookie 有效',
            style: TextStyle(fontSize: 11, color: AppGray.g600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          // 6 位码
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s4,
              horizontal: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: AppBrand.teal.withValues(alpha: 0.06),
              borderRadius: AppRadius.brMd,
            ),
            child: Text(
              _code?.code ?? '------',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
                fontFamily: 'monospace',
                color: AppBrand.teal,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: AppGray.g600),
              const SizedBox(width: AppSpacing.s1),
              Text(
                '有效期还剩 ${_formatTime(_remaining)}',
                style: const TextStyle(fontSize: 12, color: AppGray.g600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              TextButton.icon(
                onPressed: _code == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: _code!.code));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制配对码'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('复制'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 已配对设备 modal
class SessionsModal extends ConsumerStatefulWidget {
  const SessionsModal({super.key});

  @override
  ConsumerState<SessionsModal> createState() => _SessionsModalState();
}

class _SessionsModalState extends ConsumerState<SessionsModal> {
  List<ActiveSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final list =
        ref.read(lanWebControllerProvider.notifier).listActiveSessions();
    if (mounted) {
      setState(() {
        _sessions = list;
        _loading = false;
      });
    }
  }

  Future<void> _revoke(String token) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销设备?'),
        content: const Text('该设备将立即失去访问权限,需重新配对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('撤销', style: TextStyle(color: AppStatus.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(lanWebControllerProvider.notifier).revokeSession(token);
      _load();
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.s3),
              decoration: BoxDecoration(
                color: AppGray.g200,
                borderRadius: AppRadius.brSm,
              ),
            ),
          ),
          const Text(
            '已配对设备',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s1),
          const Text(
            '7 天内无需重新配对,撤销后立即断连',
            style: TextStyle(fontSize: 11, color: AppGray.g600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.s4),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.s4),
              child: Text(
                '暂无已配对设备',
                style: TextStyle(fontSize: 12, color: AppGray.g600),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._sessions.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.s2),
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  decoration: BoxDecoration(
                    color: AppGray.g100,
                    borderRadius: AppRadius.brMd,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.devices,
                          size: 18, color: AppGray.g600),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '最后活动 ${_formatDateTime(s.lastSeenAt)} · 创于 ${_formatDateTime(s.createdAt)}',
                              style: const TextStyle(
                                  fontSize: 10, color: AppGray.g600),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _revoke(s.token),
                        style: TextButton.styleFrom(
                          foregroundColor: AppStatus.error,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s2),
                          minimumSize: const Size(48, 32),
                        ),
                        child: const Text('撤销',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}