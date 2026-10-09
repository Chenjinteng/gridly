// lib/core/database/tables/categories.dart
// 分类表(系统预置 + 用户自定义)
import 'package:drift/drift.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 16)();
  TextColumn get icon => text()();                // icon key,对应预设几何图标
  IntColumn get color => integer()();              // ARGB 32-bit
  TextColumn get type => text()();                 // 'expense' | 'income'
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
