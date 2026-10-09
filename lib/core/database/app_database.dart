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

import 'tables/categories.dart';
import 'tables/transactions.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Transactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          // 启用外键
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// 清空所有用户数据:流水 + 自定义分类
  /// 保留系统预置分类(餐饮/交通/...)和数据库 schema
  Future<void> clearAllData() async {
    await delete(transactions).go();
    await (delete(categories)..where((c) => c.isSystem.equals(false))).go();
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
