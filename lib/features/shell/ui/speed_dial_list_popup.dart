// lib/features/shell/ui/speed_dial_list_popup.dart
// Speed Dial List Popup —— "输入法长按字母浮出变体"风格(纯 UI 组件)
//
// 2026-10-13 P6 第 11 次改(2026-10-13 13:56 UAT:"长按弹 popup 后,得先
//   松开再触碰才能滑动选"):
//   - 之前自己内部用 Listener 监听 pointer events,失败:
//     - 第 8 次改 GestureDetector → Listener(绕开 gesture arena)
//     - 第 9 次改 localPosition → position(global 坐标)
//     - 第 10 次改 _popupRect → 直接用 size 算
//   - 但 user 反馈"还是不行,得松开再碰" — 说明 Listener 实际
//     没收到 long press 之后的 PointerMove
//   - 第 11 次改:**完全脱离 Overlay 机制**
//     - Listener 移到 main_shell root Stack 内(覆盖全屏)
//     - Listener 跟 _CenterFab 同一 widget tree(都在 main_shell 内),
//       不被 Overlay 隔断,100% 接收 pointer events
//     - hoveredIndex 状态由 main_shell 统一管理
//     - SpeedDialListPopup 退化为纯 UI 组件
//       (接受 hoveredIndex + onHoveredIndexChanged,内部不再有 Listener)
//
// 2026-10-13 P6 第 5 次改(2026-10-13 11:53 UAT):
//   - 从 Speed Dial Radial Menu(5 圆 180° 弧)改成"输入法长按字母浮出"模式
//   - popup 锚定 + 圆上方,5 行垂直 list,跟手滑动选,松手 = 选中
//   - 几何:popup 锚定在 + 圆上方 4px,5 row × 48px,row 高 48px
//     icon chip 32 + 12 gap + name 14sp
//
// 2026-10-13 P6 第 6 次改:移除整体 Transform.scale/Opacity 动画,
//   改用每行 StaggeredFadeIn 错峰 fade-in(20ms 错峰 + 8px 上推 + 360ms aquaIn)
//
// 2026-10-13 P6 第 7 次改:popup 距离 + 圆 10→4px,错峰 30→20ms,下尖角
//   指向 + 圆(CustomPaint 三角形)
import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

/// Speed Dial 1 个 item(资产分类)
class SpeedDialItem {
  const SpeedDialItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

/// Speed Dial List Popup 主 widget(纯 UI,无 Listener)
/// - 全屏覆盖(由父 widget 在 main_shell Stack 内)
///
/// [hoveredIndex]:当前拖到的 row index(由父 widget 算,传入)
/// [onHoveredIndexChanged]:不暴露(父 widget 自己用 Listener + position 算)
class SpeedDialListPopup extends StatefulWidget {
  const SpeedDialListPopup({
    super.key,
    required this.items,
    required this.hoveredIndex,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<SpeedDialItem> items;
  final int? hoveredIndex;
  final void Function(SpeedDialItem item) onSelected;
  final VoidCallback onDismiss;

  @override
  State<SpeedDialListPopup> createState() => _SpeedDialListPopupState();
}

class _SpeedDialListPopupState extends State<SpeedDialListPopup>
    with SingleTickerProviderStateMixin {
  /// 0..1 弹出动画进度
  double _expanded = 0;

  /// popup 内每行高
  static const double _rowHeight = 48;

  /// popup 宽度
  static const double _popupWidth = 200;

  /// popup 顶部 padding
  static const double _popupPadding = 8;

  /// 中心 + 圆在屏幕底部偏移(跟 main_shell 一致)
  /// - 100 = 估算 nav 高度 72 + safe area bottom ~30 - buffer 2
  static const double _fabOffsetFromBottom = 90;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            constraints.maxWidth.isFinite && constraints.maxHeight.isFinite
            ? Size(constraints.maxWidth, constraints.maxHeight)
            : MediaQuery.sizeOf(context);
        // + 圆位置
        final fabCenterX = size.width / 2;
        final fabCenterY = size.height - _fabOffsetFromBottom;
        // popup 锚定在 + 圆上方,gap 4px
        final popupHeight =
            _popupPadding * 2 + widget.items.length * _rowHeight;
        final popupLeft = fabCenterX - _popupWidth / 2;
        // popup 底边 = + 圆顶边上方 4px
        final popupTop = (fabCenterY - 28 - 4 - popupHeight).clamp(
          20.0,
          size.height - popupHeight - 20,
        );

        return Stack(
          children: [
            // 极轻 scrim
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: Colors.black.withValues(alpha: 0.15 * _expanded),
                ),
              ),
            ),
            // popup 主体(纯渲染,不监听 pointer events — 由 main_shell 全屏 Listener 接管)
            Positioned(
              left: popupLeft,
              top: popupTop,
              width: _popupWidth,
              child: _buildPopupContent(),
            ),
          ],
        );
      },
    );
  }

  /// popup 主体:圆角矩形 + 下尖角 + 5 行错峰 fade-in
  Widget _buildPopupContent() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圆角矩形 + 5 行
        Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: _popupPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < widget.items.length; i++)
                    _StaggeredRowFadeIn(
                      index: i,
                      child: _buildRow(i, widget.items[i]),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 下尖角(指向 + 圆,CustomPaint 画三角形)
        CustomPaint(
          size: const Size(20, 10),
          painter: _TrianglePainter(
            fillColor: theme.colorScheme.surface,
            borderColor: theme.colorScheme.outlineVariant,
          ),
        ),
      ],
    );
  }

  /// 单行:icon chip + label,选中 tint 0.12
  Widget _buildRow(int i, SpeedDialItem item) {
    final isHovered = i == widget.hoveredIndex;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelected(item),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          color: isHovered
              ? item.color.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Row(
            children: [
              // icon chip(32px 圆,type 配色)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.color, size: 18),
              ),
              const SizedBox(width: AppSpacing.s3),
              // label
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isHovered ? FontWeight.w600 : FontWeight.w500,
                    color: isHovered ? item.color : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ThemeData get theme => Theme.of(context);
}

/// 行级错峰 fade-in(20ms 错峰 + 8px 上推 + 360ms aquaIn)
class _StaggeredRowFadeIn extends StatefulWidget {
  const _StaggeredRowFadeIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggeredRowFadeIn> createState() => _StaggeredRowFadeInState();
}

class _StaggeredRowFadeInState extends State<_StaggeredRowFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      value: 0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: AppMotion.aquaIn);
    // 20ms 错峰
    Future.delayed(Duration(milliseconds: widget.index * 20), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        return Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _t.value) * 8),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// popup 下尖角(指向 + 圆)
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.fillColor, required this.borderColor});

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = fillColor);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) =>
      old.fillColor != fillColor || old.borderColor != borderColor;
}
