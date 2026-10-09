// lib/core/database/tables/transactions.dart
// 流水表(记账记录)
import 'package:drift/drift.dart';
import 'categories.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();         // 单位:元(保留 2 位)
  TextColumn get type => text()();           // 'expense' | 'income'
  IntColumn get categoryId => integer().references(Categories, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  IntColumn get accountId => integer().nullable()();  // Phase 2: 多账户
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
