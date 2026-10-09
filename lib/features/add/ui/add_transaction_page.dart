// lib/features/add/ui/add_transaction_page.dart
// 记一笔 —— 类型切换 / 表达式 / 金额大字号 / 分类网格 / 备注 / 计算器键盘 / 保存
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

class _CalcState {
  String display = '0';           // 当前显示字符串
  String expression = '';         // 表达式(已计算的部分)
  double? previousValue;          // 上一个数
  String? pendingOp;              // 等待中的运算符
  bool justEvaluated = false;     // 上一次按键是 =
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  String _type = 'expense';
  int? _categoryId;
  final DateTime _occurredAt = DateTime.now();
  final _noteController = TextEditingController();
  final _calc = _CalcState();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'C') {
        _calc.display = '0';
        _calc.expression = '';
        _calc.previousValue = null;
        _calc.pendingOp = null;
        _calc.justEvaluated = false;
        return;
      }
      if (key == '⌫') {
        if (_calc.justEvaluated) {
          _calc.display = '0';
          _calc.justEvaluated = false;
          return;
        }
        if (_calc.display.length > 1) {
          _calc.display = _calc.display.substring(0, _calc.display.length - 1);
          if (_calc.display == '-') _calc.display = '0';
        } else {
          _calc.display = '0';
        }
        return;
      }
      if (key == '%') {
        final v = double.tryParse(_calc.display) ?? 0;
        _calc.display = _formatNumber(v / 100);
        _calc.justEvaluated = true;
        return;
      }
      if (key == '±') {
        if (_calc.display.startsWith('-')) {
          _calc.display = _calc.display.substring(1);
        } else if (_calc.display != '0') {
          _calc.display = '-$_calc.display';
        }
        return;
      }
      if ('+-×÷'.contains(key)) {
        if (_calc.pendingOp != null && !_calc.justEvaluated) {
          _evaluate();
        }
        _calc.previousValue = double.tryParse(_calc.display);
        _calc.pendingOp = key;
        _calc.justEvaluated = false;
        _calc.expression = '${_formatNumber(_calc.previousValue ?? 0)} $key';
        _calc.display = '0';
        return;
      }
      if (key == '=') {
        _evaluate();
        return;
      }
      if (key == '.') {
        if (_calc.justEvaluated) {
          _calc.display = '0.';
          _calc.justEvaluated = false;
          return;
        }
        if (!_calc.display.contains('.')) {
          _calc.display = '${_calc.display}.';
        }
        return;
      }
      if (key == '00') {
        if (_calc.justEvaluated) {
          _calc.display = '0';
          _calc.justEvaluated = false;
          return;
        }
        if (_calc.display == '0') return;
        if (_calc.display.length >= 11) return;
        _calc.display = '$_calc.display' '00';
        return;
      }
      // 数字 0-9
      if (_calc.justEvaluated) {
        _calc.display = key;
        _calc.justEvaluated = false;
        _calc.previousValue = null;
        _calc.pendingOp = null;
        _calc.expression = '';
      } else if (_calc.display == '0') {
        _calc.display = key;
      } else {
        if (_calc.display.length >= 12) return;
        _calc.display = '$_calc.display$key';
      }
    });
  }

  void _evaluate() {
    if (_calc.pendingOp == null || _calc.previousValue == null) return;
    final current = double.tryParse(_calc.display) ?? 0;
    final prev = _calc.previousValue!;
    double result;
    switch (_calc.pendingOp) {
      case '+':
        result = prev + current;
        break;
      case '-':
        result = prev - current;
        break;
      case '×':
        result = prev * current;
        break;
      case '÷':
        if (current == 0) {
          _toast('不能除以 0');
          return;
        }
        result = prev / current;
        break;
      default:
        return;
    }
    _calc.expression =
        '${_formatNumber(prev)} ${_calc.pendingOp} ${_formatNumber(current)} =';
    _calc.display = _formatNumber(result);
    _calc.previousValue = result;
    _calc.pendingOp = null;
    _calc.justEvaluated = true;
  }

  String _formatNumber(double v) {
    if (v == v.truncateToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    var s = v.toStringAsFixed(6);
    // 去掉尾随 0 和无意义的小数点
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  Future<void> _save() async {
    final value = double.tryParse(_calc.display);
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
            // 表达式 + 金额
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_calc.expression.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _calc.expression,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  AmountDisplay(amount: _calc.display, type: _type),
                ],
              ),
            ),
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
              padding: const EdgeInsets.all(AppSpacing.s1),
              child: Numpad(onKey: _onKey),
            ),
          ],
        ),
      ),
    );
  }
}
