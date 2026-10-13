// lib/features/shell/ui/speed_dial_radial_menu.dart
// Speed Dial / Radial Menu —— Apple Watch Force Touch 风格
//   - 大圆是主按钮(中央 +),周围 5 个小圆(投资/福利/债权/不动产/其它)
//   - 拖动选小圆(onPanUpdate 跟手),松手 = 选中;拖回中心 = 取消
//   - 弹簧弹出(spring 缩放 + opacity,400ms aquaIn)
//   - 选中反馈:scale 1.15 + glow shadow
//
// 2026-10-13 P6 commit 加:
//   - 中央 + 长按 0.4s 弹 5 小圆,选完后跳 AddTransactionPage 预设
//     preselectedAssetType = 该小圆 key
//   - 短按 0.4s 内松手走默认(preselectedAssetType = 'cash_flow' = 现金流)
//   - 跟手反馈:小圆在拖到时 scale + glow,AppHaptics.selectionClick 触发
//
// 几何:
//   - 中心点 = (screenW/2, screenH*0.78) —— 留顶部 22% 空间给 status bar / app bar
//   - 5 小圆 = 360/5 = 72° 等分,起点 -90°(顶部)
//   - radius = 110(中心 → 小圆中心)
//   - 中心 30% 范围 = 取消区(dist < radius*0.4 = 44px)
//   - 选中:scale 1.15,外发光 shadow 16px blur
//   - 未选中:scale 1.0,普通 shadow
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';

/// Speed Dial 1 个小圆(资产分类)
class SpeedDialItem {
  const SpeedDialItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// asset.type 枚举:'investment' / 'benefit' / 'receivable' / 'fixed_asset' / 'other'
  final String key;

  /// 显示文字:'投资' / '福利' / ...
  final String label;

  /// icon chip 中心 icon
  final IconData icon;

  /// 配色(跟 asset_type 配色一致)
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
    this.radius = 110,
    this.smallCircleSize = 56,
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
  /// - 其他区域:按 angle 算最近小圆(72° 等分,起点 -90° 顶部)
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

    // atan2:返回 -π..π (-180°..180°),0° = +x(右),90° = +y(下)
    // 我们要的"0° = 顶部"所以 -π/2 = -90° 顶
    var angleDeg = math.atan2(dy, dx) * 180 / math.pi;
    // 旋转:加 90° 让 0° 在顶,1° 在右上,90° 在底,180° 在左,270° 在左上
    angleDeg += 90;
    if (angleDeg < 0) angleDeg += 360;
    if (angleDeg >= 360) angleDeg -= 360;

    final step = 360 / widget.items.length; // 72° / item
    final i = (angleDeg / step).floor() % widget.items.length;
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
            // 半透明 scrim(只画背景,不拦截手势)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: Colors.black.withValues(alpha: 0.45 * _expanded),
                ),
              ),
            ),
            // 5 个小圆(围绕中心 radial 排开)
            for (int i = 0; i < widget.items.length; i++) _buildSmallCircle(i),
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

  /// 单个小圆
  /// - 位置:中心 + (radius * expanded) * (cos(angle), sin(angle))
  /// - 颜色:type 配色;选中时加 scale 1.15 + glow shadow
  /// - 文字:在圆下方 6px 浮动,选中时更亮
  Widget _buildSmallCircle(int i) {
    final angleDeg = -90.0 + (360 / widget.items.length) * i;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小圆本体
            Container(
              width: widget.smallCircleSize,
              height: widget.smallCircleSize,
              decoration: BoxDecoration(
                color: isHovered
                    ? item.color
                    : item.color.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: isHovered
                    ? [
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.55),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(item.icon, color: Colors.white, size: 26),
            ),
            // 圆下方文字标签(始终显示,选中时更亮)
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                color: isHovered
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.75),
              ),
              child: Text(item.label),
            ),
          ],
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
