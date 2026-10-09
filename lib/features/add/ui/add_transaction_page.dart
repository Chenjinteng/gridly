// lib/features/add/ui/add_transaction_page.dart
// 记一笔 —— 类型切换 / 金额大字号 / 分类网格 / 备注 / 数字键盘 / 保存
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/amount_display.dart';
import 'widgets/category_grid.dart';
import 'widgets/numpad.dart';
import 'widgets/type_toggle.dart';

class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({super.key});

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  String _type = 'expense';
  String _amount = '';
  int? _categoryId;
  final DateTime _occurredAt = DateTime.now();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    setState(() {
      if (key == '⌫') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (key == '.') {
        if (!_amount.contains('.')) {
          _amount = _amount.isEmpty ? '0.' : '$_amount.';
        }
        return;
      }
      // 数字
      if (_amount.contains('.')) {
        final parts = _amount.split('.');
        if (parts.length == 2 && parts[1].length >= 2) return;
      }
      final intPart = _amount.split('.').first;
      if (intPart.length >= 8) return;
      _amount = (_amount == '0' && key != '.') ? key : '$_amount$key';
    });
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount);
    if (value == null || value <= 0) {
      _toast('金额要大于 0');
      return;
    }
    if (_categoryId == null) {
      _toast('选个分类');
      return;
    }
    await ref.read(transactionRepositoryProvider).add(
          amount: value,
          type: _type,
          categoryId: _categoryId!,
          occurredAt: _occurredAt,
          note: _noteController.text.isEmpty ? null : _noteController.text,
        );
    // 刷新流水数据
    ref.invalidate(allTransactionsByDayProvider);
    ref.invalidate(monthTransactionsProvider);
    if (!mounted) return;
    context.go('/home');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: TypeToggle(
                value: _type,
                onChanged: (v) => setState(() {
                  _type = v;
                  _categoryId = null;
                }),
              ),
            ),
            AmountDisplay(amount: _amount, type: _type),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                child: CategoryGrid(
                  type: _type,
                  selected: _categoryId,
                  onSelect: (id) => setState(() => _categoryId = id),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: TextField(
                controller: _noteController,
                maxLength: 30,
                decoration: const InputDecoration(
                  hintText: '备注(可选)',
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s2),
              child: Numpad(onKey: _onKey),
            ),
          ],
        ),
      ),
    );
  }
}
