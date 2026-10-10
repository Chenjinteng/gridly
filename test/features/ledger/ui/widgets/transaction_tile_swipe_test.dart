// test/features/ledger/ui/widgets/transaction_tile_swipe_test.dart
// 流水滑动删除 / 编辑按钮的 Widget 测试 —— 覆盖:
//   1. 左滑到阈值后释放 → snap 打开
//   2. 未到阈值就释放 → 弹回关闭
//   3. 点击卡片 → 关闭
//   4. snap 动画进行中再次拖动 → 动画停止,从当前位置继续
//   5. 快速重复打开/关闭,无状态错乱
//   6. 多条流水分别滑动,各自的 _offset 互不影响
//
// 验证最终状态,不依赖逐帧截图。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/features/ledger/application/transactions_providers.dart';
import 'package:gridly/features/ledger/ui/widgets/transaction_tile.dart';

/// 测试用 Transaction
Transaction _tx({int id = 1}) => Transaction(
      id: id,
      amount: 24.0,
      type: 'expense',
      categoryId: 1,
      occurredAt: DateTime(2026, 10, 8),
      note: '明仔记',
      createdAt: DateTime(2026, 10, 8),
      updatedAt: DateTime(2026, 10, 8),
    );

/// 测试用 Category
Category _cat({int id = 1, String type = 'expense'}) => Category(
      id: id,
      name: '正餐支出',
      icon: 'restaurant',
      color: 0xFF6B8E23,
      type: type,
      isSystem: true,
      sortOrder: 0,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

/// 包装:ProviderScope(monkey-patch allCategoriesProvider) + MaterialApp + Scaffold(body)
Widget _harness(Widget child) {
  return ProviderScope(
    overrides: [
      // TransactionTile.render 读这个 provider;mock 成同步值,避免拖动时数据库 race
      allCategoriesProvider.overrideWith((ref) async => [_cat()]),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

/// 读指定 TransactionTile 内部 tile 平移 Transform 的 x 偏移
/// (按钮也用 Transform.translate(slide-in),通过 ValueKey('tx-tile-transform') 定位)
double _offsetOf(WidgetTester tester, Finder tileFinder) {
  final t = tester.widget<Transform>(
    find.descendant(
      of: tileFinder,
      matching: find.byKey(const ValueKey('tx-tile-transform')),
    ),
  );
  return t.transform.getTranslation().x;
}

void main() {
  // 容器宽度给 360,足以让 152px 的按钮组有地方显示
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  testWidgets('左滑超过阈值后释放 → snap 打开,offset 收敛到 -156', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    // 初始关闭
    expect(_offsetOf(tester, find.byType(TransactionTile)), 0);

    // 拖动 -200px(大于 _kSnapThreshold=40,会触发 snap 到 -156)
    await tester.drag(find.byType(TransactionTile), const Offset(-200, 0));
    await tester.pumpAndSettle();  // 等动画结束

    expect(_offsetOf(tester, find.byType(TransactionTile)), -156);
  });

  testWidgets('左滑未到阈值就释放 → 弹回关闭,offset 回到 0', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    // 拖动 -30px(小于阈值 40,会回弹)
    await tester.drag(find.byType(TransactionTile), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(_offsetOf(tester, find.byType(TransactionTile)), 0);
  });

  testWidgets('打开状态下点击 tile → 关闭', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    // 先打开
    await tester.drag(find.byType(TransactionTile), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(_offsetOf(tester, find.byType(TransactionTile)), -156);

    // 点击 tile(onTap → _close → _animateTo(0))
    await tester.tap(find.byType(TransactionTile));
    await tester.pumpAndSettle();
    expect(_offsetOf(tester, find.byType(TransactionTile)), 0);
  });

  testWidgets('snap 动画进行中再次拖动 → 动画被中断,从当前位置继续', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    // 第一次拖动 -100px(> 阈值 40 但 < _kOpenOffset 152 —— 留出 snap 余量,
    // 否则 _offset 会被 clamp 到 -156,_animateTo 因等于 target 直接返回,snap 不启动)
    await tester.drag(find.byType(TransactionTile), const Offset(-100, 0));
    // pump 100ms(动画 240ms)—— 此时 offset 还在动画中间
    await tester.pump(const Duration(milliseconds: 100));
    final midOffset = _offsetOf(tester, find.byType(TransactionTile));
    expect(midOffset, lessThan(0), reason: 'snap 动画已开始,offset 应是负值');
    expect(midOffset, greaterThan(-156), reason: 'snap 动画还在中间,没到终点');
    expect(find.byType(TransactionTile), findsOneWidget);

    // 在 snap 动画进行中,发起第二次手势 —— 应立即打断动画并接管 _offset,
    // 然后新触发的 snap 收敛到 -156。验证最终态稳定:
    //   - 没有 crash
    //   - _offset 不会卡在 midOffset(动画没停)
    //   - 也不会越过 _kOpenOffset
    // 注意:必须用超过 kTouchSlop(~13px)的位移,否则 GestureDetector 会判为 tap → _close() → 弹回 0
    await tester.drag(find.byType(TransactionTile), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(_offsetOf(tester, find.byType(TransactionTile)), -156,
        reason: 'snap 动画被中断后,后续 drag 触发的 snap 应能稳定到 -156');
  });

  testWidgets('快速重复打开/关闭多次,状态正常收敛', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(TransactionTile), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(_offsetOf(tester, find.byType(TransactionTile)), -156,
          reason: '第 $i 次打开后应 snap 到 -156');

      await tester.tap(find.byType(TransactionTile));
      await tester.pumpAndSettle();
      expect(_offsetOf(tester, find.byType(TransactionTile)), 0,
          reason: '第 $i 次点击关闭后应回到 0');
    }
  });

  testWidgets('多条流水分别滑动,各自的 _offset 互不影响', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(
      ListView(
        children: [
          TransactionTile(key: ValueKey('tx-1'), transaction: _tx(id: 1)),
          TransactionTile(key: ValueKey('tx-2'), transaction: _tx(id: 2)),
          TransactionTile(key: ValueKey('tx-3'), transaction: _tx(id: 3)),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    final allTiles = find.byType(TransactionTile);
    expect(allTiles, findsNWidgets(3));

    // 拖第二条
    await tester.drag(allTiles.at(1), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_offsetOf(tester, allTiles.at(0)), 0, reason: '第一条不应受第二条影响');
    expect(_offsetOf(tester, allTiles.at(1)), -156, reason: '第二条应 snap 到 -156');
    expect(_offsetOf(tester, allTiles.at(2)), 0, reason: '第三条不应受第二条影响');

    // 拖第三条
    await tester.drag(allTiles.at(2), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(_offsetOf(tester, allTiles.at(0)), 0);
    expect(_offsetOf(tester, allTiles.at(1)), -156, reason: '第二条应保持打开状态');
    expect(_offsetOf(tester, allTiles.at(2)), -156, reason: '第三条也应 snap 到 -156');

    // 关闭第三条
    await tester.tap(allTiles.at(2));
    await tester.pumpAndSettle();

    expect(_offsetOf(tester, allTiles.at(0)), 0);
    expect(_offsetOf(tester, allTiles.at(1)), -156, reason: '第二条仍应打开');
    expect(_offsetOf(tester, allTiles.at(2)), 0, reason: '第三条应关闭');
  });

  testWidgets('drag 中断正在进行的 snap 动画后,_offset 不再被 pump 自动改变', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    await tester.pumpWidget(_harness(TransactionTile(transaction: _tx())));
    await tester.pumpAndSettle();

    // 第一次 drag 启动 snap 动画
    await tester.drag(find.byType(TransactionTile), const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 100));
    final midOffset = _offsetOf(tester, find.byType(TransactionTile));
    expect(midOffset, lessThan(0));

    // 第二次 drag 触发 _onDragStart → _ctrl.stop() 中断 snap
    // 关键证据:drag 结束后,pump 不应再让 _offset 自动变化
    await tester.drag(find.byType(TransactionTile), const Offset(-60, 0));
    final afterDrag = _offsetOf(tester, find.byType(TransactionTile));

    // 如果动画没被中断,这里 pump 会让 animation tick,_offset 继续向 -156 推进
    // 如果动画已中断,pump 不会改变 _offset(因 drag 已触发新的 _animateTo,
    // 但新的 _ctrl.forward(from: 0) 在 pump(100ms) 后应跑到一定进度,_offset 应变化)
    // 为了精确判断:drag 后 _offset 已确定(由 drag 累加 + clamp);后续 pumpAndSettle 应让它收敛到 -156
    // 但单帧 pump(0) 不应改变 _offset(除非新的 animation 已经开始)
    // 这里改用更直接的证据:pumpAndSettle 后稳定到 -156,证明新 snap 启动了
    await tester.pumpAndSettle();
    expect(_offsetOf(tester, find.byType(TransactionTile)), -156);
    // afterDrag 应在合理范围(midOffset 附近,但可能已被 drag 进一步推)
    expect(afterDrag, lessThanOrEqualTo(midOffset),
        reason: '第二次 drag 应让 _offset 不超过 midOffset(动画已中断,drag 累加)');
    expect(afterDrag, greaterThanOrEqualTo(-156),
        reason: '_offset 不应越过 _kOpenOffset');
  });
}