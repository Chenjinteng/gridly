// lib/core/theme/ledger_grid_background.dart
// 全局"格子纸"背景 —— 16×16 网格线 + 64×64 处小十字 marker,呼应"格子"主题。
// 放在 main_shell Stack 底层,所有 Tab 自动继承。
// 主题切换时颜色随 light/dark 自动切换。
import 'package:flutter/material.dart';

class LedgerGridBackground extends StatelessWidget {
  const LedgerGridBackground({
    super.key,
    this.cellSize = 16,
    this.markerEvery = 4,
  });

  /// 主网格线间距(默认 16px,与 AppSpacing.s4 对齐)
  final double cellSize;

  /// 每 N 个 cell 画一个十字 marker(N=4 即每 64px 出现一个)
  final int markerEvery;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _LedgerGridPainter(
          lineColor: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
          lineAlpha: isDark ? 0.5 : 0.65,
          markerAlpha: isDark ? 0.45 : 0.55,
          cellSize: cellSize,
          markerEvery: markerEvery,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LedgerGridPainter extends CustomPainter {
  _LedgerGridPainter({
    required this.lineColor,
    required this.lineAlpha,
    required this.markerAlpha,
    required this.cellSize,
    required this.markerEvery,
  });

  final Color lineColor;
  final double lineAlpha;
  final double markerAlpha;
  final double cellSize;
  final int markerEvery;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: lineAlpha)
      ..strokeWidth = 0.5
      ..isAntiAlias = true;
    final markerPaint = Paint()
      ..color = lineColor.withValues(alpha: markerAlpha)
      ..strokeWidth = 0.7
      ..isAntiAlias = true;

    // 主网格线(竖 + 横)
    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // 每 markerEvery 个 cell 加一个小十字 marker
    final markerStep = cellSize * markerEvery;
    if (markerStep <= 0) return;
    for (double x = markerStep; x <= size.width + markerStep; x += markerStep) {
      for (double y = markerStep; y <= size.height + markerStep; y += markerStep) {
        final cx = x - markerStep / 2;
        final cy = y - markerStep / 2;
        canvas.drawLine(
          Offset(cx - 2, cy),
          Offset(cx + 2, cy),
          markerPaint,
        );
        canvas.drawLine(
          Offset(cx, cy - 2),
          Offset(cx, cy + 2),
          markerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LedgerGridPainter old) =>
      old.lineColor != lineColor ||
      old.cellSize != cellSize ||
      old.markerEvery != markerEvery ||
      old.lineAlpha != lineAlpha ||
      old.markerAlpha != markerAlpha;
}