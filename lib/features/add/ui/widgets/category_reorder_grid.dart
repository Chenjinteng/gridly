// lib/features/add/ui/widgets/category_reorder_grid.dart
// 「选分类」sheet 里的分类网格 —— 支持长按拖动排序(D64.98)
//
// 2026-10-22 D64.98:user 提的需求 ——「把常用的人为拖到前面」。
// 方案 A(user 拍板):就在「选分类」这个当场用得着的地方长按拖,
// 不用专门跑去分类管理页 —— 配置跟使用合一,用到才发现不顺手就当场调。
//
// **交互**
//   - 长按(350ms)一格 → 拿起(轻振 + 卡片浮到手指上方),拖到哪格就插到哪格
//   - 拖到网格上下边缘 → 自动滚动(26 个分类 = 7 行,一屏放不下,必须能滚)
//   - 落手 → 写 `categories.sort_order`,分类管理页 / 报表顺序同步跟着变
//
// **为什么不用 ReorderableListView**
//   分类选择器是 4 列网格,ReorderableListView 只能做纵向列表 → 布局得整个重做。
//   这里手写 LongPressDraggable + DragTarget,网格布局一个字没动。
//
// **两个坑(实现时踩过 / 想清楚的)**
//
//   ① **换位死循环**
//      DragTarget 的 `onWillAcceptWithDetails` 是在「进入」时触发的。如果把换位
//      逻辑写在 onWillAccept 里 → 换位 → 重建网格 → 指针底下的 target 换了身份
//      → 又触发 onWillAccept → 反复换位 → 抖动。
//      **解法**:换位只写在 `onMove`(指针真的移动了才换),并且拖动项所在的
//      那一格自己跟自己换没意义 → `_moveDraggedTo` 里 `from == to` 直接跳过。
//      另外 `onWillAcceptWithDetails` 拒绝「拖回自己」,让落点语义更干净。
//
//   ② **自动滚动会不会把 sheet 收起来**
//      网格在 DraggableScrollableSheet 里,直觉上「往上滚到顶」会不会把 sheet
//      拉下去?不会 —— sheet 的尺寸只由 `applyUserOffset`(用户手势)驱动,
//      程序化 `jumpTo` 不走那条路(`goBallistic(0)` 在没拖过 sheet 时直接回落
//      到普通滚动)。所以自动滚动可以放心用 `jumpTo`。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/theme/app_spacing.dart';
import 'category_picker_tile.dart';

/// 可长按拖动排序的分类网格
class CategoryReorderGrid extends StatefulWidget {
  const CategoryReorderGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onReorder,
    this.scrollController,
    this.crossAxisCount = 4,
    this.childAspectRatio = 0.85,
    this.spacing = AppSpacing.s2,
    this.padding = const EdgeInsets.all(AppSpacing.s4),
  });

  /// 父级传进来的分类(顺序 = 当前显示顺序)
  final List<Category> categories;

  /// 当前选中的分类 id(高亮)
  final int? selectedId;

  /// 点一下分类(选中 → 关 sheet)
  final ValueChanged<int> onSelect;

  /// 拖动结束、顺序真的变了 → 回调新顺序(分类 id 列表)
  final ValueChanged<List<int>> onReorder;

  /// 外部 scrollController(DraggableScrollableSheet 给的,自动滚动要用)
  final ScrollController? scrollController;

  final int crossAxisCount;

  /// 卡片宽高比(**D64.97 起保持 0.85 不变** —— 分类名换行是改 tile 内部排版,
  /// 不是改这个比例,卡片尺寸必须跟旧版一致)
  final double childAspectRatio;

  final double spacing;
  final EdgeInsets padding;

  @override
  State<CategoryReorderGrid> createState() => _CategoryReorderGridState();
}

class _CategoryReorderGridState extends State<CategoryReorderGrid> {
  /// 网格的 GlobalKey —— 自动滚动时用来算「指针离上/下边缘多近」
  final GlobalKey _gridKey = GlobalKey();

  /// 当前显示顺序(分类 id)。拖动过程中它是唯一真源,落手后回写给父级。
  List<int> _order = const [];

  /// 正在被拖的分类 id(null = 没在拖)
  int? _draggingId;

  /// 指针的全局坐标(自动滚动用)
  Offset? _pointerGlobal;

  /// 自动滚动定时器(只在拖动期间跑)
  Timer? _autoScrollTimer;

  /// 拖动开始前的顺序(用来判断「顺序到底变没变」)
  List<int> _orderAtDragStart = const [];

  /// 一格的实际宽度(反馈浮层要跟网格里的卡片一样宽)
  double _cellWidth = 0;

  /// 长按多久算「拿起」(比系统默认 500ms 短一点,小格子按久了容易误判成想滚动)
  static const Duration _longPressDelay = Duration(milliseconds: 350);

  /// 上下边缘感应带高度(指针进入这个范围就开始自动滚动)
  static const double _autoScrollEdge = 56.0;

  /// 自动滚动速度(每个 tick = 16ms 的滚动像素,越靠边越快)
  static const double _autoScrollSpeed = 14.0;

  @override
  void initState() {
    super.initState();
    _order = widget.categories.map((c) => c.id).toList();
  }

  @override
  void didUpdateWidget(CategoryReorderGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 拖动过程中不跟外部同步(会跟手指打架)
    if (_draggingId != null) return;
    final incoming = widget.categories.map((c) => c.id).toList();
    if (!_sameIds(incoming, _order)) {
      setState(() => _order = incoming);
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 按 [_order] 排好的分类列表。
  /// 父级多给了新分类(拖动期间被加进来的)→ 追加到末尾,不丢。
  List<Category> _orderedCategories() {
    final byId = <int, Category>{for (final c in widget.categories) c.id: c};
    final result = <Category>[];
    for (final id in _order) {
      final c = byId.remove(id);
      if (c != null) result.add(c);
    }
    result.addAll(byId.values);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cats = _orderedCategories();
    return LayoutBuilder(
      builder: (context, constraints) {
        // 一格的实际宽度 = (可用宽 - 左右 padding - 格间距) / 列数
        final usable = constraints.maxWidth.isFinite
            ? constraints.maxWidth - widget.padding.horizontal
            : 0.0;
        _cellWidth =
            (usable - widget.spacing * (widget.crossAxisCount - 1)) /
            widget.crossAxisCount;
        return GridView.builder(
          key: _gridKey,
          controller: widget.scrollController,
          padding: widget.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.crossAxisCount,
            mainAxisSpacing: widget.spacing,
            crossAxisSpacing: widget.spacing,
            childAspectRatio: widget.childAspectRatio,
          ),
          itemCount: cats.length,
          itemBuilder: (context, i) => _buildCell(cats[i]),
        );
      },
    );
  }

  Widget _buildCell(Category c) {
    final isDragging = _draggingId == c.id;
    return DragTarget<int>(
      // 只接受「不是我自己的」拖动 —— 拖回自己 = 没动
      onWillAcceptWithDetails: (d) => d.data != c.id,
      // 换位只写在 onMove(指针真的移动了才换)—— 理由见文件头「坑 ①」
      onMove: (_) => _moveDraggedTo(c.id),
      builder: (context, candidate, rejected) {
        final isDropTarget = candidate.isNotEmpty && !isDragging;
        return LongPressDraggable<int>(
          data: c.id,
          delay: _longPressDelay,
          // 自己用 AppHaptics.nudge()(app 的触感语义统一在一处),不用内置的
          hapticFeedbackOnStart: false,
          // 反馈浮层:卡片浮到手指**上方**,手指底下那格(落点)才看得见
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _buildFeedback(c),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: CategoryPickerTile(
              category: c,
              isSelected: false,
              onTap: () {},
            ),
          ),
          onDragStarted: () => _onDragStarted(c.id),
          onDragUpdate: (d) => _pointerGlobal = d.globalPosition,
          onDragEnd: (_) => _onDragEnd(),
          onDraggableCanceled: (_, _) => _onDragEnd(),
          child: CategoryPickerTile(
            category: c,
            isSelected: c.id == widget.selectedId,
            isDropTarget: isDropTarget,
            onTap: () => widget.onSelect(c.id),
          ),
        );
      },
    );
  }

  /// 拿起来跟着手指走的那张卡片
  Widget _buildFeedback(Category c) {
    final tile = CategoryPickerTile(
      category: c,
      isSelected: c.id == widget.selectedId,
      onTap: () {},
    );
    if (_cellWidth <= 0) {
      return Material(type: MaterialType.transparency, child: tile);
    }
    final cellHeight = _cellWidth / widget.childAspectRatio;
    return Material(
      type: MaterialType.transparency,
      // pointerDragAnchorStrategy 把反馈层的**左上角**放在手指上,
      // 这里再平移一下 → 卡片水平居中 + 整个浮在手指上方
      child: Transform.translate(
        offset: Offset(-_cellWidth / 2, -cellHeight),
        child: SizedBox(
          width: _cellWidth,
          height: cellHeight,
          child: tile,
        ),
      ),
    );
  }

  /// 换位:把正在拖的那一格挪到 targetId 所在的位置
  void _moveDraggedTo(int targetId) {
    final dragging = _draggingId;
    if (dragging == null) return;
    final from = _order.indexOf(dragging);
    final to = _order.indexOf(targetId);
    // 拖回自己 → 不动(也是「换位死循环」的那道保险)
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      final item = _order.removeAt(from);
      _order.insert(to, item);
    });
  }

  void _onDragStarted(int id) {
    setState(() {
      _draggingId = id;
      _orderAtDragStart = List<int>.from(_order);
    });
    AppHaptics.nudge();
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScroll(),
    );
  }

  void _onDragEnd() {
    // onDragEnd / onDraggableCanceled 可能都触发 → 幂等保护
    if (_draggingId == null) return;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _pointerGlobal = null;
    final changed = !_sameIds(_order, _orderAtDragStart);
    final order = List<int>.from(_order);
    setState(() {
      _draggingId = null;
      _orderAtDragStart = const [];
    });
    if (changed) widget.onReorder(order);
  }

  /// 自动滚动:指针贴到网格上/下边缘时把列表滚一点
  void _autoScroll() {
    final pointer = _pointerGlobal;
    final ctrl = widget.scrollController;
    if (pointer == null || ctrl == null || !ctrl.hasClients) return;
    final box = _viewportBox();
    if (box == null) return;

    final local = box.globalToLocal(pointer);
    final height = box.size.height;
    double delta = 0;
    if (local.dy < _autoScrollEdge) {
      // 越靠上滚得越快
      final t = ((_autoScrollEdge - local.dy) / _autoScrollEdge).clamp(0.0, 1.0);
      delta = -_autoScrollSpeed * t;
    } else if (local.dy > height - _autoScrollEdge) {
      final t = ((local.dy - (height - _autoScrollEdge)) / _autoScrollEdge)
          .clamp(0.0, 1.0);
      delta = _autoScrollSpeed * t;
    }
    if (delta == 0) return;

    final pos = ctrl.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() < 0.5) return;
    // jumpTo 是程序化滚动:不会触发 sheet 的手势收起逻辑(见文件头「坑 ②」)
    pos.jumpTo(target);
  }

  /// 网格可见区域的 RenderBox(用来把指针的全局坐标换算成「离边缘多近」)
  RenderBox? _viewportBox() {
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    RenderObject? ro = ctx.findRenderObject();
    // viewport 是 RenderObject 不是 RenderBox → 往上找一个 RenderBox
    while (ro != null && ro is! RenderBox) {
      ro = ro.parent;
    }
    final box = ro as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box;
  }
}
