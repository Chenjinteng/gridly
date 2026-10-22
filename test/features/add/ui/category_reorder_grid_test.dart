// test/features/add/ui/category_reorder_grid_test.dart
// 2026-10-22 D64.98 —— 「选分类」sheet 长按拖动排序的交互
//
// 目的:锁死拖动排序的真实交互行为(不是量自己的复刻)
//
// 交互契约:
//   - 长按(350ms)一格 → 拿起;拖到别的格 → 那格成为落点(拖动项插到该格位置)
//   - 落手 → 回调 onReorder(新顺序 = 分类 id 列表)
//   - 原地松手 / 没换位 → **不**回调 onReorder(顺序没变就不该写库)
//   - 快速点一下(不长按)→ 仍然走 onSelect(选分类的老行为没被拖动功能打断)
//   - 拖到网格上下边缘 → 自动滚动(26 个分类 7 行,一屏放不下,必须能滚)
//
// **测量方式**:全部用真实的 pointer 事件(gesture)驱动,量的是真实渲染结果 ——
// 跟 D64.96 / D64.97 总结的坑一致:不要量自己另排一遍的复刻。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/features/add/ui/widgets/category_picker_tile.dart';
import 'package:gridly/features/add/ui/widgets/category_reorder_grid.dart';

/// 造一条分类
Category _cat(int id, String name, {String type = 'expense'}) {
  return Category(
    id: id,
    name: name,
    icon: 'more_horiz',
    color: 0xFF14B8A6,
    type: type,
    isSystem: true,
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  /// 渲染网格:固定尺寸 + 固定列数,让每格的位置可预测
  Widget host(
    List<Category> cats, {
    required ValueChanged<List<int>> onReorder,
    required ValueChanged<int> onSelect,
    ScrollController? controller,
    int crossAxisCount = 4,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 600,
          child: CategoryReorderGrid(
            categories: cats,
            selectedId: null,
            onSelect: onSelect,
            onReorder: onReorder,
            scrollController: controller,
            crossAxisCount: crossAxisCount,
          ),
        ),
      ),
    );
  }

  /// 所有格子(在拖起来之前取 —— 拖起来之后 feedback 里会多出一份)
  List<Offset> tileCenters(WidgetTester tester, int count) {
    final finder = find.byType(CategoryPickerTile);
    expect(finder, findsNWidgets(count));
    return List.generate(
      count,
      (i) => tester.getCenter(finder.at(i)),
    );
  }

  testWidgets('D64.98 长按拖到第 3 格 → 回调新顺序(拖动项插到落点位置)', (
    tester,
  ) async {
    final cats = [_cat(1, '餐饮'), _cat(2, '交通'), _cat(3, '购物'), _cat(4, '住房')];
    List<int>? reordered;
    var selected = -1;

    await tester.pumpWidget(
      host(
        cats,
        onReorder: (ids) => reordered = ids,
        onSelect: (id) => selected = id,
      ),
    );
    await tester.pumpAndSettle();

    final centers = tileCenters(tester, 4);

    // 长按第 1 格 → 拿起
    final gesture = await tester.startGesture(centers[0]);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // 拖到第 3 格(索引 2)
    await gesture.moveTo(centers[2]);
    await tester.pump();

    // 落手
    await gesture.up();
    await tester.pumpAndSettle();

    // 第 1 项被挪到第 3 格的位置 → [2, 3, 1, 4]
    expect(reordered, [2, 3, 1, 4]);
    // 拖动**不是**选中 —— 不该触发 onSelect
    expect(selected, -1);
  });

  testWidgets('D64.98 原地松手(没换位)→ 不回调 onReorder', (tester) async {
    final cats = [_cat(1, '餐饮'), _cat(2, '交通'), _cat(3, '购物')];
    var reorderCount = 0;

    await tester.pumpWidget(
      host(
        cats,
        onReorder: (_) => reorderCount++,
        onSelect: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final centers = tileCenters(tester, 3);

    final gesture = await tester.startGesture(centers[0]);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // 手指都没挪 → 顺序没变
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reorderCount, 0);
  });

  testWidgets('D64.98 快速点一下(不长按)→ 仍然走 onSelect,顺序不变', (
    tester,
  ) async {
    final cats = [_cat(1, '餐饮'), _cat(2, '交通'), _cat(3, '购物')];
    var selected = -1;
    var reorderCount = 0;

    await tester.pumpWidget(
      host(
        cats,
        onReorder: (_) => reorderCount++,
        onSelect: (id) => selected = id,
      ),
    );
    await tester.pumpAndSettle();

    final centers = tileCenters(tester, 3);

    await tester.tapAt(centers[1]);
    await tester.pumpAndSettle();

    expect(selected, 2);
    expect(reorderCount, 0);
  });

  testWidgets('D64.98 拖到下边缘 → 自动滚动(7 行网格必须能滚)', (tester) async {
    // 12 个分类 / 4 列 = 3 行;视口压矮 → 内容超高,可滚
    final cats = List.generate(12, (i) => _cat(i + 1, '分类${i + 1}'));
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 160, // 一屏只放得下 1 行多
            child: CategoryReorderGrid(
              categories: cats,
              selectedId: null,
              onSelect: (_) {},
              onReorder: (_) {},
              scrollController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, 0);

    final finder = find.byType(CategoryPickerTile);
    final start = tester.getCenter(finder.at(0));

    // 长按第 1 格 → 拿起
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // 把指针移到网格下边缘(容器高 160 → 下边缘感应带是 y>104)
    final box = tester.getRect(find.byType(CategoryReorderGrid));
    await gesture.moveTo(Offset(box.center.dx, box.bottom - 4));
    // 让自动滚动的定时器跑几帧
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.offset, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    controller.dispose();
  });
}
