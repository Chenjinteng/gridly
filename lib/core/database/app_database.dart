// lib/core/database/app_database.dart
// Drift Database 单例 —— 整个 App 一个 AppDatabase 实例
// Schema 在 tables/ 下,Repository 在 repositories/ 下
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'seeds/default_assets.dart';
import 'tables/assets.dart';
import 'tables/categories.dart';
import 'tables/category_budgets.dart';
import 'tables/transactions.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Transactions, CategoryBudgets, Assets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // 2026-10-12 commit 90:1 → 2,新增 CategoryBudgets 表
  // 2026-10-12 commit 110:2 → 3,新增 Assets 表 + transactions.accountId NOT NULL + FK
  //   - 旧设备升级时走 onUpgrade 创建新表 + 预置 3 个默认账户
  //   - 新设备安装走 onCreate 的 createAll() + seedDefaultsIfEmpty
  //   - 这里"没数据"约束下,不需要老数据回填(commit 110 P1 默认场景)
  // 2026-10-13 P7:4 → 5,assets 加 isDefault 列(cash_flow 段"日常流水默认账户"标记)
  // 2026-10-13 P8:5 → 6,transactions 加 destinationAccountId 列(投资场景投入/收益/调拨双账户)
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // 1 → 2:加 CategoryBudgets 表
      if (from < 2) {
        await m.createTable(categoryBudgets);
      }
      // 2 → 3:加 Assets 表 + 预置 3 个默认账户
      //   老设备升级没有 accountId 字段,但因为没数据(P1 约束),
      //   不会有外键违规。transactions.accountId 改 NOT NULL 在新 schema 生效。
      if (from < 3) {
        await m.createTable(assets);
        await batch((b) {
          for (final a in DefaultAssets.all) {
            b.insert(
              assets,
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
      // 3 → 4:assets 加 includeInTransactions 列(默认 true)
      //   2026-10-13 P6 user 决定资产分类 4 → 6 段,并在 form 里加'是否计入流水'开关
      //   老账户默认 includeInTransactions = true(全部计入日常流水,行为不变)
      if (from < 4) {
        await m.addColumn(assets, assets.includeInTransactions);
      }
      // 4 → 5:assets 加 isDefault 列(默认 false)
      //   2026-10-13 P7 user 要求 cash_flow 段支持"设为默认"开关,
      //   记一笔优先选 isDefault=true 账户。老设备升级时 cash_flow 段账户全为 false,
      //   user 在资产列表主动开/用 form 创建时手动开。已有 seed "现金" 自动 isDefault=true。
      if (from < 5) {
        await m.addColumn(assets, assets.isDefault);
        // 老设备升级时,seed 已经种了 3 个 cash_flow 默认账户,但 isDefault 全 false。
        // 这里把 displayOrder 0 的"现金"补 isDefault = true(2026-10-13 P7 决策,
        // 保证老设备升级后立刻有默认账户可用,不强制 user 重新设置)。
        await batch((b) {
          b.update(
            assets,
            const AssetsCompanion(isDefault: Value(true)),
            where: (a) => a.type.equals('cash_flow') & a.displayOrder.equals(0),
          );
        });
      }
      // 5 → 6:transactions 加 destinationAccountId(nullable,FK 引用 Assets)
      //   2026-10-13 P8 投资场景精简化:投入/收益/调拨 3 段都需要"转出 + 转入"双账户
      //   老数据全为 null(向后兼容,不影响 cash_flow 已有 expense/income/balance)
      if (from < 6) {
        await m.addColumn(transactions, transactions.destinationAccountId);
      }
      // 6 → 7:assets 加 actAsCashFlow 列(默认 false)
      //   2026-10-15 D61 user 反馈:"债务这里的属性还需要增加一个按钮,就是'充当现金流'",
      //   区分"花呗/白条等可消费债务"(可作 cash_flow 支出 source)vs"车贷/房贷等不可消费债务"
      //   (只能在 receivable 段调拨还款,不能进 cash_flow 支出 picker)。
      //   老数据默认 false:已经存在的 receivable 账户(包括花呗/车贷等)首次升级后都是 false,
      //   user 需要在资产管理手动给花呗/白条/信用卡开"充当现金流"。
      //   这样保证"不可消费债务"不会因为升级而意外出现在记一笔 picker 里。
      if (from < 7) {
        await m.addColumn(assets, assets.actAsCashFlow);
      }
    },
    beforeOpen: (details) async {
      // 启用外键
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 清空所有用户数据:流水 + 自定义分类 + 分类预算 + 资产
  /// 保留系统预置分类(餐饮/交通/...)和数据库 schema
  /// 2026-10-14 修(D46):之前漏删 assets,user UAT 发现"清空所有数据"按钮
  ///   实际没清空资产 —— 注释里写"预置账户永远保留"但 user 期望的"清空"
  ///   语义是真清空,保留 system 分类是因为分类是 user 主动选的核心维度,
  ///   资产清空后 caller(UI 层)可以再调 seedDefaultsIfEmpty() 重 seed 默认
  ///   3 个现金账户,或者 user 自己建。
  Future<void> clearAllData() async {
    await delete(transactions).go();
    await delete(categoryBudgets).go();
    await (delete(categories)..where((c) => c.isSystem.equals(false))).go();
    await delete(assets).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'gridly.sqlite'));

    // Workaround:旧 Android 设备的 sqlite3 动态库不包含最新特性
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    // 性能调优
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}
