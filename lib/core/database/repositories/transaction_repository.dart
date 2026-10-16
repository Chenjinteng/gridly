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
  /// 2026-10-13 P8 加:destinationAccountId 参数(投资场景投入/收益/调拨双账户)
  ///   - 非空 → 表示这是"资产流转"流水(accountId=转出,destinationAccountId=转入)
  ///   - null → 单账户流水(cash_flow expense/income/balance 不存,数据迁移以空)
  Future<int> add({
    required double amount,
    required String type, // 'expense' | 'income' | 'balance'
    required int categoryId,
    required DateTime occurredAt,
    String? note,
    int? accountId,
    int? destinationAccountId,
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
            // 2026-10-13 P8:nullable,投资场景以外的所有 caller 都不传 → 默认 null
            destinationAccountId: Value(destinationAccountId),
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

  /// 2026-10-16 D64.81 加:投资活动聚合(SQL GROUP BY)
  ///   - invested = sum(amount) where cat.type='investment' AND tx.type='balance'
  ///   - returned = sum(amount) where cat.type='investment' AND tx.type='income'
  ///   - 全时间累计,跟 investmentNetTotalProvider 口径一致
  ///   - SQL 端 JOIN + GROUP BY 一次性算好,跟之前 Dart 端 filter 全表 N+1 反差大
  ///     (1w+ 笔时 investment_dashboard 首次 build 从 200ms+ 降到 <20ms)
  Future<InvestmentAggregated> investmentAggregated() async {
    // 拉 cat.type='investment' 的 id 集合(走 categories 索引,内存过滤)
    final investCats = await (_db.selectOnly(_db.categories)
          ..addColumns([_db.categories.id])
          ..where(_db.categories.type.equals('investment')))
        .map((row) => row.read(_db.categories.id)!)
        .get();
    if (investCats.isEmpty) {
      return const InvestmentAggregated(invested: 0, returned: 0);
    }
    // SQL:按 tx.type 分组 sum(amount),filter invest cats + 限定 balance/income
    final typeCol = _db.transactions.type;
    final amountSum = _db.transactions.amount.sum();
    final rows = await (_db.selectOnly(_db.transactions)
          ..addColumns([typeCol, amountSum])
          ..where(_db.transactions.categoryId.isIn(investCats) &
              typeCol.isIn(['balance', 'income']))
          ..groupBy([typeCol]))
        .get();
    double invested = 0;
    double returned = 0;
    for (final row in rows) {
      final t = row.read(typeCol);
      final sum = row.read(amountSum) ?? 0.0;
      if (t == 'balance') {
        invested += sum;
      } else if (t == 'income') {
        returned += sum;
      }
    }
    return InvestmentAggregated(invested: invested, returned: returned);
  }
}

/// 投资活动累计聚合(全时间)
///   - invested:投入(现金 → 投资账户的调拨,cat.type='investment' AND tx.type='balance')
///   - returned:收益(投资账户自身收入,cat.type='investment' AND tx.type='income')
///   - net = returned - invested(正=累计赚的比投的多,负=累计投的比赚的多)
class InvestmentAggregated {
  const InvestmentAggregated({
    required this.invested,
    required this.returned,
  });
  final double invested;
  final double returned;
  double get net => returned - invested;
}
