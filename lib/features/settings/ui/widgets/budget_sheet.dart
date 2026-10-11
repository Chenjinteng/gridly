// lib/features/settings/ui/widgets/budget_sheet.dart
// 月度预算设置底部表单
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';

class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key});

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(monthlyBudgetProvider);
    _controller = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_controller.text.trim());
    setState(() => _saving = true);
    try {
      await ref.read(monthlyBudgetProvider.notifier).set(v ?? 0);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await ref.read(monthlyBudgetProvider.notifier).set(0);
      _controller.clear();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s3,
          AppSpacing.s4,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.s3),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '月度预算',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s1),
            const Text(
              '设置后,首页会显示预算进度(80% 警告,100% 超支)。',
              style: TextStyle(fontSize: 12, color: AppGray.g600),
            ),
            const SizedBox(height: AppSpacing.s4),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // 语义级上限,跟记账计算器的 maxIntDigits=7 / maxFracDigits=2 对齐:
              // 9999999.99 = 7 位整数 + 小数点 + 2 位小数。maxLength 单卡字符数
              // 会被 "100000000000" 这种远超业务上限的值绕过,落到 Formatters.amount
              // 才被发现"超出范围",这里前置拦掉。
              inputFormatters: [const _AmountInputFormatter()],
              decoration: const InputDecoration(
                labelText: '预算金额',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  // dark mode 仿 onDark:ink → cream
                  backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                  foregroundColor: isDark ? AppBrand.ink : null,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.brLg,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppBrand.gold,
                        ),
                      )
                    : Text(_controller.text.isEmpty ? '保存' : '保存 · ¥${_controller.text}'),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            SizedBox(
              width: double.infinity,
              // OutlinedButton + 错误色边框/文字:
              //   - 形状跟 FilledButton 一致(同 AppRadius.brLg、同 padding),
              //     视觉上是"按钮家族"的次级成员而非游离文字
              //   - 无背景填充,语义/视觉上仍然次要于"保存"(主行动),
              //     但不再是看起来像取消链接的纯红字,不易误点又保持按钮感
              child: OutlinedButton(
                onPressed: _saving ? null : _clear,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.brLg,
                  ),
                  foregroundColor: AppStatus.error,
                  side: const BorderSide(color: AppStatus.error, width: 1),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.s3,
                  ),
                ),
                child: const Text('清除预算'),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 提示:用金额格式化显示
            Text(
              _controller.text.isEmpty
                  ? '当前未设置预算'
                  : '将设预算为 ¥${Formatters.amount(double.tryParse(_controller.text) ?? 0)}',
              style: const TextStyle(fontSize: 11, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预算/记账公用金额输入 formatter:7 位整数 + 小数点 + 2 位小数 = 9999999.99
///
/// 比 `maxLength` 单卡字符数更稳:
///   - 字符级 `"9999999.99"` 是 10 字符,正好到上限没事,但 `"9999999999"`(99 亿)
///     也是 10 字符却远超业务上限
///   - 这里按"整数位数 ≤ 7,小数位数 ≤ 2"分两段判断,跟 Formatters.amount 的
///     上限语义一致,在用户输入阶段就前置拦截
///
/// 不允许负号(预算/支出场景都是正数),需要负号走 ± 单独逻辑(如记账计算器)
class _AmountInputFormatter extends TextInputFormatter {
  const _AmountInputFormatter();

  static const _maxIntegerDigits = 7;
  static const _maxFractionDigits = 2;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // 字符级白名单:只允许数字 + 可选 1 个小数点(其它修饰符号、字母全剔除)
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text)) {
      return oldValue;
    }
    final dotIdx = text.indexOf('.');
    if (dotIdx == -1) {
      // 纯整数:总位数 ≤ 7
      if (text.length > _maxIntegerDigits) return oldValue;
    } else {
      // 带小数:整数位 ≤ 7 && 小数位 ≤ 2
      if (dotIdx > _maxIntegerDigits) return oldValue;
      final fracLen = text.length - dotIdx - 1;
      if (fracLen > _maxFractionDigits) return oldValue;
    }
    return newValue;
  }
}
