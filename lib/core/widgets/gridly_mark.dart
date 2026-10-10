// lib/core/widgets/gridly_mark.dart
// 格子记账 LOGO mark —— 复刻 design/THEME.html §1.2 + 1.2 三个圆角方块
//
// 设计稿 HTML(line 68-75):
//   .logo3{
//     display:grid; grid-template-columns:1fr 1fr; gap:8px;
//     width:120px; height:120px;
//     transform:rotate(-8deg);
//   }
//   i:nth-child(1){grid-column:1;grid-row:1;background:ink}   // 左上
//   i:nth-child(2){grid-column:2;grid-row:1;background:gold}  // 右上
//   i:nth-child(3){grid-column:2;grid-row:2;background:teal}  // 右下
//   i { border-radius:20px }  // 16.67% 边长
//
// 复刻要点:
//   - 2x2 网格,3 块各占一格(右下那格是第 3 块,左下是空的)
//   - 整组旋转 -8°(不是各块独立旋转)
//   - 圆角 16.67% 边长(gap 6.67%)
//   - 深色底上 ink → cream,避免和背景融掉
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

  /// true = 用在深色背景上(ink 方块 → cream)
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GridMarkPainter(
          ink: onDark ? AppSecondary.cream : AppBrand.ink,
          gold: AppBrand.gold,
          teal: AppBrand.teal,
        ),
      ),
    );
  }
}

/// 精确复刻 design.html .logo3:
///   - 整体 -8° 旋转
///   - 2x2 网格,3 块各占一格,左下空
///   - gap 6.67%,圆角 16.67% 边长
class _GridMarkPainter extends CustomPainter {
  _GridMarkPainter({
    required this.ink,
    required this.gold,
    required this.teal,
  });

  final Color ink;
  final Color gold;
  final Color teal;

  // design.html 比例常量
  static const double _gapRatio = 8 / 120;        // 6.67%
  static const double _radiusRatio = 20 / 120;    // 16.67%
  static const double _rotationRad = -0.1396;     // -8°

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final gap = s * _gapRatio;
    final cellSize = (s - gap) / 2;
    final radius = cellSize * _radiusRatio;

    // 整组先旋转 -8°(以中心为轴)
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(_rotationRad);
    canvas.translate(-s / 2, -s / 2);

    final paint = Paint()..isAntiAlias = true;
    // 左上(1,1):墨
    paint.color = ink;
    _drawBlock(canvas, paint, Rect.fromLTWH(0, 0, cellSize, cellSize), radius);
    // 右上(2,1):金
    paint.color = gold;
    _drawBlock(
      canvas,
      paint,
      Rect.fromLTWH(cellSize + gap, 0, cellSize, cellSize),
      radius,
    );
    // 右下(2,2):青
    paint.color = teal;
    _drawBlock(
      canvas,
      paint,
      Rect.fromLTWH(cellSize + gap, cellSize + gap, cellSize, cellSize),
      radius,
    );

    canvas.restore();
  }

  void _drawBlock(Canvas canvas, Paint paint, Rect rect, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GridMarkPainter old) =>
      old.ink != ink || old.gold != gold || old.teal != teal;
}