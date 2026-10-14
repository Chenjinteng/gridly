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
  ///
  /// 2026-10-13 P7:seed 时也写入 isDefault("现金"为 true)
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
            // 2026-10-13 P7:"现金" isDefault=true,记一笔默认命中
            isDefault: Value(a.isDefault),
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
  /// 2026-10-13 P7:加 isDefault 参数(cash_flow 段"日常流水默认账户"标记)
  ///   - 单例:cash_flow 段同时只能有 1 只 isDefault=true
  ///   - 由调用方负责调用 setDefaultForCashFlow() 在插入后同步
  ///     (insert + setDefault 在一个事务里更好,但当前 UI 流程允许短暂不一致,可接受)
  Future<int> create({
    required String name,
    required String type,
    String icon = 'account_balance_wallet',
    int color = 0xFF14B8A6,
    double initialBalance = 0.0,
    bool includeInTransactions = true,
    int displayOrder = 0,
    bool isDefault = false,
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
            // 2026-10-13 P7:记一笔默认账户标记(cash_flow 段单例)
            isDefault: Value(isDefault),
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

  /// 2026-10-13 P7:把 cash_flow 段 id 标记为默认账户,清掉同段其他 isDefault
  ///   - 单例:cash_flow 段同时只能有 1 只 isDefault=true
  ///   - 关闭老默认(同段其他账户 isDefault=false)+ 开启新默认(id isDefault=true)
  ///   - 包 batch 一次事务,避免 race(用户快速切换默认值时老默认残留)
  ///   - 非 cash_flow 段调用本方法无害(where 含 type=blank,找不到就 update 0 行)
  Future<void> setDefaultForCashFlow(int id) async {
    await _db.batch((b) {
      b.update(
        _db.assets,
        const AssetsCompanion(isDefault: Value(false)),
        where: (a) => a.type.equals('cash_flow') & a.isDefault.equals(true),
      );
      b.update(
        _db.assets,
        const AssetsCompanion(isDefault: Value(true)),
        where: (a) => a.id.equals(id),
      );
    });
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
  /// 公式(commit 110 P1 决策,2026-10-14 修正 balance 流水处理):
  ///   - expense amount 永远正 → accountId 减少 sum
  ///   - income amount 永远正 → accountId 增加 sum
  ///   - balance amount 永远正 → accountId(source)减少 sum,destinationAccountId(dest)增加 sum
  ///     (P18 修:之前 source 累加 sum 是错的,转出应该减;dest 完全漏处理,转入应该加)
  /// 2026-10-14 D51 加:负债段 lend_out / borrow_in
  ///   - lend_out amount 永远正 → accountId 增加 sum(我是债权人,正数)
  ///   - borrow_in amount 永远正 → accountId 减少 sum(我是负债方,负数)
  ///   - balance 公式:Σ lend_out − Σ borrow_in(正数=净债权人,负数=净负债方)
  ///
  /// 完整 currentBalance = initialBalance + delta(由 asset_balance_provider 组合)
  ///
  /// 返回 `Map<int, double>`(assetId → delta)—— 没流水的账户不出现在 map 里
  Future<Map<int, double>> balanceDeltaByAssetId() async {
    // expense / income 按 accountId group by
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

    // balance 流水两次查询:source 按 accountId, dest 按 destinationAccountId
    //  - 调拨 amount 永远正,source 减 sum,dest 加 sum
    final balanceSourceSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('balance'))
              ..groupBy([_db.transactions.accountId]))
            .get();

    final balanceDestSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.destinationAccountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('balance'))
              ..groupBy([_db.transactions.destinationAccountId]))
            .get();

    // 2026-10-14 D51:负债段 lend_out / borrow_in 累加
    //   lend_out = 借出,我是债权人,balance += sum
    //   borrow_in = 借入,我是负债方,balance -= sum
    final lendOutSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('lend_out'))
              ..groupBy([_db.transactions.accountId]))
            .get();

    final borrowInSum =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([
                _db.transactions.accountId,
                _db.transactions.amount.sum(),
              ])
              ..where(_db.transactions.type.equals('borrow_in'))
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

    for (final row in balanceSourceSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        // balance source:转出 → 减少余额(P18 修:之前 + sum 错)
        result[id] = (result[id] ?? 0.0) - sum;
      }
    }

    for (final row in balanceDestSum) {
      final id = row.read(_db.transactions.destinationAccountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        // balance dest:转入 → 增加余额(P18 新增:之前完全漏处理)
        result[id] = (result[id] ?? 0.0) + sum;
      }
    }

    // 2026-10-14 D51:负债段 lend_out / borrow_in
    for (final row in lendOutSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        // 借出:我是债权人,balance 增加
        result[id] = (result[id] ?? 0.0) + sum;
      }
    }

    for (final row in borrowInSum) {
      final id = row.read(_db.transactions.accountId);
      final sum = row.read(_db.transactions.amount.sum()) ?? 0.0;
      if (id != null) {
        // 借入:我是负债方,balance 减少
        result[id] = (result[id] ?? 0.0) - sum;
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
