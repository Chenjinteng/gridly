// lib/features/add/ui/widgets/numpad.dart
// 4x4 + 第 5 行 = 5x4 计算器键盘
//   C  ⌫  %  ÷
//   7  8  9  ×
//   4  5  6  -
//   1  2  3  +
//   0  .  00 =
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class Numpad extends StatelessWidget {
  const Numpad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  static const _keys = [
    ['C', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '00', '='],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) {
        return Row(
          children: row.map((k) {
            return Expanded(
              child: AspectRatio(
                aspectRatio: 1.9,
                child: InkWell(
                  onTap: () => onKey(k),
                  child: Center(
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: _isNumber(k) ? 24 : 22,
                        fontWeight: _isNumber(k) ? FontWeight.w500 : FontWeight.w600,
                        color: _keyColor(context, k),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  bool _isNumber(String k) {
    if (k.length == 1 && '0123456789.'.contains(k)) return true;
    return false;
  }

  Color _keyColor(BuildContext context, String k) {
    if (k == 'C') return AppStatus.error;
    if ('+-×÷%='.contains(k)) return AppBrand.teal;
    return Theme.of(context).colorScheme.onSurface;
  }
}
