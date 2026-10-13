// lib/features/shell/ui/speed_dial_list_popup.dart
// Speed Dial List Popup —— "输入法长按字母浮出变体"风格
//
// 2026-10-13 P6 第 12 次改(2026-10-13 14:11 UAT:"之前滑动能选,改了之后反而不行"):
//   - 第 11 次改让 main_shell._computeHoveredIndex 用 MediaQuery.sizeOf,
//     算的 size = full screen height(包含 statusBar)
//   - SpeedDialListPopup 用 LayoutBuilder.constraints.maxHeight,
//     算的 size = Stack 高度(screen - statusBar - bottomNav)
//   - 两者不同,导致 fabCenterY / popupTop 算错,popupRect.contains(globalPos)
//     永远 false,row 算不出来
//   - 修法:把 Listener 放回 SpeedDialListPopup 内(全屏透明 Listener 覆盖整个屏幕),
//     跟 main_shell 共用 LayoutBuilder 的 size,rowIndex 算算法跟 popup 位置一致
//   - 通过 onHoveredIndexChanged callback 把 rowIndex 传出给 main_shell
//   - main_shell 保留 _speedDialOpen 状态(开/关),_hoveredIndex 状态(高亮 row)
//
// 2026-10-13 P6 第 11 次改(2026-10-13 13:56 UAT):
//   - 之前 Listener 在 Overlay 内(在 SpeedDialListPopup 内部),user 反馈
//     "得先松开再触碰才能滑动选"——Listener 在 long press 触发时收不到
//     pointer events(guesture arena 冲突)
//   - 第 11 次改把 Listener 移到 main_shell root Stack 内,但 size 算法
//     不一致,导致这次"之前滑动能选,改了之后反而不行"
//
// 2026-10-13 P6 第 5 次改(2026-10-13 11:53 UAT):
//   - 从 Speed Dial Radial Menu(5 圆 180° 弧)改成"输入法长按字母浮出"模式
//   - popup 锚定 + 圆上方,5 行垂直 list,跟手滑动选,松手 = 选中
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

/// Speed Dial List Popup 主 widget
///   - 全屏覆盖(由父 widget 在 main_shell Stack 内)
///   - 内部用全屏透明 Listener 接管 pointer events(跟 _CenterFab 同 widget tree)
///   - row index 通过 [onHoveredIndexChanged] 传出给 main_shell
class SpeedDialListPopup extends StatefulWidget {
  const SpeedDialListPopup({
    super.key,
    required this.items,
    required this.hoveredIndex,
    required this.onHoveredIndexChanged,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<SpeedDialItem> items;
  final int? hoveredIndex;
  final void Function(int? index) onHoveredIndexChanged;
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

  /// 中心 + 圆在屏幕底部偏移
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
            // popup 主体
            Positioned(
              left: popupLeft,
              top: popupTop,
              width: _popupWidth,
              child: _buildPopupContent(),
            ),
            // 2026-10-13 P6 第 12 次改:全屏透明 Listener 接管 pointer events
            //   - 覆盖整个屏幕(Positioned.fill)
            //   - 跟 _CenterFab 同 widget tree(都在 main_shell Stack 内),
            //     100% 接收 pointer events,不被 Overlay 隔断
            //   - 跟 popup 主体共用 LayoutBuilder 的 size,rowIndex 算法一致
            //   - HitTestBehavior.translucent 让 popup 主体内的 InkWell 也能 tap
            Positioned.fill(
              child: Listener(
                onPointerMove: (e) =>
                    _onPointerMove(e, popupTop, popupLeft, popupHeight, size),
                onPointerUp: (e) =>
                    _onPointerUp(e, popupTop, popupLeft, popupHeight, size),
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        );
      },
    );
  }

  void _onPointerMove(
    PointerEvent e,
    double popupTop,
    double popupLeft,
    double popupHeight,
    Size size,
  ) {
    final i = _computeRowIndex(
      e.position,
      popupTop,
      popupLeft,
      popupHeight,
      size,
    );
    if (i != widget.hoveredIndex) {
      widget.onHoveredIndexChanged(i);
    }
  }

  void _onPointerUp(
    PointerEvent e,
    double popupTop,
    double popupLeft,
    double popupHeight,
    Size size,
  ) {
    final i = _computeRowIndex(
      e.position,
      popupTop,
      popupLeft,
      popupHeight,
      size,
    );
    if (i != null) {
      widget.onSelected(widget.items[i]);
    } else {
      widget.onDismiss();
    }
  }

  /// 根据 global position 算 hovered row
  ///   - popupRect 跟 build 内 Positioned 用的值一致(同 LayoutBuilder)
  ///   - pointer 在 popup 外 → null
  int? _computeRowIndex(
    Offset globalPos,
    double popupTop,
    double popupLeft,
    double popupHeight,
    Size size,
  ) {
    final popupRect = Rect.fromLTWH(
      popupLeft,
      popupTop,
      _popupWidth,
      popupHeight,
    );
    if (!popupRect.contains(globalPos)) return null;
    final relY = globalPos.dy - popupTop - _popupPadding;
    final i = (relY / _rowHeight).floor().clamp(0, widget.items.length - 1);
    return i;
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
              // 2026-10-13 P6 UAT fix:矩形不画底边 border
              //   - 之前 Border.all 4 边全画,矩形底边 1px outlineVariant
              //     跟下方三角形的 fill 顶边 anti-alias 接缝,看起来像"横线"
              //     截图标红框框那里
              //   - 改 Border.only(top/left/right),底边 0
              //   - 三角形 fillColor 同 surface,接缝平滑
              //   - 三角形两条斜边 border 从矩形左/右 border 起点延伸,
              //     形成完整 5 边包围(上/左/右 + 两条斜下)
              // 注:Flutter 4.x 改用 BorderDirectional 或自己 const Border 4 边改 side
              // 这里用最稳的 Border.all 然后在 _TrianglePainter 调整
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
                right: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
                bottom: const BorderSide(color: Color(0x00000000), width: 0),
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
