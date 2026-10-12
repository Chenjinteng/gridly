// lib/core/database/repositories/asset_repository.dart
// 资产/账户 Repository —— 业务层唯一接触 Asset DAO 的地方
// App 首次启动时,seed 默认 3 个资产(现金/银行卡/微信支付)
//
// 2026-10-12 commit 110 加(P1):
//   - 4 段 type enum(cash_flow / fixed_asset / liability / other)
//   - toJson for LAN_WEB P2 API
//   - balanceDeltaByAssetId:实时算 currentBalance 增量(累加 expense/income/balance 流水)
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../seeds/default_assets.dart';

class AssetRepository {
  AssetRepository(this._db);
  final AppDatabase _db;

  /// App 启动:seed 默认资产(只在空表时执行)
  /// 跟 CategoryRepository.seedDefaultsIfEmpty 同模式,幂等
  Future<void> seedDefaultsIfEmpty() async {
    final count =
        await (_db.selectOnly(_db.assets)..addColumns([_db.assets.id.count()]))
            .map((row) => row.read(_db.assets.id.count())!)
            .getSingle();
    if (count > 0) return;

    await _db.batch((batch) {
      for (final a in DefaultAssets.all) {
        batch.insert(
          _db.assets,
          AssetsCompanion.insert(
            name: a.name,
            type: a.type,
            icon: Value(a.icon),
            color: Value(a.color),
            displayOrder: Value(a.displayOrder),
          ),
        );
      }
    });
  }

  /// 全部资产(按 displayOrder 升序)
  Future<List<Asset>> all() {
    return (_db.select(
      _db.assets,
    )..orderBy([(a) => OrderingTerm.asc(a.displayOrder)])).get();
  }

  /// 按 type 取(雷达图 4 维汇总用)
  Future<List<Asset>> byType(String type) {
    return (_db.select(_db.assets)
          ..where((a) => a.type.equals(type))
          ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
        .get();
  }

  /// 按 id 取单条
  Future<Asset?> byId(int id) {
    return (_db.select(
      _db.assets,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  /// 新增
  /// 2026-10-13 P6:加 includeInTransactions 参数(true = 计入日常流水 / false = 投资/福利/债权等)
  Future<int> create({
    required String name,
    required String type,
    String icon = 'account_balance_wallet',
    int color = 0xFF14B8A6,
    double initialBalance = 0.0,
    bool includeInTransactions = true,
    int displayOrder = 0,
  }) {
    return _db
        .into(_db.assets)
        .insert(
          AssetsCompanion.insert(
            name: name,
            type: type,
            icon: Value(icon),
            color: Value(color),
            initialBalance: Value(initialBalance),
            // 显式 Value() 包,即使默认值也是 true,迁移过来的老数据这条会是默认值
            includeInTransactions: Value(includeInTransactions),
            displayOrder: Value(displayOrder),
          ),
        );
  }

  /// 改
  Future<bool> update(Asset a) {
    return _db.update(_db.assets).replace(a);
  }

  /// 删(若被 transactions FK 引用会失败,UI 提示先改引用)
  Future<int> delete(int id) {
    return (_db.delete(_db.assets)..where((a) => a.id.equals(id))).go();
  }

  /// 资产是否被流水引用
  Future<int> usageCount(int id) async {
    return (_db.selectOnly(_db.transactions)
          ..addColumns([_db.transactions.id.count()])
          ..where(_db.transactions.accountId.equals(id)))
        .map((row) => row.read(_db.transactions.id.count())!)
        .getSingle();
  }

  /// 实时算每个账户的"净流水增量"
  /// 公式(commit 110 P1 决策):
  ///   delta = -sum(expense amount) + sum(income amount) + sum(balance amount)
  ///   - expense amount 永远正 → 减少余额
  ///   - income amount 永远正 → 增加余额
  ///   - balance amount 可正可负 → 正入负出
  ///
  /// 完整 currentBalance = initialBalance + delta(由 asset_balance_provider 组合)
  ///
  /// 返回 `Map<int, double>`(assetId → delta)—— 没流水的账户不出现在 map 里
  Future<Map<int, double>> balanceDeltaByAssetId() async {
    // 三次查询(每种 type 一次)然后合并,比一次 group by 简单清晰
    final expenseSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('expense'))
              ..groupBy([_db.transactions.accountId]))
            .get();

    final incomeSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('income'))
              ..groupBy([_db.transactions.accountId]))
            .get();

    final balanceSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('balance'))
              ..groupBy([_db.transactions.accountId]))
            .get();

    final result = <int, double>{};

    for (final row in expenseSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        // expense 减少余额
        result[id] = (result[id] ?? 0.0) - sum;
      }
    }

    for (final row in incomeSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        result[id] = (result[id] ?? 0.0) + sum;
      }
    }

    for (final row in balanceSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        result[id] = (result[id] ?? 0.0) + sum;
      }
    }

    return result;
  }

  /// 转 JSON(LAN_WEB P2 API 用,commit 110 P1 阶段不加但先把方法备好)
  Map<String, dynamic> toJson(Asset a) {
    return {
      'id': a.id,
      'name': a.name,
      'type': a.type,
      'icon': a.icon,
      'color': a.color,
      'initialBalance': a.initialBalance,
      'displayOrder': a.displayOrder,
      'createdAt': a.createdAt.toIso8601String(),
      'updatedAt': a.updatedAt.toIso8601String(),
    };
  }
}
