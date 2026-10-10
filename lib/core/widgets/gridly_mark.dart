// lib/core/widgets/gridly_mark.dart
// 格子记账 LOGO mark —— 复刻 design/THEME.md §1.2 "三个圆角方块的隐喻"
//
// 形态:三个**有机**圆角方块(像鹅卵石/气泡,各角圆度略不同),
// 倒三角排布,**不重叠**,各自轻微旋转:
//
//       ┌─墨─┐ ┌──金──┐
//       │    │ │      │
//       └────┘ └──────┘
//         ┌───青───┐
//         │        │
//         └────────┘
//
// 颜色:Ink / Gold / Teal,深色背景时 Ink 自动换 Cream。
// 用 CustomPainter 直接画有机形状,不用 Container 矩形 + 圆角堆叠。
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GridlyMark extends StatelessWidget {
  const GridlyMark({
    super.key,
    this.size = 28,
    this.onDark = false,
  });

  /// 整体边长(像素)
  final double size;

  /// true = 用在深色背景上(ink 方块 → cream,避免和背景融掉)
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OrganicMarkPainter(
          ink: onDark ? AppSecondary.cream : AppBrand.ink,
          gold: AppBrand.gold,
          teal: AppBrand.teal,
        ),
      ),
    );
  }
}

/// 三个鹅卵石方块:每个 4 个角用略微不同的圆角半径,模拟手绘的不规则感
/// 整体用 CustomPainter 画,精确还原 design 稿形态
class _OrganicMarkPainter extends CustomPainter {
  _OrganicMarkPainter({
    required this.ink,
    required this.gold,
    required this.teal,
  });

  final Color ink;
  final Color gold;
  final Color teal;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // 三个块的中心点(相对)+ 边长 + 旋转角(弧度,顺时针为正)
    // 倒三角:上 2 下 1,无重叠
    final blocks = <_BlockSpec>[
      // 上左:墨(略小,微微左倾)
      _BlockSpec(
        center: Offset(s * 0.26, s * 0.28),
        w: s * 0.46,
        h: s * 0.42,
        rotation: -0.10,
        color: ink,
      ),
      // 上右:金(略大,微右倾)
      _BlockSpec(
        center: Offset(s * 0.74, s * 0.26),
        w: s * 0.50,
        h: s * 0.46,
        rotation: 0.12,
        color: gold,
      ),
      // 下中:青(中等,微左倾)
      _BlockSpec(
        center: Offset(s * 0.50, s * 0.74),
        w: s * 0.48,
        h: s * 0.42,
        rotation: -0.08,
        color: teal,
      ),
    ];

    final paint = Paint()..isAntiAlias = true;
    for (final b in blocks) {
      canvas.save();
      canvas.translate(b.center.dx, b.center.dy);
      canvas.rotate(b.rotation);
      paint.color = b.color;
      canvas.drawPath(_organicRoundedRect(b.w, b.h), paint);
      canvas.restore();
    }
  }

  /// 4 个角用略微不同圆角半径的 rounded rect path
  Path _organicRoundedRect(double w, double h) {
    final w2 = w / 2, h2 = h / 2;
    final rTL = w * 0.22;
    final rTR = w * 0.26;
    final rBR = w * 0.24;
    final rBL = w * 0.20;

    final path = Path()
      ..moveTo(-w2 + rTL, -h2)
      // 顶边
      ..lineTo(w2 - rTR, -h2)
      ..quadraticBezierTo(w2, -h2, w2, -h2 + rTR)
      // 右边
      ..lineTo(w2, h2 - rBR)
      ..quadraticBezierTo(w2, h2, w2 - rBR, h2)
      // 底边
      ..lineTo(-w2 + rBL, h2)
      ..quadraticBezierTo(-w2, h2, -w2, h2 - rBL)
      // 左边
      ..lineTo(-w2, -h2 + rTL)
      ..quadraticBezierTo(-w2, -h2, -w2 + rTL, -h2);
    return path;
  }

  @override
  bool shouldRepaint(_OrganicMarkPainter old) =>
      old.ink != ink || old.gold != gold || old.teal != teal;
}

class _BlockSpec {
  const _BlockSpec({
    required this.center,
    required this.w,
    required this.h,
    required this.rotation,
    required this.color,
  });
  final Offset center;
  final double w, h, rotation;
  final Color color;
}