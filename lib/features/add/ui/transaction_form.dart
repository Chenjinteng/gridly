// lib/features/add/ui/transaction_form.dart
// 流水编辑 / 新增表单(纯 body,无 Scaffold/AppBar)——
//   - AddTransactionPage:包成 Scaffold 做"全屏记一笔"页面
//   - EditTransactionPage:包成 Scaffold 做"全屏编辑"页面(/edit/:id 路由)
//
// 两处共用同一份表单逻辑(type toggle / 表达式计算器 / 分类 / 日期 / 备注 / 保存),
// 调用方通过 onSaved 回调决定保存后行为(都 context.pop(),返回路由栈上一级)。
//
// ⚠️ 2026-10-11 改:之前流水编辑用 showEditTransactionSheet(modal sheet),sheet 内
// AnimatedPadding 会按 viewInsets 推 Numpad 上移,跟全屏不一致。改成全屏路由后,
// 两处都用 Scaffold(resizeToAvoidBottomInset:false)+ SafeArea(bottom:false) 的
// 同一套物理布局:键盘弹起时 Numpad 真正被键盘盖住。
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
import '../../../core/utils/gridly_banner.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/amount_display.dart';
import 'widgets/custom_date_picker.dart';
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
    // 个人记账上限:9,999,999.99(≈ 10 百万)
    // 上限由"语义"决定(7 位整数 + 小数点 + 2 位小数),而不是字符数:
    //   - 长度限制会被"9999999999"(10 位整数=99 亿)等绕开,远超业务上限
    //   - 真正的上限是数学意义上的绝对值,所以按整/小数位分别判断
    // 负号由 ± 单独处理,不影响整/小数位判断
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
      // 语义上限:7 位整数 + 2 位小数 = 9999999.99
      // 负号前缀不影响位数(由 ± 单独维护),只剥离后判断数字部分
      const maxIntegerDigits = 7;
      const maxFractionDigits = 2;
      // 数字键按当前是否已含小数点判断是限制整数位还是小数位
      if (RegExp(r'^[0-9]$').hasMatch(key)) {
        final s = _calc.display.startsWith('-')
            ? _calc.display.substring(1)
            : _calc.display;
        final dotIdx = s.indexOf('.');
        if (dotIdx == -1) {
          if (s.length >= maxIntegerDigits) return; // 整数位已满
        } else {
          final fracLen = s.length - dotIdx - 1;
          if (fracLen >= maxFractionDigits) return; // 小数位已满
        }
      }
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
    // 计算结果超出 9999999.99 → 显示"超出范围"
    if (result.abs() > 9999999.99 || result.isNaN || result.isInfinite) {
      _curr.expression = '';
      _curr.display = '超出范围';
      _curr.previousValue = null;
      _curr.pendingOp = null;
      _curr.justEvaluated = true;
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
    showGridlyBanner(context, msg, kind: GridlyBannerKind.warning);
  }

  Future<void> _pickDate() async {
    // 2026-10-11 UAT:系统 showDatePicker 满屏英文("Sun, Oct 11" / "Cancel")
    // + 卡片样式跟 gridly 不搭。换成自定义 CustomDatePickerSheet:
    //   - 全中文:年月日 / 快捷按钮 / 取消确定 / 周日一二三四五六
    //   - 卡片样式对齐 gridly(AppRadius.brXl + brand teal)
    //   - 顶部"今天/昨天/前天"快捷(覆盖记账 80% 场景)
    final picked = await showCustomDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    // 2026-10-11 UAT 反馈:分类管理页加了新分类后,在记一笔的分类选择
    // 器里看不到。原因:之前这里 ref.read(provider) 拿到 picker 打开
    // 那一瞬间的快照(Snapshot),即使父级 _saveBar watch 的 invalidate
    // 已经触发,read 不会重新计算、也不会随新数据重建。
    // 修复:把 _CategoryPickerSheet 改成 ConsumerWidget,内部 watch 这个
    // provider。打开后 invalidate 完成的最新分类会自动出现在 grid 里。
    // 调用方只负责传 type + selected + onSelect,不再读 categories。
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _CategoryPickerSheet(
        type: _type,
        selected: _categoryId,
        onSelect: (id) {
          setState(() => _categoryId = id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // ============================================================
// 2026-10-11 UAT 第三次重构 —— 单行操作栏:
//   顶部:type toggle(支出/收入,很少切换,放最上面)
//   中部:金额(大字,主视觉)
//   操作行:[今天][分类][备注][保存] —— 一行内放完,贴近 Numpad,
//         单手握机时拇指自然覆盖整个 row,不用抬手
//   底部:Numpad(键盘区域固定)
//   旧 _metaRow / _datePill / _categoryChip / _saveButton 全部弃用,
//   单一 _actionRow 替代
// ============================================================

  /// ③两行操作栏(贴近 Numpad,单手拇指可达):
  ///   上行:备注 TextField(占满整行,不再跟其它挤)
  ///   下行:[日期 pill][分类 chip][保存按钮] — 3 items
  /// 之前 4 items 一行挤不下,分类 chip 名字被 flex 吃掉变成只有 icon,
  /// 备注输入框又被挤压。改成两行后,每个 item 都有自己的舒适宽度。
  Widget _actionRow(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catsAsync = ref.watch(categoriesByTypeProvider(_type));
    Category? sel;
    catsAsync.whenData((cats) {
      for (final c in cats) {
        if (c.id == _categoryId) {
          sel = c;
          break;
        }
      }
    });
    final hasCat = sel != null;
    final canSave = _categoryId != null;
    final isToday = _occurredAt.year == DateTime.now().year &&
        _occurredAt.month == DateTime.now().month &&
        _occurredAt.day == DateTime.now().day;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s3,
        AppSpacing.s2,
        AppSpacing.s3,
        AppSpacing.s2,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上行:备注 —— 占满整行,舒适的输入空间
          TextField(
            controller: _noteController,
            maxLength: 30,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: '备注',
              hintStyle: TextStyle(color: AppGray.g400, fontSize: 13),
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s1,
                vertical: AppSpacing.s2,
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.s2),
          // 下行:[日期][分类][保存] —— 2026-10-11 UAT 第四轮反馈:
//   日期 + 分类 1:1 均分(两个弹性 Expanded 同 flex),
//   保存按钮固定窄宽(跟之前一致),不强拉成 1/3。
          Row(
            children: [
              // 1) 日期 pill(均分 1/2)
              Expanded(
                child: _ActionPill(
                  icon: Icons.calendar_today_rounded,
                  label: isToday ? '今天' : '${_occurredAt.month}月${_occurredAt.day}日',
                  highlighted: isToday,
                  highlightColor: AppBrand.teal,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              // 2) 分类 chip(均分 1/2)
              Expanded(
                child: _ActionPill(
                  icon: hasCat
                      ? (CategoryIcons.map[sel!.icon] ??
                          Icons.category_rounded)
                      : Icons.category_outlined,
                  label: hasCat ? sel!.name : '选分类',
                  highlighted: hasCat,
                  highlightColor: hasCat ? Color(sel!.color) : null,
                  iconColorOverride: hasCat ? Color(sel!.color) : null,
                  onTap: _openCategoryPicker,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              // 3) 保存按钮(固定窄宽,pill 形)
              SizedBox(
                height: 36,
                child: FilledButton(
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
                    ),
                    minimumSize: const Size(64, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.brPill,
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ③ 金额块 —— 表达式(若有)+ 大金额(默认右对齐,跟数字键盘 Numpad 方向一致)
  Widget _amountBlock(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_calc.expression.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _calc.expression,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        AmountDisplay(amount: _calc.display, type: _type),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Numpad 始终固定在底部 —— 键盘弹起时被系统键盘覆盖(由 AddTransactionPage
    // 的 Scaffold.resizeToAvoidBottomInset=false 实现),不需要任何运行时检测。
    // 2026-10-11 UAT 最终方案:前 5 次尝试(保留 Numpad 高度 / MediaQuery 隐藏 /
    // FocusNode 隐藏 / Scaffold popUntil)都被推翻 —— 路线太复杂,改回最简单的:
    //   记金额 → Numpad 在,键盘不用
    //   写备注 → 键盘在,Numpad 被盖住(无所谓,写备注时用不到计算器)
    //   收键盘 → Numpad 回来
    // SafeArea(bottom: false) —— 关掉底部的 viewInsets/padding padding。
    // 原因:Scaffold.resizeToAvoidBottomInset=false 只挡 Scaffold 重排,
    // 但 SafeArea 默认会按 viewInsets.bottom 加底部 padding,
    // 结果键盘弹起时 Numpad 被顶起来(SafeArea 推上去),不被键盘覆盖。
    // 改 bottom: false 后 SafeArea 只挡 home indicator(由 padding.bottom 给),
    // 不挡键盘(由 viewInsets.bottom 给,但我们不要这个 padding)
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // 2026-10-11 UAT 三改:操作行单行化。
          // 上半区(type toggle + 金额)可滚动;
          // 下半区(_actionRow)是固定操作行,贴近 Numpad,
          // 拇指自然覆盖。
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ① type toggle(支出/收入,顶部居中)
                  Align(
                    alignment: Alignment.center,
                    child: TypeToggle(
                      value: _type,
                      onChanged: (v) => setState(() {
                        _type = v;
                        _categoryId = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  // ② 金额(主视觉,大)
                  _amountBlock(context),
                ],
              ),
            ),
          ),
          // ③ 单行操作栏:[今天] [分类] [备注] [保存]
          // 4 个 item 在一行内,贴近 Numpad,单手握机时拇指覆盖区
          _actionRow(context, ref),
          // 始终显示 —— 键盘弹起时由外层 Scaffold(resizeToAvoidBottomInset=false)
          // 让键盘自然覆盖此处。
          // 2026-10-11 UAT:外层 SafeArea(bottom:false) 把底部 padding 关了,
          // 键盘弹起时不会被顶上去,但代价是 Numpad 贴到屏幕底边、跟 iOS
          // 小白条(home indicator)叠在一起,最后一行数字(0 / . / 00 / =)
          // 几乎点不到。这里手动加 MediaQuery.padding.bottom,留出小白条
          // 高度的留白 —— 不影响键盘覆盖(键盘是 viewInsets.bottom,跟
          // padding.bottom 是两个独立维度,这里只读 padding 不读 viewInsets)。
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s1,
              AppSpacing.s1,
              AppSpacing.s1,
              AppSpacing.s1 + MediaQuery.of(context).padding.bottom,
            ),
            child: Numpad(onKey: _onKey),
          ),
        ],
      ),
    );
  }
}

/// _actionRow 用的紧凑 pill 按钮 —— icon + label 单行展示
/// 配合不同 highlighted 状态(highlight color: teal/gold/分类色)区分语义
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.highlightColor,
    this.iconColorOverride,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final Color? highlightColor;
  final Color? iconColorOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = highlightColor ?? theme.colorScheme.onSurfaceVariant;
    final bg = highlighted
        ? accent.withValues(alpha: 0.10)
        : theme.colorScheme.surfaceContainerLow;
    final fg = highlighted ? accent : theme.colorScheme.onSurface;
    final iconColor = iconColorOverride ?? (highlighted ? accent : AppGray.g600);
    return InkWell(
      borderRadius: AppRadius.brPill,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brPill,
          border: Border.all(
            color: highlighted
                ? accent.withValues(alpha: 0.4)
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            // 2026-10-11 UAT 撤回居中:长分类名(如"吃吃喝喝必选")被
            // 居中后溢出 + ellipsis 切位,看起来"文字没居中"。改回左对齐,
            // icon + 文字紧贴左边,文字过长时自然尾部省略。
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类选择底部 sheet —— 在 TransactionForm SaveBar 左侧点击时弹出。
///
/// 2026-10-11 UAT:从 StatelessWidget + 静态分类列表改成
/// ConsumerWidget + ref.watch(categoriesByTypeProvider(type))。原因:
/// 调用方 (TransactionForm._openCategoryPicker) 用 ref.read 拿一次性快照,
/// 即使父级 _saveBar watch 触发了 invalidate,read 不会重新计算 —— picker
/// 仍显示旧列表,在分类管理加新分类后这里看不到。改成 watch 后 invalidate
/// 完成时 picker 自动 rebuild 拿到最新分类。
class _CategoryPickerSheet extends ConsumerWidget {
  const _CategoryPickerSheet({
    required this.type,
    required this.selected,
    required this.onSelect,
  });
  final String type;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catsAsync = ref.watch(categoriesByTypeProvider(type));
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          color: theme.colorScheme.surface,
          child: catsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s4),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Center(child: Text('加载失败:$e')),
            ),
            data: (cats) => Column(
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
                        '${cats.length} 个',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppSpacing.s4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: AppSpacing.s2,
                      crossAxisSpacing: AppSpacing.s2,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: cats.length,
                    itemBuilder: (context, i) {
                      final c = cats[i];
                      final isSelected = c.id == selected;
                      return InkWell(
                        borderRadius: AppRadius.brLg,
                        onTap: () => onSelect(c.id),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.s2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(c.color).withValues(alpha: 0.12)
                                : theme.colorScheme.surfaceContainerLow,
                            borderRadius: AppRadius.brLg,
                            border: Border.all(
                              color: isSelected
                                  ? Color(c.color)
                                  : theme.colorScheme.outlineVariant,
                              width: isSelected ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CategoryIcons.map[c.icon] ??
                                    Icons.category_rounded,
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
            ),
          ),
        );
      },
    );
  }
}