// lib/core/database/repositories/transaction_repository.dart
// 流水 Repository —— 业务层唯一接触 Transaction DAO 的地方
import 'package:drift/drift.dart';
import '../app_database.dart';

class TransactionRepository {
  TransactionRepository(this._db);
  final AppDatabase _db;

  /// 写一笔(新增流水)
  Future<int> add({
    required double amount,
    required String type,             // 'expense' | 'income'
    required int categoryId,
    required DateTime occurredAt,
    String? note,
  }) {
    return _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            amount: amount,
            type: type,
            categoryId: categoryId,
            occurredAt: occurredAt,
            note: Value(note),
          ),
        );
  }

  /// 全部流水(按时间倒序)
  Future<List<Transaction>> all() {
    return (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();
  }

  /// 按日分组(返回 `Map<日期, List<Transaction>>`)
  Future<Map<DateTime, List<Transaction>>> groupedByDay() async {
    final all = await this.all();
    final map = <DateTime, List<Transaction>>{};
    for (final t in all) {
      final day = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map;
  }

  /// 删一笔
  Future<int> delete(int id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  /// 改一笔
  Future<bool> update(Transaction t) {
    return _db.update(_db.transactions).replace(t);
  }
}
