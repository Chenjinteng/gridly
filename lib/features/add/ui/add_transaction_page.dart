// lib/features/add/ui/add_transaction_page.dart
// 记一笔 —— 类型切换 / 表达式 / 金额大字号 / 分类下拉 / 备注 / 计算器键盘 / 保存
//
// ⚠️ 字符串插值陷阱(已踩过):
// Dart 里 `'$_calc.display'` 不会取 _calc.display 的值,而是把 $_calc
// 当插值(_calc.toString() = "Instance of '_CalcState'"),再把 .display 当字面量
// 拼在后面,最终 _calc.display 被赋值成 "Instance of '_CalcState'.display"。
// 正确写法是 '${_calc.display}'(加花括号)。任何字符串里要用 _calc.display,
// 都必须带花括号,否则会触发 AmountDisplay 的长度断言。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/amount_display.dart';
import 'widgets/category_selector.dart';
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
          _calc.display = '-${_calc.display}';
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
        _calc.display = '${_calc.display}00';
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
        _calc.display = '${_calc.display}$key';
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

  /// 键盘上方的保存栏 —— 左侧展示当前已选分类(没选就给提示),
  /// 右侧是保存动作按钮。位置贴近键盘,输完金额可一步保存,
  /// 不必抬拇指到 AppBar 右上角。
  Widget _saveBar(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catsAsync = ref.watch(categoriesByTypeProvider(_type));
    Category? current;
    catsAsync.whenData((cats) {
      for (final c in cats) {
        if (c.id == _categoryId) {
          current = c;
          break;
        }
      }
    });
    final canSave = _categoryId != null;
    // 捕获成本地 final,Dart 能在 else 分支自动提升非空
    final sel = current;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: sel == null
                ? const Text(
                    '先选个分类',
                    style: TextStyle(fontSize: 13, color: AppGray.g600),
                  )
                : Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(sel.color).withValues(alpha: 0.12),
                          borderRadius: AppRadius.brMd,
                        ),
                        child: Icon(
                          CategoryIcons.map[sel.icon] ??
                              Icons.category_rounded,
                          color: Color(sel.color),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Flexible(
                        child: Text(
                          sel.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppBrand.ink,
                disabledBackgroundColor: AppGray.g200,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.brLg,
                ),
              ),
              child: const Text(
                '保存',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
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
        // 保存按钮移到了键盘上方(见 _saveBar),方便输完金额直接点
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: CategorySelector(
                type: _type,
                selected: _categoryId,
                onSelect: (id) => setState(() => _categoryId = id),
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
            _saveBar(context, ref),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s1),
                child: Numpad(onKey: _onKey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
