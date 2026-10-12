// lib/core/database/repositories/transaction_repository.dart
// 流水 Repository —— 业务层唯一接触 Transaction DAO 的地方
import 'package:drift/drift.dart';

import '../app_database.dart';

class TransactionRepository {
  TransactionRepository(this._db);
  final AppDatabase _db;

  /// 写一笔(新增流水)
  /// 2026-10-12 commit 110 改:accountId 必填字段(FK 引用 Assets),
  ///   P1 阶段 UI 未暴露账户选择器,允许 caller 不传 → 内部 fallback
  ///   到第一个 cash_flow 账户(displayOrder 升序 = "现金")。
  ///   后续 P2/P3 加资产选择器时,callers 显式传 accountId。
  Future<int> add({
    required double amount,
    required String type, // 'expense' | 'income' | 'balance'
    required int categoryId,
    required DateTime occurredAt,
    String? note,
    int? accountId,
  }) async {
    final aid = accountId ?? await _firstCashAssetId();
    return _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            amount: amount,
            type: type,
            categoryId: categoryId,
            occurredAt: occurredAt,
            note: Value(note),
            accountId: aid,
          ),
        );
  }

  /// 取第一个 cash_flow 账户(displayOrder 升序)作为 accountId fallback
  /// App 启动 seed 后,assets 表必有 3 个现金账户,这里永不返回 null。
  /// 万一返回 null(理论上不会),抛 StateError 让 caller 看到原因。
  Future<int> _firstCashAssetId() async {
    final a =
        await (_db.select(_db.assets)
              ..where((a) => a.type.equals('cash_flow'))
              ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)])
              ..limit(1))
            .getSingleOrNull();
    if (a == null) {
      throw StateError(
        'assets 表没有 cash_flow 账户。App 启动时应该已 seedDefaultsIfEmpty(),'
        '若仍报这个错说明 seed 流程出问题,需排查 main.dart。',
      );
    }
    return a.id;
  }

  /// 全部流水(按时间倒序)
  Future<List<Transaction>> all() {
    return (_db.select(
      _db.transactions,
    )..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).get();
  }

  /// 按 id 取单笔(2026-10-11 新增:EditTransactionPage 全屏编辑用)
  /// 不存在返回 null(理论上不应该,UI 层有"找不到就退回"处理)
  Future<Transaction?> byId(int id) async {
    return (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 按日分组(返回 `Map<日期, List<Transaction>>`)
  Future<Map<DateTime, List<Transaction>>> groupedByDay() async {
    final all = await this.all();
    final map = <DateTime, List<Transaction>>{};
    for (final t in all) {
      final day = DateTime(
        t.occurredAt.year,
        t.occurredAt.month,
        t.occurredAt.day,
      );
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
