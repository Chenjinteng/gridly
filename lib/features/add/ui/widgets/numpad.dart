// lib/features/add/ui/widgets/numpad.dart
// 3x4 数字键盘:1-9 + 0 + . + ⌫
import 'package:flutter/material.dart';

class Numpad extends StatelessWidget {
  const Numpad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];
    return Column(
      children: keys.map((row) {
        return Row(
          children: row.map((k) {
            return Expanded(
              child: AspectRatio(
                aspectRatio: 1.8,
                child: InkWell(
                  onTap: () => onKey(k),
                  child: Center(
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: k == '⌫' ? 24 : 26,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
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
}
