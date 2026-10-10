// lib/features/add/ui/widgets/amount_display.dart
// 大字号金额显示
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.amount, required this.type})
      : assert(
          amount.length <= 16,
          'amount 异常长,可能被错误地传了对象而不是 display 字符串。'
          '常见原因:在 Dart 字符串插值里写了 \$_calc.display(没加花括号),'
          'Dart 会把 \$_calc 求值为 _calc.toString(),再把 .display 当字面量拼上,'
          '最终得到 "Instance of \'X\' .display" 这样的脏字符串。'
          '修复:把 \$_calc.display 改成 \${_calc.display}。',
        );

  final String amount;     // 用户输入的字符串
  final String type;       // 'expense' | 'income'

  @override
  Widget build(BuildContext context) {
    final color = type == 'income' ? AppBrand.gold : AppBrand.teal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '¥',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            amount.isEmpty ? '0' : amount,
            style: TextStyle(
              color: color,
              fontSize: 56,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}
