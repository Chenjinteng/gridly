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
  @override
  int get schemaVersion => 3;

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
    },
    beforeOpen: (details) async {
      // 启用外键
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 清空所有用户数据:流水 + 自定义分类 + 分类预算
  /// 保留系统预置分类(餐饮/交通/...)和数据库 schema 和默认资产
  Future<void> clearAllData() async {
    await delete(transactions).go();
    await delete(categoryBudgets).go();
    await (delete(categories)..where((c) => c.isSystem.equals(false))).go();
    // assets 表不删(预置账户永远保留,user 删完自己加的也无所谓)
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
