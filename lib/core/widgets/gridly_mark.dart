// lib/core/widgets/gridly_mark.dart
// 格子记账 LOGO mark —— 三个圆角方块叠加(经典 Bauhaus 排布),
//   前左:Ink(主色,放最前面)
//   后右:Gold(顶部)
//   后右:Teal(底部)
// 复刻 assets/images/logo/logo_primary.jpg 的形态。
//
// 用法:在卡片/页头/Settings 关于页用 `GridlyMark(size: 24)`。
// 深色背景上把 `onDark: true`,黑方块自动换成米白(否则会和底色融成一片)。
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GridlyMark extends StatelessWidget {
  const GridlyMark({
    super.key,
    this.size = 24,
    this.onDark = false,
  });

  /// 整体边长(像素)
  final double size;

  /// true = 用在深色背景上(ink 方块 → cream)
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? AppSecondary.cream : AppBrand.ink;
    final s = size;
    final block = s * 0.62;       // 每个方块边长
    final r = s * 0.18;           // 圆角
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        children: [
          // 后右·上:金
          Positioned(
            right: 0,
            top: 0,
            child: _block(block, AppBrand.gold, r),
          ),
          // 后右·下:青
          Positioned(
            right: 0,
            bottom: 0,
            child: _block(block, AppBrand.teal, r),
          ),
          // 前左:墨(覆盖在金/青之上)
          Positioned(
            left: 0,
            top: s * 0.16,
            child: _block(block, ink, r),
          ),
        ],
      ),
    );
  }

  Widget _block(double sz, Color color, double r) {
    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}