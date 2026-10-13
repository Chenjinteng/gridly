// lib/features/shell/ui/speed_dial_list_popup.dart
// Speed Dial List Popup —— "输入法长按字母浮出变体"风格
//   - 长按中央 + 0.4s,从 + 圆位置**往上**弹一个 5 行的 list popup
//   - 拖动选 row(onPanUpdate 跟手),松手 = 选中;拖回中心 = 取消
//   - 极轻 scrim(alpha 0.15),不重遮
//   - 弹簧弹出(spring scale + opacity,400ms aquaIn)
//
// 2026-10-13 P6 commit 第 5 次改(2026-10-13 11:53 UAT):
//   - 之前 Speed Dial Radial Menu(5 圆围绕 + 圆 180° 弧)有 2 个根本问题:
//     1) 5 圆跟 nav 上的中央 + 圆位置错位(Overlay 层和 Scaffold 内的 + 圆分离)
//     2) 5 圆中靠下的几个被 + 圆遮挡(180° 弧必然有一部分在 + 圆高度 ±80px 内)
//   - 改用"输入法长按字母浮出变体"模式:从 + 圆正上方弹出 list popup
//     - 不再画 + 圆(已经在 nav 上,不需要重复)
//     - 5 行垂直 list,无遮挡
//     - popup 锚定在 + 圆上方,看起来像是"长按从 + 圆"冒出
//   - 跟手拖动选行,松手 = 选中;拖回中心/外区 = 取消
//
// 几何:
//   - popup 锚定:左中 = (screenW/2 - popupW/2),底 = nav + 圆顶部上方 10px
//   - popup 内容:5 row × 48px + 12px padding = 264px 高
//   - row 高度 48px,左 icon chip 32 + 12 gap + name 14sp
//   - 中心 30% 范围(dist < height*0.3) = 取消区,松手 dismiss 走默认 cash_flow
import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/staggered_fade_in.dart';

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

/// Speed Dial List Popup 主 widget
/// - 全屏覆盖(Overlay 在 MainShell 之上)
/// - onSelected:用户松手选中了某个 item
/// - onDismiss:用户取消(松手时不在任何 item 上 / tap 中心 / tap 空白)
class SpeedDialListPopup extends StatefulWidget {
  const SpeedDialListPopup({
    super.key,
    required this.items,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<SpeedDialItem> items;
  final void Function(SpeedDialItem item) onSelected;
  final VoidCallback onDismiss;

  @override
  State<SpeedDialListPopup> createState() => _SpeedDialListPopupState();
}

class _SpeedDialListPopupState extends State<SpeedDialListPopup>
    with SingleTickerProviderStateMixin {
  /// 0..1 弹出动画进度
  double _expanded = 0;

  /// 当前拖到的 row index(null = 取消区 / 还没拖)
  int? _hoveredIndex;

  /// popup 内每行高
  static const double _rowHeight = 48;

  /// popup 宽度
  static const double _popupWidth = 200;

  /// popup 顶部 padding
  static const double _popupPadding = 8;

  /// 中心 + 圆在屏幕底部偏移(2026-10-13 第 5 次改:_center 对齐 + 圆)
  ///   - 100 = 估算 nav 高度 72 + safe area bottom ~30 - buffer 2
  static const double _fabOffsetFromBottom = 90;

  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  /// popup 矩形(RenderBox 计算后填)
  Rect? _popupRect;

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

  /// 根据手指位置算"当前激活的 row index"
  /// - 如果手指在 popup 矩形内:算 row index
  /// - 否则:取消(null)
  void _updateHover(Offset pos) {
    if (_popupRect == null) return;
    if (!_popupRect!.contains(pos)) {
      if (_hoveredIndex != null) {
        setState(() => _hoveredIndex = null);
      }
      return;
    }
    // 在 popup 内:算 row index
    final relY = pos.dy - _popupRect!.top - _popupPadding;
    final i = (relY / _rowHeight).floor().clamp(0, widget.items.length - 1);
    if (i != _hoveredIndex) {
      AppHaptics.select();
      setState(() => _hoveredIndex = i);
    }
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
        // popup 锚定在 + 圆上方,gap 10px
        final popupHeight =
            _popupPadding * 2 + widget.items.length * _rowHeight;
        final popupLeft = fabCenterX - _popupWidth / 2;
        // popup 底边 = + 圆顶边上方 10px
        // popup 顶 = (fabCenterY - 28) - 10 - popupHeight
        final popupTop = (fabCenterY - 28 - 10 - popupHeight).clamp(
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
            // popup 主体
            Positioned(
              left: popupLeft,
              top: popupTop,
              width: _popupWidth,
              // 2026-10-13 第 6 次改:移除整体 Transform.scale/Opacity 动画
              //   改用每行 StaggeredFadeIn 错峰 fade-in(30ms 错峰 + 8px 上推)
              //   popup 容器立即显示,无整体淡入
              // 记录 popup Rect(用 Builder 在 widget 实际 layout 完后取)
              child: Builder(
                builder: (innerContext) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final renderBox =
                        innerContext.findRenderObject() as RenderBox?;
                    if (renderBox != null && mounted) {
                      final topLeft = renderBox.localToGlobal(Offset.zero);
                      _popupRect = topLeft & renderBox.size;
                    }
                  });
                  return _buildPopupContent();
                },
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

  /// popup 主体:5 行 InkWell
  /// popup 主体:圆角矩形 + 下尖角 + 5 行错峰 fade-in
  /// - 整体无整体 fade/scale(2026-10-13 第 6 次改)
  /// - 每行用 StaggeredFadeIn(index: i, enabled: true) 30ms 错峰 + 8px 上推 + 360ms aquaIn
  /// - 视觉上"从 + 圆冒出"逐行生长
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
                    StaggeredFadeIn(
                      index: i,
                      enabled: true, // popup 每次开都触发一次错峰(dismiss 后重建)
                      child: _buildRow(i, widget.items[i]),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 下尖角(指向 + 圆,CustomPaint 画三角形)
        // 跟圆角矩形同色 + 同 border 颜色,视觉上像"对话框"的小尾巴
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

  /// 单行:icon chip + label,选中 tint 0.10
  Widget _buildRow(int i, SpeedDialItem item) {
    final isHovered = i == _hoveredIndex;
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

/// 2026-10-13 P6 加:popup 下尖角(指向 + 圆)
// - 跟圆角矩形同色 + 同 border 颜色,视觉上像"对话框"的小尾巴
// - 12-20px 宽 × 10px 高,顶边贴齐矩形底边,顶点朝下指向 + 圆
// - 用 CustomPaint 一次性画 fill + 两条斜边 border(顶边被矩形覆盖不画)
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.fillColor, required this.borderColor});

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 三角形 path(0,0) → (W,0) → (W/2, H) 闭合
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    // 填充
    canvas.drawPath(path, Paint()..color = fillColor);

    // 画两条斜边 border(顶边被矩形覆盖,不画)
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
