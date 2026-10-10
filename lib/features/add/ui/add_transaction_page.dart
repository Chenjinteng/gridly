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
import '../../../core/utils/formatters.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/amount_display.dart';
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
  DateTime _occurredAt = DateTime.now();
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
    // 广谱刷新 —— 流水 / 首页 / 报表 / 分类页都同步更新
    refreshAllData(ref);
    if (!mounted) return;
    context.go('/home');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
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
                          const Spacer(),
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
          const SizedBox(width: AppSpacing.s3),
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

  /// 弹分类选择底部 sheet,选完自动关
  void _openCategoryPicker() {
    final cats = ref.read(categoriesByTypeProvider(_type)).valueOrNull ?? [];
    if (cats.isEmpty) {
      _toast('没有可用分类');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _CategoryPickerSheet(
        categories: cats,
        selected: _categoryId,
        onSelect: (id) {
          setState(() => _categoryId = id);
          Navigator.pop(context);
        },
      ),
    );
  }

  /// 弹日期选择器 —— 默认值 = 当前 _occurredAt(支持从一周前接着改)
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      // 不允许选未来日期(记账不会提前记未来)
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: '选择日期',
    );
    if (picked != null) {
      setState(() {
        _occurredAt = picked;
      });
    }
  }

  /// 日期行(支出/收入 tab 下方,金额上方)——
  /// 默认"今天",改过后显示具体日期,点击整行触发 _pickDate
  Widget _dateRow(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = _occurredAt.year == now.year &&
        _occurredAt.month == now.month &&
        _occurredAt.day == now.day;
    final isYesterday = _occurredAt.year == now.year &&
        _occurredAt.month == now.month &&
        _occurredAt.day == now.day - 1;
    final label = isToday
        ? '今天'
        : isYesterday
            ? '昨天'
            : Formatters.dayHeader(_occurredAt);
    final color = isToday
        ? AppBrand.gold
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s1,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickDate,
            borderRadius: AppRadius.brSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: color.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // "回到今天"快捷按钮 —— 仅在选了非今天时出现
          if (!isToday)
            InkWell(
              onTap: () => setState(() => _occurredAt = DateTime.now()),
              borderRadius: AppRadius.brXs,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s1,
                ),
                child: Text(
                  '回到今天',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
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
      ),
    );
  }
}

/// 分类选择底部 sheet —— 在记一笔页 SaveBar 左侧点击时弹出。
/// 之前是独立文件 category_selector.dart,现在合并进记一笔页(分类入口只此一处)。
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppGray.g600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final isSel = c.id == selected;
                  final color = Color(c.color);
                  return InkWell(
                    onTap: () => onSelect(c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? color.withValues(alpha: 0.10)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              CategoryIcons.map[c.icon] ??
                                  Icons.category_rounded,
                              color: color,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSel
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSel ? color : null,
                              ),
                            ),
                          ),
                          if (isSel)
                            Icon(Icons.check_circle, color: color, size: 20),
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
