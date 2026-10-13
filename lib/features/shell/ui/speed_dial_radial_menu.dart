// lib/features/shell/ui/speed_dial_radial_menu.dart
// Speed Dial / Radial Menu —— 轻量半圆弧 ring 提示
//   - 5 个小圆环(投资/福利/债权/不动产/其它)排成 180° 半圆弧
//   - 默认:空心 ring(2px 灰边),只显示轮廓,不抢视觉
//   - hover:填 type 配色 + scale 1.15 + glow shadow
//   - 拖动选(onPanUpdate 跟手),松手 = 选中;拖回中心 = 取消
//   - 极轻 scrim(alpha 0.15),不重遮罩
//   - 弹簧弹出(spring 缩放 + opacity,400ms aquaIn)
//
// 2026-10-13 P6 commit 加:
//   - 第 2 次改(UAT 反馈"不要这种,要小小的"):
//     之前是 360° 全圆 + 大彩圆 + label,太大抢视觉
//     现在是 180° 半圆弧 + 40px ring + 无 label,只在中央 + 上方提示
//
// 几何:
//   - 中心点 = (screenW/2, screenH*0.78)
//   - 5 小圆 = 180° 弧,5 段 36° 间隔,起点 -90°(顶部)
//   - 半径 = 100(中心 → 小圆中心)
//   - 中心 30% 范围 = 取消区(dist < radius*0.4 = 40px)
//   - 选中:scale 1.15,填 type 配色 + glow shadow 12px blur
//   - 未选中:空心 ring(2px outline),size 40px
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';

/// Speed Dial 1 个小圆环(资产分类)
class SpeedDialItem {
  const SpeedDialItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// asset.type 枚举:'investment' / 'benefit' / 'receivable' / 'fixed_asset' / 'other'
  final String key;

  /// 显示文字:'投资' / '福利' / ...(2026-10-13 P6 第 2 次改:不再渲染,只保留 key 用于 jump)
  final String label;

  /// icon chip 中心 icon(选中时填色显示)
  final IconData icon;

  /// 配色(选中时填这个色)
  final Color color;
}

/// Speed Dial / Radial Menu 主 widget
/// - 全屏覆盖(Stack 在 MainShell 之上)
/// - onSelected:用户松手选中了某个 item
/// - onDismiss:用户取消(松手时不在任何 item 上 / 点空白 / tap 中心)
class SpeedDialRadialMenu extends StatefulWidget {
  const SpeedDialRadialMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.onDismiss,
    this.radius = 100,
    this.smallCircleSize = 40,
    this.centerSize = 56,
  });

  final List<SpeedDialItem> items;
  final void Function(SpeedDialItem item) onSelected;
  final VoidCallback onDismiss;
  final double radius;
  final double smallCircleSize;
  final double centerSize;

  @override
  State<SpeedDialRadialMenu> createState() => _SpeedDialRadialMenuState();
}

class _SpeedDialRadialMenuState extends State<SpeedDialRadialMenu>
    with SingleTickerProviderStateMixin {
  /// 0..1 弹出动画进度(0=完全收起,1=完全展开)
  double _expanded = 0;

  /// 当前拖到的小圆 index(null = 在中心取消区 / 还没拖)
  int? _hoveredIndex;

  /// 中心点(ScreenLayout 计算后设置)
  late Offset _center;

  /// 弧形扫过的总角度(2026-10-13 P6 第 2 次改:180° 半圆弧)
  ///   - 默认 360° = 整圈(覆盖 5 个 type),5 段 72° 间隔
  ///   - 180° = 上方半弧,5 段 36° 间隔,起点 -90° 顶
  ///   - 这里 180° 是 user 期望:节省空间,只在上方提示
  static const double _sweepDeg = 180;

  /// 弧形起点角度(2026-10-13 P6 第 2 次改:-90° = 顶部,弧从顶部往左右两边展开)
  ///   - 180° 弧 + 起点 -90° + 终点 +90°(左半 + 顶 + 右半)
  ///   - 5 个 item 在 -90° 到 +90° 之间 36° 等分
  static const double _startDeg = -90;

  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    _anim.addListener(() {
      if (mounted) setState(() => _expanded = _anim.value);
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) => _updateHover(d.localPosition);
  void _onPanUpdate(DragUpdateDetails d) => _updateHover(d.localPosition);

  void _onPanEnd(DragEndDetails d) {
    if (_hoveredIndex != null) {
      widget.onSelected(widget.items[_hoveredIndex!]);
    } else {
      widget.onDismiss();
    }
  }

  /// 短按:用户 tap 空白(包括 scrim)就 dismiss
  void _onTap() => widget.onDismiss();

  /// 根据手指位置算"当前激活的小圆 index"
  /// - 中心区(dist < radius*0.4):取消(null)
  /// - 其他区域:按 angle 算最近小圆(180° 弧,5 段 36° 间隔,起点 -90°)
  void _updateHover(Offset pos) {
    final dx = pos.dx - _center.dx;
    final dy = pos.dy - _center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist < widget.radius * 0.4) {
      if (_hoveredIndex != null) {
        setState(() => _hoveredIndex = null);
      }
      return;
    }

    // atan2 返回 -π..π(-180°..180°),0° = +x(右),90° = +y(下)
    // 我们要的"0° = 顶部"所以 -π/2 = -90° 顶
    var angleDeg = math.atan2(dy, dx) * 180 / math.pi;
    // 旋转:加 90° 让 0° 在顶,1° 在右上,90° 在底,180° 在左,270° 在左上
    angleDeg += 90;
    if (angleDeg < 0) angleDeg += 360;
    if (angleDeg >= 360) angleDeg -= 360;

    // 5 个 item 在 180° 弧内 36° 等分
    // - 起点 -90°(顶),终点 +90°(底)
    // - 实际上 (angleDeg - (-90)) / 36 = (angleDeg + 90) / 36
    // - 但 angleDeg 已经 normalize 到 0..360,-90° = 270°
    // - 180° 弧映射到 270°..360°..90°(跨 0°)
    // - 简单做法:把 angleDeg 重新映射到 -180..180,然后判断
    var relAngle = angleDeg;
    if (relAngle > 180) relAngle -= 360; // 270° → -90°, 315° → -45°
    // 现在 -90° = 顶,+90° = 底
    final clamped = relAngle.clamp(-90.0, 90.0);

    final step = _sweepDeg / widget.items.length; // 36° / item
    // item 0 起点 -90°,index i 在 -90° + i*36° 位置
    final i = ((clamped - _startDeg) / step).round().clamp(
      0,
      widget.items.length - 1,
    );
    if (i != _hoveredIndex) {
      AppHaptics.select();
      setState(() => _hoveredIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 中心点 = 屏宽中点 / 屏高 78%(留顶部 22% 给 status bar + app bar)
        _center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight * 0.78,
        );
        return Stack(
          children: [
            // 极轻 scrim(2026-10-13 P6 第 2 次改:0.45 → 0.15,不重遮)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: Colors.black.withValues(alpha: 0.15 * _expanded),
                ),
              ),
            ),
            // 5 个小圆环(180° 半圆弧排开,无 label,默认 ring hover 填色)
            for (int i = 0; i < widget.items.length; i++) _buildSmallRing(i),
            // 中央大圆(原 + 号位置,保持可见,scale 跟着 expanded 1.0 → 0.85)
            Positioned(
              left: _center.dx - widget.centerSize / 2,
              top: _center.dy - widget.centerSize / 2,
              child: AnimatedScale(
                scale: 0.85 + 0.15 * _expanded,
                duration: const Duration(milliseconds: 400),
                curve: AppMotion.aquaIn,
                child: _buildCenter(),
              ),
            ),
            // 顶层 pan detector 接收拖动 / tap
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onTap: _onTap,
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 单个小圆环(180° 半圆弧布局,默认 ring / hover 填色)
  /// - 位置:中心 + (radius * expanded) * (cos(angle), sin(angle))
  /// - 角度:起点 -90°,5 段 36° 间隔(-90° / -54° / -18° / 18° / 54°)
  /// - 颜色:type 配色;选中时填 type 配色 + scale 1.15 + glow
  /// - 不显示 label(2026-10-13 P6 第 2 次改,user 反馈"小小的就行")
  Widget _buildSmallRing(int i) {
    final angleDeg = _startDeg + (_sweepDeg / (widget.items.length - 1)) * i;
    final rad = angleDeg * math.pi / 180;
    final r = widget.radius * _expanded;
    final dx = _center.dx + r * math.cos(rad);
    final dy = _center.dy + r * math.sin(rad);
    final isHovered = i == _hoveredIndex;
    final item = widget.items[i];
    final scale = isHovered ? 1.15 : 1.0;

    return Positioned(
      left: dx - widget.smallCircleSize / 2,
      top: dy - widget.smallCircleSize / 2,
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.fast,
        curve: AppMotion.aquaIn,
        child: Container(
          width: widget.smallCircleSize,
          height: widget.smallCircleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // hover:填 type 配色;未选:透明(只 border)
            color: isHovered ? item.color : Colors.transparent,
            border: Border.all(
              color: isHovered
                  ? item.color
                  : AppBrand.ink.withValues(alpha: 0.25),
              width: 2,
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          // hover:显示 icon;未选:空白(纯 ring 提示,不抢视觉)
          child: isHovered
              ? Icon(item.icon, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }

  /// 中央大圆(原 + 号)
  Widget _buildCenter() {
    return Container(
      width: widget.centerSize,
      height: widget.centerSize,
      decoration: const BoxDecoration(
        color: AppBrand.ink,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.add_rounded, color: AppBrand.gold, size: 32),
    );
  }
}
