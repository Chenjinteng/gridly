// lib/features/add/ui/widgets/numpad.dart
// 5x4 计算器键盘 —— 5 行固定高(SizedBox),外层不再依赖 Expanded 给高
//   C  ⌫  %   ÷
//   7  8  9   ×
//   4  5  6   -
//   1  2  3   +
//   0  .  00  =
//
// 2026-10-11 改本征高:之前每行用 Expanded,在父级被 keyboards 推挤时会均分
// 剩余空间,4 行只剩 1 行可见,后面 3 行被键盘覆盖。改 SizedBox(height:56)
// 后 Numpad 总高 280px,不被压缩,transaction_form 的表单上半部
// 改用 Expanded(SingleChildScrollView) 来让键盘弹出时滚动给备注。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class Numpad extends StatelessWidget {
  const Numpad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  /// 单行高度。5 × 56 = 280px,典型 4 列 5 行计算器键位;
  /// 太矮(40-50)易误触,太高(70+)挤掉备注/分类显示区
  static const double _rowHeight = 56;

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
      mainAxisSize: MainAxisSize.min,
      children: _keys.map((row) {
        return SizedBox(
          height: _rowHeight,
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: InkWell(
                  onTap: () => onKey(k),
                  child: Center(
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: _isNumber(k) ? 22 : 20,
                        fontWeight:
                            _isNumber(k) ? FontWeight.w500 : FontWeight.w600,
                        color: _keyColor(context, k),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  bool _isNumber(String k) {
    if (k.length == 1 && '0123456789.'.contains(k)) return true;
    return k == '00';
  }

  Color _keyColor(BuildContext context, String k) {
    if (k == 'C') return AppStatus.error;
    if ('+-×÷%='.contains(k)) return AppBrand.teal;
    return Theme.of(context).colorScheme.onSurface;
  }
}
