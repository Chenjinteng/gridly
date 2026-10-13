// lib/features/add/ui/widgets/amount_display.dart
// 大字号金额显示
//
// 2026-10-13 P7 改:金额色 = TypeToggle 选中色(支出红 / 收入 teal / 调拨浅金)
//   - user UAT:"切换时要保持与中间的输入数字一致" — toggle 切到支出,金额变红;
//     切到收入变 teal,视觉系统统一
//   - expense = AppStatus.error (#EF4444 红,跟 TypeToggle _primaryFor 对齐)
//   - income = AppBrand.teal (#14B8A6 主题蓝,跟"保存"按钮 / today pill / 现金 chip 一致)
//   - balance = AppSecondary.softGold (#FFEAA7 浅金,中性,跟 income 区分)
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.amount, required this.type});

  final String amount; // 用户输入的字符串
  final String type; // 'expense' | 'income' | 'balance'

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'income' => AppBrand.teal,
      'balance' => AppSecondary.softGold,
      _ => AppStatus.error, // 'expense'
    };
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
          // FittedBox 兜底:即使长度限制意外失效,文本也会缩字号不溢出
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount.isEmpty ? '0' : amount,
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
