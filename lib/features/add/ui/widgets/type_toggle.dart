// lib/features/add/ui/widgets/type_toggle.dart
// 类型切换:支出 / 收入
import 'package:flutter/material.dart';

class TypeToggle extends StatelessWidget {
  const TypeToggle({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'expense',
          label: Text('支出'),
          icon: Icon(Icons.arrow_outward_rounded, size: 18),
        ),
        ButtonSegment(
          value: 'income',
          label: Text('收入'),
          icon: Icon(Icons.south_west_rounded, size: 18),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
