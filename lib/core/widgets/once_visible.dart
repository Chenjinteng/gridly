// lib/core/widgets/once_visible.dart
// viewport-aware 一次性触发 wrapper
//
// 2026-10-16 D64.89 抽:3 个 chart widget(asset_allocation_chart / assets_radar /
//   expense_analysis._AccountTab)各复制 50+ 行 viewport-aware 触发 boilerplate:
//   - initState postFrameCallback + Scrollable.maybeOf + addListener
//   - _appeared flag + GlobalKey + setState
//   - dispose removeListener
//   - _checkInView:LocalToGlobal + RenderBox 几何判定
//   boilerplate 100% 一致,只 child widget 不同
//
// 抽 OnceVisible wrapper:
//   - 内部管 _appeared / _scrollPos / _key 全生命周期
//   - builder 收 appeared bool,child widget 用它触发入场动画
//   - 用完即清(once):_appeared=true 后 _scrollPos?.removeListener,避免 leak
//   - 替代 child widget 自己管 GlobalKey + ScrollPosition,3 处共用 0 重复
//
// 用法(替换前 50 行 boilerplate,只要 ~10 行):
//   ```dart
//   OnceVisible(
//     builder: (context, appeared) => SomeChart(
//       data: ...,
//       play: appeared, // 圆环 / 雷达等 chart 的入场动画开关
//     ),
//   )
//   ```
import 'package:flutter/material.dart';

class OnceVisible extends StatefulWidget {
  const OnceVisible({super.key, required this.builder});

  /// child widget builder,第二个参数 `appeared` 是 viewport-aware 触发结果
  ///   - false:widget 还没进入 scroll viewport,child 不触发入场动画
  ///   - true:viewport 进入后,child 开始 forward(一次性,不再重置)
  final Widget Function(BuildContext context, bool appeared) builder;

  @override
  State<OnceVisible> createState() => _OnceVisibleState();
}

class _OnceVisibleState extends State<OnceVisible> {
  bool _appeared = false;
  final GlobalKey _key = GlobalKey();
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    // 第一次 build 后 frame 完成,ref 拿 ancestors(Scrollable)再 addListener
    //   - 之前 3 处各 inline 同样套路(commit 之前 review D64.7 写的)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollPos = Scrollable.maybeOf(context)?.position;
      _scrollPos?.addListener(_checkInView);
      _checkInView();
    });
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  void _checkInView() {
    if (_appeared) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final scrollableBox =
        _scrollPos?.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollableBox == null) return;
    // widget 顶在 viewport 内 + widget 底超出 viewport 顶
    // = widget 至少有一半进入 viewport 才 forward(几何判定)
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      _appeared = true;
      _scrollPos?.removeListener(_checkInView); // once
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.builder(context, _appeared),
    );
  }
}
