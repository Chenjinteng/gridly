// lib/web/log_in_page.dart
// LAN_WEB v2.0.0 P3 commit 3 log in 页
//
// 6 位配对码输入 + POST /api/auth/pair + 成功后 callback
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

class LogInPage extends StatefulWidget {
  const LogInPage({super.key, required this.api, required this.onSuccess});

  final WebApiClient api;
  final VoidCallback onSuccess; // 配对成功后回调(切到主页)

  @override
  State<LogInPage> createState() => _LogInPageState();
}

class _LogInPageState extends State<LogInPage> {
  final _codeCtrl = TextEditingController();
  final _labelCtrl =
      TextEditingController(text: 'Web Browser'); // device label fallback
  bool _busy = false;
  String? _errorMsg;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMsg = '配对码必须是 6 位数字');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await widget.api.pairWithCode(code, label: _labelCtrl.text.trim());
      if (!mounted) return;
      widget.onSuccess();
    } on ApiException catch (e) {
      setState(() => _errorMsg = _errorText(e.errorCode));
    } catch (e) {
      setState(() => _errorMsg = '网络错误:$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(String code) {
    switch (code) {
      case 'invalid_or_expired':
        return '配对码错或已过期(5 分钟有效)。请在 gridly app 重新看码。';
      case 'invalid_code_format':
        return '配对码格式错,应该是 6 位数字。';
      case 'rate_limited':
        return '请求太快,被限流。请稍后再试。';
      default:
        return '配对失败:$code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('gridly · 局域网伴侣端'),
        centerTitle: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '连接到 gridly',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '在 gridly app 的「设置 → 局域网」页面看 6 位配对码,',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _codeCtrl,
                          enabled: !_busy,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontFamily: 'monospace',
                            letterSpacing: 8,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            labelText: '6 位配对码',
                            hintText: '000000',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _labelCtrl,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: '设备名(可选)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(_busy ? '配对中...' : '配对'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        if (_errorMsg != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
