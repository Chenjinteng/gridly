// lib/features/add/ui/transaction_form.dart
// 流水编辑 / 新增表单(纯 body,无 Scaffold/AppBar)——
//   - AddTransactionPage:包成 Scaffold 做"全屏记一笔"页面
//   - showEditTransactionSheet:包成 Modal Bottom Sheet 做"在当前 tab 弹出编辑"
//
// 两处共用同一份表单逻辑(type toggle / 表达式计算器 / 分类 / 日期 / 备注 / 保存),
// 调用方通过 onSaved 回调决定保存后行为(context.go('/home') vs Navigator.pop())。
//
// ⚠️ 字符串插值陷阱(沿用历史踩坑注释):
// Dart 里 `'$_calc.display'` 不会取 _calc.display 的值,而是把 $_calc
// 当插值(_calc.toString() = "Instance of '_CalcState'"),再把 .display 当字面量
// 拼在后面,最终 _calc.display 被赋值成 "Instance of '_CalcState'.display"。
// 正确写法是 '${_calc.display}'(加花括号)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/amount_display.dart';
import 'widgets/numpad.dart';
import 'widgets/type_toggle.dart';

class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({
    super.key,
    this.editTransaction,
    this.onSaved,
  });

  /// 非空 → 编辑模式(预填 + 保存 update)
  /// 为空 → 新增模式(保存 insert)
  final Transaction? editTransaction;

  /// 保存成功后回调(由调用方决定:AddTransactionPage 跳 /home,edit sheet 仅 dismiss)
  final VoidCallback? onSaved;

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _CalcState {
  String display = '0';           // 当前显示字符串
  String expression = '';         // 表达式(已计算的部分)
  double? previousValue;          // 上一个数
  String? pendingOp;              // 等待中的运算符
  bool justEvaluated = false;     // 上一次按键是 =
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  String _type = 'expense';
  int? _categoryId;
  DateTime _occurredAt = DateTime.now();
  final _noteController = TextEditingController();
  final _calc = _CalcState();

  bool get _isEdit => widget.editTransaction != null;

  @override
  void initState() {
    super.initState();
    // 编辑模式:预填已有数据
    final t = widget.editTransaction;
    if (t != null) {
      _type = t.type;
      _categoryId = t.categoryId;
      _occurredAt = t.occurredAt;
      _noteController.text = t.note ?? '';
      // 金额显示:整数显示整数,小数保留原值
      if (t.amount == t.amount.truncateToDouble() && t.amount.abs() < 1e15) {
        _calc.display = t.amount.toInt().toString();
      } else {
        _calc.display = t.amount.toString();
      }
    }
  }

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
      // 数字 / 小数点
      if (_calc.justEvaluated) {
        _calc.display = '0';
        _calc.justEvaluated = false;
      }
      if (key == '.' && _calc.display.contains('.')) return;
      if (_calc.display == '0' && key != '.') {
        _calc.display = key;
      } else {
        // 必须用花括号:'$_calc.display' 会被 linter 当作 _calc.toString() + ".display",
        // 触发文件头的"字符串插值陷阱"。_calc.display 是 String 拼接,加花括号强制语义。
        // ignore: unnecessary_brace_in_string_interps
        _calc.display = '${_calc.display}${key}';
      }
    });
  }

  void _evaluate() {
    if (_curr.previousValue == null || _curr.pendingOp == null) return;
    final cur = double.tryParse(_curr.display) ?? 0;
    double result;
    switch (_curr.pendingOp) {
      case '+':
        result = _curr.previousValue! + cur;
        break;
      case '-':
        result = _curr.previousValue! - cur;
        break;
      case '×':
        result = _curr.previousValue! * cur;
        break;
      case '÷':
        if (cur == 0) {
          _toast('除数不能为 0');
          return;
        }
        result = _curr.previousValue! / cur;
        break;
      default:
        return;
    }
    _curr.expression = '${_formatNumber(_curr.previousValue!)} ${_curr.pendingOp} ${_formatNumber(cur)} =';
    _curr.display = _formatNumber(result);
    _curr.previousValue = null;
    _curr.pendingOp = null;
    _curr.justEvaluated = true;
  }

  // 简化 alias,防止多次 _curr 前缀写错
  _CalcState get _curr => _calc;

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
    final note = _noteController.text.isEmpty ? null : _noteController.text;
    final repo = ref.read(transactionRepositoryProvider);
    if (_isEdit) {
      // 编辑:用原 id replace(Drift 的 replace 按主键 update)
      await repo.update(widget.editTransaction!.copyWith(
        amount: value,
        type: _type,
        categoryId: _categoryId!,
        occurredAt: _occurredAt,
        note: Value(note),
      ));
      if (!mounted) return;
      _toast('已更新');
    } else {
      await repo.add(
        amount: value,
        type: _type,
        categoryId: _categoryId!,
        occurredAt: _occurredAt,
        note: note,
      );
    }
    // 广谱刷新 —— 流水 / 首页 / 报表 / 分类页都同步更新
    refreshAllData(ref);
    if (!mounted) return;
    widget.onSaved?.call();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '选日期',
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
  }

  void _openCategoryPicker() {
    final catsAsync = ref.read(categoriesByTypeProvider(_type));
    final cats = catsAsync.valueOrNull ?? const [];
    if (cats.isEmpty) {
      _toast('该类型下暂无分类');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPickerSheet(
        categories: cats,
        selected: _categoryId,
        onSelect: (id) {
          setState(() => _categoryId = id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// 键盘上方的保存栏 —— 左侧"选分类"入口 + 已选分类显示,
  /// 右侧保存按钮。点左侧任意位置都弹分类选择器,既是显示又是入口。
  /// 位置贴近键盘,输完金额可一步保存,不必抬拇指到 AppBar 右上角。
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
            child: InkWell(
              borderRadius: AppRadius.brMd,
              onTap: _openCategoryPicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                child: sel == null
                    ? Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              Icons.category_outlined,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s2),
                          const Text(
                            '选个分类',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppGray.g600,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.expand_more,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(sel.color).withValues(alpha: 0.12),
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: Color(sel.color).withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              CategoryIcons.map[sel.icon] ??
                                  Icons.category_rounded,
                              color: Color(sel.color),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s2),
                          Expanded(
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
                          Icon(
                            Icons.expand_more,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          FilledButton(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: canSave
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHigh,
              foregroundColor: canSave
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
            ),
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                '${_occurredAt.year}-${_occurredAt.month.toString().padLeft(2, '0')}-${_occurredAt.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
          _dateRow(context),
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
    );
  }
}

/// 分类选择底部 sheet —— 在 TransactionForm SaveBar 左侧点击时弹出。
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });
  final List<Category> categories;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题 + 计数
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选分类',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${categories.length} 个',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(AppSpacing.s4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: AppSpacing.s2,
                  crossAxisSpacing: AppSpacing.s2,
                  childAspectRatio: 0.85,
                ),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final isSelected = c.id == selected;
                  return InkWell(
                    borderRadius: AppRadius.brLg,
                    onTap: () => onSelect(c.id),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.s2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Color(c.color).withValues(alpha: 0.12)
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.brLg,
                        border: Border.all(
                          color: isSelected
                              ? Color(c.color)
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: isSelected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CategoryIcons.map[c.icon] ?? Icons.category_rounded,
                            color: Color(c.color),
                            size: 26,
                          ),
                          const SizedBox(height: AppSpacing.s1),
                          Text(
                            c.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}