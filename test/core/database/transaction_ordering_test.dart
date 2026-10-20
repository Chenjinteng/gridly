// test/core/database/transaction_ordering_test.dart
// 2026-10-20 D64.74
//
// 目的:端到端验证"流水列表当天组内按插入时间倒序(最新插入的最前面)"。
//
// 三层都要对:
//   1. SQL 层:repository.all() 的 ORDER BY 带 `id DESC` 第二排序键
//      (原来只有 `occurred_at DESC` 单键,SQLite 对并列行不保证顺序)
//   2. repository 层:groupedByDay() 的组内排序
//   3. 用真实 in-memory SQLite 跑(不是 mock),跟真机行为一致
//
// 用 AppDatabase.forTesting(NativeDatabase.memory()) —— 不碰真机数据文件。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await Migrator(db).createAll();
    // FK 依赖:先造分类和账户
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '餐饮',
        icon: 'restaurant',
        color: 0xFF000000,
        type: 'expense',
      ),
    );
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '现金', type: 'cash_flow'),
    );
    repo = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addTx(DateTime occurredAt, {String note = ''}) {
    return repo.add(
      amount: 10,
      type: 'expense',
      categoryId: 1,
      occurredAt: occurredAt,
      note: note,
      accountId: 1,
    );
  }

  test('同一天同秒连插 5 条:all() 按 id 降序(原来是 rowid 升序)', () async {
    final same = DateTime(2026, 10, 12, 9, 30);
    for (var i = 0; i < 5; i++) {
      await addTx(same, note: 'tx$i');
    }
    final all = await repo.all();
    expect(
      all.map((t) => t.note).toList(),
      ['tx4', 'tx3', 'tx2', 'tx1', 'tx0'],
      reason: 'occurred_at 完全相同时也必须按 id 降序',
    );
  });

  test('groupedByDay:当天组内按 id 降序', () async {
    final day = DateTime(2026, 10, 12, 9, 30);
    for (var i = 0; i < 3; i++) {
      await addTx(day, note: 'tx$i');
    }
    final grouped = await repo.groupedByDay();
    final list = grouped[DateTime(2026, 10, 12)]!;
    expect(list.map((t) => t.note).toList(), ['tx2', 'tx1', 'tx0']);
  });

  test('补记历史日期(后插的 occurred_at 更早)仍排当天最前', () async {
    await addTx(DateTime(2026, 10, 12, 14, 30), note: '先记14:30');
    await addTx(DateTime(2026, 10, 12, 9, 30), note: '后记09:30');
    await addTx(DateTime(2026, 10, 12, 11, 0), note: '再记11:00');
    final grouped = await repo.groupedByDay();
    final list = grouped[DateTime(2026, 10, 12)]!;
    expect(
      list.map((t) => t.note).toList(),
      ['再记11:00', '后记09:30', '先记14:30'],
      reason: '当天组内必须是纯插入序,不受 occurred_at 时分影响',
    );
  });

  test('跨天:天按日期倒序(由调用方排),组内按 id 降序', () async {
    await addTx(DateTime(2026, 10, 12, 10), note: 'd12-a');
    await addTx(DateTime(2026, 10, 12, 20), note: 'd12-b');
    await addTx(DateTime(2026, 10, 13, 10), note: 'd13-a');
    await addTx(DateTime(2026, 10, 13, 20), note: 'd13-b');

    final grouped = await repo.groupedByDay();
    expect(grouped[DateTime(2026, 10, 12)]!.map((t) => t.note).toList(), [
      'd12-b',
      'd12-a',
    ]);
    expect(grouped[DateTime(2026, 10, 13)]!.map((t) => t.note).toList(), [
      'd13-b',
      'd13-a',
    ]);
  });

  test('id 是 AUTOINCREMENT:删除后不复用,新插入的 id 更大', () async {
    final day = DateTime(2026, 10, 12, 9, 30);
    final a = await addTx(day, note: 'A');
    final b = await addTx(day, note: 'B');
    await repo.delete(a);
    final c = await addTx(day, note: 'C');
    expect(c, greaterThan(b), reason: 'AUTOINCREMENT 不复用已删除的 id');
    final grouped = await repo.groupedByDay();
    expect(
      grouped[DateTime(2026, 10, 12)]!.map((t) => t.note).toList(),
      ['C', 'B'],
    );
  });
}
