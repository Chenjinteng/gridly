// lib/core/database/tables/assets.dart
// 资产/账户表(2026-10-12 P1 加,commit 110)
//   - type 字段 4 段 enum(cash_flow / fixed_asset / liability / other)
//   - name 字段 free text(具体账户名)
//   - initialBalance 持久化,currentBalance 读时实时算
//   - displayOrder 排序字段
import 'package:drift/drift.dart';

class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 24)();
  // 4 段 enum: 'cash_flow' | 'fixed_asset' | 'liability' | 'other'
  TextColumn get type => text()();
  TextColumn get icon =>
      text().withDefault(const Constant('account_balance_wallet'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF14B8A6))();
  RealColumn get initialBalance => real().withDefault(const Constant(0.0))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
