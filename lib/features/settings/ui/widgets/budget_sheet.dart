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
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              maxLength: 12,
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
                  backgroundColor: AppBrand.ink,
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
              child: TextButton(
                onPressed: _saving ? null : _clear,
                child: const Text(
                  '清除预算',
                  style: TextStyle(color: AppStatus.error, fontSize: 13),
                ),
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
