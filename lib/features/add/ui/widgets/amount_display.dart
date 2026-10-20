// lib/features/add/ui/widgets/amount_display.dart
// 大字号金额显示
//
// 2026-10-13 P7 改:金额色 = TypeToggle 选中色(支出红 / 收入 teal / 调拨浅金)
//   - user UAT:"切换时要保持与中间的输入数字一致" — toggle 切到支出,金额变红;
//     切到收入变 teal,视觉系统统一
//
// 2026-10-16 D64.77 改:type → color 改走 TxDisplayStyle 集中表
//   - 之前 switch 5 case(2026-10-14 D51 加 lend_out / borrow_in),跟
//     transaction_tile prefix/label 3 处 switch 重复
//   - 现在 1 处定义,3 处共用,改 1 处生效全部
import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/tx_display_style.dart';

class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.amount, required this.type});

  final String amount; // 用户输入的字符串
  final String
  type; // 'expense' | 'income' | 'balance' | 'lend_out' | 'borrow_in'

  @override
  Widget build(BuildContext context) {
    // 2026-10-20 D64.83 改:forType → forAmount(按金额符号)
    //   - 投资「收益」段可以记负数(亏损),负数用红色(亏损语义),不是"收入绿"
    //   - 负号拆出来放 ¥ 前面:显示 "- ¥184.88",不是 "¥-184.88"
    final parsed = double.tryParse(amount);
    final style = TxDisplayStyle.forAmount(type, parsed ?? 0);
    final color = style.color;
    final isNegative = (parsed ?? 0) < 0;
    final raw = amount.isEmpty ? '0' : amount;
    final sign = isNegative ? '-' : '';
    final digits = isNegative ? raw.replaceFirst('-', '') : raw;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (sign.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                sign,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
          // FittedBox 兜底:即使长度限制意外失效,文本也会缩字号不溢出
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                digits,
                style: TextStyle(
                  color: color,
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
