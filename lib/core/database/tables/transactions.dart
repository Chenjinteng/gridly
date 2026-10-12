// lib/core/database/tables/transactions.dart
// 流水表(记账记录)
import 'package:drift/drift.dart';

import 'assets.dart';
import 'categories.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()(); // 单位:元(保留 2 位)
  // commit 110 加 'balance' type:
  //   - 'expense' | 'income' | 'balance'
  //   - 'balance' = 动资产但不算月度收支(公积金月供/期权/外借等)
  TextColumn get type => text()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  // commit 110 改:accountId NOT NULL + FK 引用 Assets
  //   之前是 nullable 占位字段(P1 之前没有 asset 表,nullable 兜底)
  //   P1 后改成必填,流水必须挂靠到某个账户
  IntColumn get accountId => integer().references(Assets, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
