// test/features/add/ui/category_picker_rename_test.dart
// 2026-10-22 D64.95(2026-10-22 D64.97 重写)
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
// 2026-10-22 D64.97 重写的原因:上一版测的是
// `lib/features/add/ui/widgets/category_grid.dart` —— 那个 widget 早期(P1-2)
// 用过,后来 `2d52fa1` / `e800c29` 把 picker 改成**内联 GridView** 之后
// 它就成了**死代码**,测试等于没测到生产界面。
// 现在改成测**真实的** `CategoryPickerTile`(picker 用的就是它)。
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
import 'package:gridly/core/theme/app_spacing.dart';
import 'package:gridly/features/add/ui/widgets/category_picker_tile.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertCat(
    String name,
    String type, {
    required bool isSystem,
    int sortOrder = 0,
  }) async {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        icon: 'more_horiz',
        color: 0xFFA1A1AA,
        type: type,
        isSystem: Value(isSystem),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  testWidgets('D64.95:老设备改名后,分类选择器显示「其它支出」,用户的「其它」不动',
      (tester) async {
    // 老设备状态:系统可见支出兜底还是旧名「其他」
    await insertCat('其他', 'expense', isSystem: true, sortOrder: 99);
    // 用户自建的「其它」(迁移脚本从旧账单搬过来的)
    await insertCat('其它', 'expense', isSystem: false, sortOrder: 122);

    // app 启动时的改名步骤
    await repo.renameSystemCategories();

    final cats = await repo.byType('expense');
    expect(cats.map((c) => c.name).toList(), ['其它支出', '其它']);

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
            body: GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.s4),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: AppSpacing.s2,
                crossAxisSpacing: AppSpacing.s2,
                childAspectRatio: 0.85,
              ),
              itemCount: cats.length,
              itemBuilder: (context, i) => CategoryPickerTile(
                category: cats[i],
                isSelected: false,
                onTap: () {},
              ),
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
