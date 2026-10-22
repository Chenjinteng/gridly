// test/core/database/category_reorder_test.dart
// 2026-10-22 D64.98 —— 长按拖动排序的落库口径
//
// 背景:D64.98 给「选分类」sheet 加了长按拖动排序,拖完把新顺序写回
// `categories.sort_order`。本文件锁死写库口径,避免以后有人改成
// 「只改被拖的那一两个」导致排序出现空洞 / 跨 type 串味。
//
// 本文件锁死 6 件事:
//   1. 拖完 byType() 读出来的顺序 == 传入的顺序
//   2. 只动当前 type —— 收入的 sortOrder 一行不碰
//   3. 没传进来的分类按原相对次序追加在后面(不丢分类)
//   4. 传了不属于该 type 的 id → 直接忽略(防呆)
//   5. 幂等(同样顺序连调两次结果一致)
//   6. sortOrder 从 0 开始连续重编号(不留空洞)
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  // 支出 4 条(id 1..4) + 收入 2 条(id 5..6)
  const expenseNames = ['餐饮', '交通', '购物', '住房'];
  const incomeNames = ['工资', '奖金'];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);

    for (var i = 0; i < expenseNames.length; i++) {
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          name: expenseNames[i],
          icon: 'more_horiz',
          color: 0xFF9CA3AF,
          type: 'expense',
          isSystem: const Value(true),
          sortOrder: Value(i),
        ),
      );
    }
    for (var i = 0; i < incomeNames.length; i++) {
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          name: incomeNames[i],
          icon: 'more_horiz',
          color: 0xFF9CA3AF,
          type: 'income',
          isSystem: const Value(true),
          sortOrder: Value(i),
        ),
      );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> expenseNamesInOrder() async {
    final rows = await repo.byType('expense');
    return rows.map((c) => c.name).toList();
  }

  Future<List<int>> incomeSortOrders() async {
    final rows = await repo.byType('income');
    return rows.map((c) => c.sortOrder).toList();
  }

  test('D64.98 拖完:byType 读出来的顺序 == 传入的顺序', () async {
    // 把「住房」(id=4)拖到最前面
    await repo.reorderByType('expense', [4, 1, 2, 3]);

    expect(await expenseNamesInOrder(), ['住房', '餐饮', '交通', '购物']);
  });

  test('D64.98 只动当前 type:收入的 sortOrder 一行不碰', () async {
    await repo.reorderByType('expense', [4, 3, 2, 1]);

    // 收入两条还是 0 / 1,而且顺序没变
    expect(await incomeSortOrders(), [0, 1]);
    final income = await repo.byType('income');
    expect(income.map((c) => c.name).toList(), ['工资', '奖金']);
  });

  test('D64.98 没传进来的分类按原相对次序追加在后面(不丢分类)', () async {
    // 只传了 id=2,3 → 剩下两条按原相对次序(1 在前、4 在后)追加
    await repo.reorderByType('expense', [2, 3]);

    expect(await expenseNamesInOrder(), ['交通', '购物', '餐饮', '住房']);
  });

  test('D64.98 传了不属于该 type 的 id → 直接忽略', () async {
    // id=5 / 6 是收入,不该被写进支出的顺序里
    await repo.reorderByType('expense', [5, 4, 1, 2, 3, 6]);

    expect(await expenseNamesInOrder(), ['住房', '餐饮', '交通', '购物']);
    // 收入没被动过
    expect(await incomeSortOrders(), [0, 1]);
  });

  test('D64.98 幂等:同样顺序连调两次结果一致', () async {
    await repo.reorderByType('expense', [3, 2, 1, 4]);
    final first = await expenseNamesInOrder();
    await repo.reorderByType('expense', [3, 2, 1, 4]);
    final second = await expenseNamesInOrder();

    expect(second, first);
    expect(second, ['购物', '交通', '餐饮', '住房']);
  });

  test('D64.98 sortOrder 从 0 开始连续重编号(不留空洞)', () async {
    await repo.reorderByType('expense', [4, 1, 2, 3]);

    final rows = await repo.byType('expense');
    expect(rows.map((c) => c.sortOrder).toList(), [0, 1, 2, 3]);
    // id 和 name 都没被动过(只动顺序)
    expect(rows.map((c) => c.id).toList(), [4, 1, 2, 3]);
    expect(rows.map((c) => c.name).toList(), ['住房', '餐饮', '交通', '购物']);
  });

  test('D64.98 新建分类落在同类最后(不跟第一类撞 sortOrder)', () async {
    // 先重排:把「交通」拖到最前面
    await repo.reorderByType('expense', [2, 1, 3, 4]);

    await repo.create(
      name: '咖啡',
      icon: 'more_horiz',
      color: 0xFF9CA3AF,
      type: 'expense',
    );

    final rows = await repo.byType('expense');
    // 追加到末尾,用户的排序没被打乱
    expect(rows.map((c) => c.name).toList(), ['交通', '餐饮', '购物', '住房', '咖啡']);
    // sortOrder 连续 —— 没有跟谁撞车(撞车的话顺序就由 SQLite 说了算 = 看着随机)
    expect(rows.map((c) => c.sortOrder).toList(), [0, 1, 2, 3, 4]);
  });

  test('D64.98 新建分类不影响别的 type 的 sortOrder', () async {
    await repo.create(
      name: '兼职',
      icon: 'more_horiz',
      color: 0xFF9CA3AF,
      type: 'income',
    );

    // 收入两条:原来的 0/1 + 新增的追加在后面
    expect(await incomeSortOrders(), [0, 1, 2]);
    // 支出没被动过
    expect(await expenseNamesInOrder(), ['餐饮', '交通', '购物', '住房']);
  });
}
