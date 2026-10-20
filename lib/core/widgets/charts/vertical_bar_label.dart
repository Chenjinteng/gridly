// lib/core/widgets/charts/vertical_bar_label.dart
// 图表 X 轴竖排 label(中文场景专用)
//
// 2026-10-20 D64.72 加:
//   - 背景:消费趋势「类别」tab 9 个中文分类名(给家里/水电燃气/会员咖啡…)在
//     手机宽度下横排必然重叠。实测(真机 ChartCard 内容宽 ≈ 296dp,9 个分类
//     平均每个只有 28dp 位宽):
//       45° 斜排 + 10sp → 5 对重叠 / + 9sp → 3 对 / + 8sp → 1 对(都放不下)
//       55°/60° + 8sp   → 0 对(但字太小)
//       70° + 9sp       → 0 对(但字符被转 70°,读要歪头)
//       本 widget(字正立竖着堆)+ 9sp → 0 对,字最清楚 ✅
//   - 关键区别:**真·中文竖排**(字符保持正立、上下堆叠)≠ 把整段文字旋转 90°
//     (那样字符会躺倒,中文几乎不可读)
//
// 用法:
//   AnimatedBarChart(
//     xLabelReservedSize: 64,          // 底部留够竖排高度
//     xLabelBuilder: (i, b) => const VerticalBarLabel(b.label),
//   )
import 'package:flutter/material.dart';

/// 图表 X 轴竖排 label —— 字符保持正立,自上而下逐字堆叠
class VerticalBarLabel extends StatelessWidget {
  const VerticalBarLabel(
    this.text, {
    super.key,
    this.fontSize = 9,
    this.maxChars = 7,
  });

  /// 完整文字(超过 maxChars 时截断并加省略号)
  final String text;

  /// 字号(默认 9sp,axis label 级别)
  final double fontSize;

  /// 最多显示几个字(超出截断)。7 字 × 9sp ≈ 63px,配合 xLabelReservedSize=64
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final truncated = chars.length > maxChars;
    final shown = truncated ? chars.sublist(0, maxChars - 1) : chars;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final ch in shown)
          Text(
            ch,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (truncated)
          Text(
            '…',
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
