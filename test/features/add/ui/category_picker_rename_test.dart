// test/features/add/ui/category_picker_rename_test.dart
// 2026-10-22 D64.95
//
// 目的:锁死「老设备改名后,用户在记一笔里看到的是新名」
//
// 这是 D64.95 的用户可见结果 —— 分类选择器里原本有两条一字之差的:
//   「其他」(系统可见支出兜底)
//   「其它」(用户自建)
// 改名后必须变成:
//   「其它支出」(系统)
//   「其它」(用户,保持不动)
//
// 测试结构跟生产一致(独立 root ProviderContainer + UncontrolledProviderScope),
// 不用 ProviderScope(overrides:) —— 那会多一层子 container。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/features/add/ui/widgets/category_grid.dart';

void main() {
  testWidgets('D64.95:老设备改名后,分类选择器显示「其它支出」,用户的「其它」不动',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = CategoryRepository(db);

    // 老设备状态:系统可见支出兜底还是旧名「其他」
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '其他',
        icon: 'more_horiz',
        color: 0xFFA1A1AA,
        type: 'expense',
        isSystem: const Value(true),
        sortOrder: const Value(99),
      ),
    );
    // 用户自建的「其它」(迁移脚本从旧账单搬过来的)
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '其它',
        icon: 'more_horiz',
        color: 0xFFA1A1AA,
        type: 'expense',
        isSystem: const Value(false),
        sortOrder: const Value(122),
      ),
    );

    // app 启动时的改名步骤
    await repo.renameSystemCategories();

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: CategoryGrid(
              type: 'expense',
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('其它支出'), findsOneWidget,
        reason: '系统那条应该已经改名成「其它支出」');
    expect(find.text('其它'), findsOneWidget,
        reason: '用户自建的那条保持「其它」不动');
    expect(find.text('其他'), findsNothing,
        reason: '旧名不该再出现在选择器里');
  });
}
