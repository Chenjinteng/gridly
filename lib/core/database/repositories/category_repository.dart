// lib/core/database/repositories/category_repository.dart
// 分类 Repository —— 业务层唯一接触 Category DAO 的地方
// App 首次启动时,seed 默认分类
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../../shared/constants/default_categories.dart';

class CategoryRepository {
  CategoryRepository(this._db);
  final AppDatabase _db;

  /// App 启动:seed 默认分类(只在空表时执行)
  Future<void> seedDefaultsIfEmpty() async {
    final count = await (_db.selectOnly(_db.categories)
          ..addColumns([_db.categories.id.count()]))
        .map((row) => row.read(_db.categories.id.count())!)
        .getSingle();
    if (count > 0) return;

    await _db.batch((batch) {
      for (final c in DefaultCategories.expense) {
        batch.insert(_db.categories, _toCompanion(c));
      }
      for (final c in DefaultCategories.income) {
        batch.insert(_db.categories, _toCompanion(c));
      }
    });
  }

  /// 全部分类(按 sortOrder 排序)
  Future<List<Category>> all() {
    return (_db.select(_db.categories)
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  /// 按 type 取
  Future<List<Category>> byType(String type) {
    return (_db.select(_db.categories)
          ..where((c) => c.type.equals(type))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  CategoriesCompanion _toCompanion(DefaultCategory c) {
    return CategoriesCompanion.insert(
      name: c.name,
      icon: c.icon,
      color: c.color.toARGB32(),
      type: c.type,
      isSystem: const Value(true),
      sortOrder: Value(c.sortOrder),
    );
  }
}
