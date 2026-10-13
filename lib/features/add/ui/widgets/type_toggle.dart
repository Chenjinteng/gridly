// lib/features/add/ui/widgets/type_toggle.dart
// 类型切换:支出 / 收入 / 调拨(可选)
//
// 2026-10-13 P6 UAT 改:加 allowBalance 参数
//   - 短按路径(老版):allowBalance=false,只显示 支出/收入
//   - 长按路径(目前):allowBalance=true,保留 3 段
//
// 2026-10-12 P3 commit 改:加 'balance' 段
//   - 'balance' = 动资产但不算月度收支(公积金月供 / 期权 / 外借等)
//   - UI 标签:中文"调拨"(比"balance"直观,user 一眼就懂)
//   - icon:swap_horiz_rounded(横向调拨视觉)
//
// 业务规则(TransactionForm 内):
//   - type='expense' / 'income' → 计入月度汇总(已花 / 收入)
//   - type='balance' → 不计入月度汇总,仅算对应资产 currentBalance 变动
import 'package:flutter/material.dart';

class TypeToggle extends StatelessWidget {
  const TypeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowBalance = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowBalance;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: [
        const ButtonSegment(
          value: 'expense',
          label: Text('支出'),
          icon: Icon(Icons.arrow_outward_rounded, size: 18),
        ),
        const ButtonSegment(
          value: 'income',
          label: Text('收入'),
          icon: Icon(Icons.south_west_rounded, size: 18),
        ),
        if (allowBalance)
          const ButtonSegment(
            value: 'balance',
            label: Text('调拨'),
            icon: Icon(Icons.swap_horiz_rounded, size: 18),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
