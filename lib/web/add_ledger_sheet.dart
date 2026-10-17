// lib/web/add_ledger_sheet.dart
// LAN_WEB v2.0.0 P3 commit 5 记一笔 modal
//
// 字段:type (expense/income/balance) + category (按 type 过滤) +
//       amount + note + occurredAt (默认 now,可选改日期)
// 提交:POST /api/ledgers,成功关 modal + 回调 onSaved
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';

class AddLedgerSheet extends StatefulWidget {
  const AddLedgerSheet({
    super.key,
    required this.api,
    required this.categories,
    required this.onSaved,
  });

  final WebApiClient api;
  final List<Map<String, dynamic>> categories; // 父组件已拉好,避免二次请求
  final VoidCallback onSaved;

  @override
  State<AddLedgerSheet> createState() => _AddLedgerSheetState();
}

class _AddLedgerSheetState extends State<AddLedgerSheet> {
  String _type = 'expense';
  int? _categoryId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _occurredAt = DateTime.now();
  bool _busy = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    // 默认选第一个匹配 type 的分类
    _pickDefaultCategory();
  }

  void _pickDefaultCategory() {
    final filtered =
        widget.categories.where((c) => c['type'] == _type).toList();
    if (filtered.isNotEmpty) {
      _categoryId = filtered.first['id'] as int;
    } else {
      _categoryId = null;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMsg = '金额必须是大于 0 的数字');
      return;
    }
    if (_categoryId == null) {
      setState(() => _errorMsg = '请选择分类');
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await widget.api.createLedger(
        amount: amount,
        type: _type,
        categoryId: _categoryId!,
        occurredAt: _occurredAt,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } on ApiException catch (e) {
      setState(() => _errorMsg = '保存失败:${e.errorCode}');
    } catch (e) {
      setState(() => _errorMsg = '网络错误:$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCats =
        widget.categories.where((c) => c['type'] == _type).toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '记一笔',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            // Type segmented
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('支出'),
                  icon: Icon(Icons.arrow_upward_rounded),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('收入'),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
                ButtonSegment(
                  value: 'balance',
                  label: Text('余额'),
                  icon: Icon(Icons.account_balance_wallet_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (sel) {
                setState(() {
                  _type = sel.first;
                  _pickDefaultCategory();
                });
              },
            ),
            const SizedBox(height: 16),
            // Amount
            TextField(
              controller: _amountCtrl,
              enabled: !_busy,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // Category dropdown
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: '分类',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              isExpanded: true,
              items: filteredCats
                  .map((c) => DropdownMenuItem(
                        value: c['id'] as int,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Color(c['color'] as int),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(c['name'] as String),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            // Date picker
            InkWell(
              onTap: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _occurredAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setState(() {
                          _occurredAt = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            _occurredAt.hour,
                            _occurredAt.minute,
                          );
                        });
                      }
                    },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '日期',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today_rounded),
                ),
                child: Text(
                  DateFormat('yyyy-MM-dd HH:mm').format(_occurredAt),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Note
            TextField(
              controller: _noteCtrl,
              enabled: !_busy,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '备注(可选)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMsg!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_busy ? '保存中...' : '保存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
