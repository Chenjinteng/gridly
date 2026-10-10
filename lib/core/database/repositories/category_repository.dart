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

  /// 全部分类(按 sortOrder 升序)
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

  /// 新增分类
  Future<int> create({
    required String name,
    required String icon,
    required int color,
    required String type,
    int sortOrder = 0,
  }) {
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            icon: icon,
            color: color,
            type: type,
            isSystem: const Value(false),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  /// 改分类
  Future<bool> update(Category c) {
    return _db.update(_db.categories).replace(c);
  }

  /// 删分类(系统分类也允许删,但如果有流水引用会因外键失败)
  Future<int> delete(int id) {
    return (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }

  /// 检查分类是否被引用
  Future<int> usageCount(int id) async {
    return (_db.selectOnly(_db.transactions)
          ..addColumns([_db.transactions.id.count()])
          ..where(_db.transactions.categoryId.equals(id)))
        .map((row) => row.read(_db.transactions.id.count())!)
        .getSingle();
  }

  /// 把系统分类的 icon 升级到 v2(语义化图标)。
  /// 按 name 匹配:在迁移表里的就更新到新 key,不在的不动(用户自定义分类不会被改)。
  /// 每次启动都会跑,但只有命中的行会被 UPDATE,代价很低。
  Future<void> syncCategoryIcons() async {
    await _db.batch((batch) {
      for (final entry in kIconMigrationV2.entries) {
        batch.update(
          _db.categories,
          CategoriesCompanion(icon: Value(entry.value)),
          where: (c) => c.name.equals(entry.key) & c.isSystem.equals(true),
        );
      }
    });
  }

  /// 同步系统分类的 color 到代码最新值。
  /// 默认分类的颜色定义在代码里(DefaultCategories.expense / .income),
  /// 旧版本种过的预置分类 color 会被固化在 db 里(全是 teal),
  /// 这里按 name 匹配把所有系统分类 color 同步到当前代码值。
  /// 跟 syncCategoryIcons 一样幂等 + 低代价。
  Future<void> syncCategoryColors() async {
    await _db.batch((batch) {
      for (final c in DefaultCategories.expense) {
        batch.update(
          _db.categories,
          CategoriesCompanion(color: Value(c.color.toARGB32())),
          where: (cat) => cat.name.equals(c.name) & cat.isSystem.equals(true),
        );
      }
      for (final c in DefaultCategories.income) {
        batch.update(
          _db.categories,
          CategoriesCompanion(color: Value(c.color.toARGB32())),
          where: (cat) => cat.name.equals(c.name) & cat.isSystem.equals(true),
        );
      }
    });
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
