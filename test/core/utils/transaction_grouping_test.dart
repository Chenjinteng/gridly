// test/core/utils/transaction_grouping_test.dart
// 2026-10-20 D64.74
//
// 目的:守住"流水列表当天组内按插入时间倒序(最新插入的最前面)"这条规则。
//
// 背景:原实现 SQL 只有 `ORDER BY occurred_at DESC` 单键,SQLite 对排序键相同的行
//   **不保证顺序** → 同一天多条实际按 rowid 升序返回(先插入的在前),看着像"随机"。
//   修法:组内改按 `id` 降序(id 是 AUTOINCREMENT → id 序 ≡ 插入序)。
//
// 测的是纯函数 groupTransactionsByDay(排序规则只此 1 处定义)。
import 'package:flutter_test/flutter_test.dart';
import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/utils/transaction_grouping.dart';

Transaction _tx({
  required int id,
  required DateTime occurredAt,
  String note = '',
}) {
  return Transaction(
    id: id,
    amount: 10,
    type: 'expense',
    categoryId: 1,
    occurredAt: occurredAt,
    note: note,
    accountId: 1,
    destinationAccountId: null,
    createdAt: DateTime(2026, 10, 20, 14, 10, 38),
    updatedAt: DateTime(2026, 10, 20, 14, 10, 38),
  );
}

void main() {
  final day1 = DateTime(2026, 10, 12);
  final day2 = DateTime(2026, 10, 13);

  group('D64.74 groupTransactionsByDay 组内排序', () {
    test('同一天多条:按 id 降序(最新插入的最前面)', () {
      final txs = [
        _tx(id: 1, occurredAt: day1),
        _tx(id: 2, occurredAt: day1),
        _tx(id: 3, occurredAt: day1),
        _tx(id: 4, occurredAt: day1),
        _tx(id: 5, occurredAt: day1),
      ];
      final map = groupTransactionsByDay(txs);
      expect(map.length, 1);
      expect(
        map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(),
        [5, 4, 3, 2, 1],
        reason: '当天组内应按 id 降序(插入顺序,新的在前)',
      );
    });

    test('occurred_at 完全相同(同秒连记)也按 id 降序', () {
      // 这是原来"看着像随机"的确切场景:ORDER BY 单键 → SQLite 并列行不保证顺序
      final same = DateTime(2026, 10, 12, 9, 30);
      final txs = [
        _tx(id: 10, occurredAt: same),
        _tx(id: 11, occurredAt: same),
        _tx(id: 12, occurredAt: same),
      ];
      final map = groupTransactionsByDay(txs);
      expect(
        map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(),
        [12, 11, 10],
      );
    });

    test('补记历史日期(后插的 occurred_at 更早)仍按 id 降序', () {
      // 改日期时 occurred_at 保留的是"表单打开那一刻"的时分秒
      // (transaction_form.dart _pickDate)→ 后插的这条 occurred_at 更早,
      // 但它是最新插入的,必须排最前
      final txs = [
        _tx(id: 20, occurredAt: DateTime(2026, 10, 12, 14, 30)),
        _tx(id: 21, occurredAt: DateTime(2026, 10, 12, 9, 30)),
        _tx(id: 22, occurredAt: DateTime(2026, 10, 12, 11, 0)),
      ];
      final map = groupTransactionsByDay(txs);
      expect(
        map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(),
        [22, 21, 20],
        reason: '当天组内必须是纯插入序,不能受 occurred_at 时分影响',
      );
    });

    test('输入顺序乱,输出仍按 id 降序(幂等)', () {
      final txs = [
        _tx(id: 7, occurredAt: day1),
        _tx(id: 3, occurredAt: day1),
        _tx(id: 9, occurredAt: day1),
        _tx(id: 1, occurredAt: day1),
      ];
      final map = groupTransactionsByDay(txs);
      expect(
        map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(),
        [9, 7, 3, 1],
      );
    });

    test('跨天正确分组,各组独立排序', () {
      final txs = [
        _tx(id: 1, occurredAt: day1),
        _tx(id: 2, occurredAt: day2),
        _tx(id: 3, occurredAt: day1),
        _tx(id: 4, occurredAt: day2),
      ];
      final map = groupTransactionsByDay(txs);
      expect(map.length, 2);
      expect(map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(), [3, 1]);
      expect(map[DateTime(2026, 10, 13)]!.map((t) => t.id).toList(), [4, 2]);
    });

    test('occurred_at 带时分秒也归到同一天(只按年月日分)', () {
      final txs = [
        _tx(id: 1, occurredAt: DateTime(2026, 10, 12, 1, 0)),
        _tx(id: 2, occurredAt: DateTime(2026, 10, 12, 23, 59)),
      ];
      final map = groupTransactionsByDay(txs);
      expect(map.length, 1);
      expect(map[DateTime(2026, 10, 12)]!.map((t) => t.id).toList(), [2, 1]);
    });

    test('空列表返回空 map', () {
      expect(groupTransactionsByDay([]), isEmpty);
    });
  });
}
