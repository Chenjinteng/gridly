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
    final count =
        await (_db.selectOnly(_db.categories)
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
      // 2026-10-14 P18 加:投资 2 类(投入/收益),UI 隐藏但 DB NOT NULL 字段需要填
      for (final c in DefaultCategories.investment) {
        batch.insert(_db.categories, _toCompanion(c));
      }
      // 2026-10-14 加:福利 1 类,UI 隐藏但 DB NOT NULL 字段需要填
      for (final c in DefaultCategories.benefit) {
        batch.insert(_db.categories, _toCompanion(c));
      }
      // 2026-10-14 加:债权段 1 类(负债),UI 隐藏 + 自动 fallback(同福利 pattern)
      for (final c in DefaultCategories.receivable) {
        batch.insert(_db.categories, _toCompanion(c));
      }
      // 2026-10-14 D57 加:其它段 1 类(其它),UI 隐藏 + 自动 fallback(同福利/债权 pattern)
      for (final c in DefaultCategories.other) {
        batch.insert(_db.categories, _toCompanion(c));
      }
    });
  }

  /// 2026-10-14 P18 加:升级路径 —— 老 user DB 已有 cash_flow 分类但没有投资分类,
  /// 这里幂等插入,已存在就跳过。
  /// 跟 seedDefaultsIfEmpty 不同:即便 expense/income 已 seed,investment 仍可能缺。
  Future<void> ensureInvestmentCategories() async {
    await _ensureSystemCategories(DefaultCategories.investment);
  }

  /// 2026-10-14 加:跟 ensureInvestmentCategories 同结构 ——
  /// 老 user DB 没 seed 福利分类时幂等插入,已存在就跳过。
  Future<void> ensureBenefitCategories() async {
    await _ensureSystemCategories(DefaultCategories.benefit);
  }

  /// 2026-10-14 加:债权段 1 cat 升级路径(负债),
  /// 跟 ensureInvestmentCategories / ensureBenefitCategories 同 pattern,
  /// 幂等插入(老 device DB 没种子时补上)
  Future<void> ensureReceivableCategories() async {
    await _ensureSystemCategories(DefaultCategories.receivable);
  }

  /// 2026-10-19 D72 加:余额调整 1 cat 升级路径,
  /// 跟 ensureInvestmentCategories / ensureBenefitCategories 同 pattern,
  /// 幂等插入(老 device DB 没种子时补上)。asset_form_page 编辑期初余额时调用,
  /// 自动生成一笔 type='balance' 流水抹平差值,source = 该资产。
  Future<void> ensureBalanceAdjustCategory() async {
    await _ensureSystemCategories(DefaultCategories.balanceAdjust);
  }

  /// 2026-10-14 D57 加:其它段 1 cat 升级路径(其它),
  /// 跟 ensureInvestmentCategories / ensureBenefitCategories / ensureReceivableCategories 同 pattern,
  /// 幂等插入(老 device DB 没种子时补上)
  Future<void> ensureOtherCategories() async {
    await _ensureSystemCategories(DefaultCategories.other);
  }

  /// 2026-10-22 D64.94:隐藏系统分类的幂等插入(5 个 ensure*Categories 共用)
  ///
  /// **判重口径从「按 name」改成「按 (name, type)」**
  ///
  /// 这批插的都是**隐藏系统分类**,语义由 `type` 决定
  /// (investment / benefit / liability / other / adjust),名字只是个显示标签。
  /// 原来只按 name 判重 → 名字被占住,系统那条就永远补不上。
  ///
  /// 实测(gridly 迁移库):用户旧账本里的「其它」被迁移脚本带成一条
  /// **is_system=0 的用户分类**(name=其它 / type=expense / 105 笔流水),
  /// 而系统隐藏那条是 (name=其它 / type=other) —— **两者同名**。
  /// → 名字被占 → ensureOtherCategories 永远认为"已存在" → 系统那条补不回来
  /// → 一旦那条被删,「其它段」账户记流水时 fallback 找不到分类。
  ///
  /// 同名但 type 不同是**两条不同的东西**,各管各的,不该互相顶掉。
  Future<void> _ensureSystemCategories(List<DefaultCategory> seeds) async {
    final existing = await all();
    // 判重:同名 **且** 同 type 才算已存在
    //   (不用拼接 key —— 分类名里可能有空格,拼接会有歧义)
    bool exists(DefaultCategory c) =>
        existing.any((e) => e.name == c.name && e.type == c.type);
    await _db.batch((batch) {
      for (final c in seeds) {
        if (!exists(c)) {
          batch.insert(_db.categories, _toCompanion(c));
        }
      }
    });
  }

  /// 2026-10-22 D64.95:系统分类改名(老设备升级路径)
  ///
  /// **为什么需要这个方法**:
  /// 改 `DefaultCategories` 里的名字只对**新装设备**生效(`seedDefaultsIfEmpty`
  /// 只在 categories 表为空时跑)。老设备库里还是旧名:
  ///   - 「其他」(type='expense',系统可见的支出兜底)
  ///   - 「其它」(type='other',系统隐藏的其它段标签)
  ///
  /// **为什么不能只改 seed**:
  /// D64.94 把系统隐藏分类的幂等判重改成了按 `(name, type)`。
  /// 老设备上「其它」是 type='other',代码里改成「其它资产」之后,
  /// `ensureOtherCategories()` 会认为"新名不存在" → **补插一条新行**
  /// → 老行还在 → 变成 2 条 type='other',比改名前更乱。
  /// 所以本方法**必须在 ensure 之前跑**(main.dart 里保证顺序)。
  ///
  /// **冲突处理**:新名如果已经被**同 type** 的行占用
  /// (典型:用户自己建了个叫「其它支出」的支出分类),就**跳过**这次改名
  /// —— 宁可系统那条留旧名,也不要产生两条同名可见分类。
  /// 同名但**不同** type 不算冲突(D64.94 的口径:同名不同 type 是两条不同的东西,
  /// 用户自建的「其它」expense 跟系统隐藏的「其它」other 本来就各管各的)。
  ///
  /// **只动 is_system=1 的行** —— 用户自建的分类一行都不碰。
  ///
  /// **幂等**:改完再跑一次,旧名行已经不存在 → 直接跳过。
  Future<void> renameSystemCategories() async {
    for (final r in kSystemCategoryRenames) {
      // 旧名的系统行还在吗?不在 → 已经改过(或本来就没有),跳过
      final oldRows = await (_db.select(_db.categories)
            ..where((c) =>
                c.name.equals(r.oldName) &
                c.type.equals(r.type) &
                c.isSystem.equals(true)))
          .get();
      if (oldRows.isEmpty) continue;

      // 新名被同 type 的行占用 → 跳过(避免出现两条同名同 type 的分类)
      final occupied = await (_db.select(_db.categories)
            ..where((c) => c.name.equals(r.newName) & c.type.equals(r.type)))
          .get();
      if (occupied.isNotEmpty) continue;

      await _db.batch((batch) {
        batch.update(
          _db.categories,
          CategoriesCompanion(
            name: Value(r.newName),
            updatedAt: Value(DateTime.now()),
          ),
          where: (c) =>
              c.name.equals(r.oldName) &
              c.type.equals(r.type) &
              c.isSystem.equals(true),
        );
      });
    }
  }

  /// 2026-10-22 D64.98:按新顺序重排指定 type 的分类(长按拖动排序落库)
  ///
  /// **口径**:
  ///   - 只动 `type` 匹配的分类,别的 type 的 sortOrder 一行不碰
  ///     (支出和收入的排序互不干扰,各自从 0 开始 —— 跟 `DefaultCategories`
  ///     里分 type 0-based 的 seed 口径一致)
  ///   - `orderedIds` = 最终显示顺序;没传进来的分类按原相对次序追加在后面
  ///     (比如拖动过程中有分类被删了,不至于把剩下的挤掉)
  ///   - 传进来的 id 不属于该 type 的直接忽略(防呆)
  ///
  /// **为什么整体重编号而不是「只改被拖的那几个」**:
  /// sortOrder 是稠密的相对序号,只改一两个会让排序出现空洞
  /// (比如 A=0, B=5, C=2 → 显示顺序还是 A,C,B,但空洞会让下次重排更难推理)。
  /// 整段重编号保证 [byType] 读出来的顺序 = 用户看到的顺序。
  Future<void> reorderByType(String type, List<int> orderedIds) async {
    final existing = await byType(type);
    if (existing.isEmpty) return;

    // 去重 + 只保留属于该 type 的 id
    final seen = <int>{};
    final wanted = <int>[];
    for (final id in orderedIds) {
      if (seen.add(id) && existing.any((c) => c.id == id)) {
        wanted.add(id);
      }
    }
    // 没传进来的按原相对次序补在后面
    for (final c in existing) {
      if (!seen.contains(c.id)) wanted.add(c.id);
    }

    await _db.batch((batch) {
      for (var i = 0; i < wanted.length; i++) {
        batch.update(
          _db.categories,
          CategoriesCompanion(sortOrder: Value(i)),
          where: (c) => c.id.equals(wanted[i]) & c.type.equals(type),
        );
      }
    });
  }

  /// 全部分类(按 sortOrder 升序)
  Future<List<Category>> all() {
    return (_db.select(
      _db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
  }

  /// 按 type 取
  Future<List<Category>> byType(String type) {
    return (_db.select(_db.categories)
          ..where((c) => c.type.equals(type))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  /// 按 name 找分类(返回 first 或 null),用于 D72 asset_form 编辑期初余额时
  /// 查找"余额调整"系统 cat。name 在 DB 唯一(unique index 在 schema 上,但
  /// 这里保险用 getSingleOrNull)。
  Future<Category?> findByName(String name) {
    return (_db.select(_db.categories)..where((c) => c.name.equals(name)))
        .getSingleOrNull();
  }

  /// 新增分类
  ///
  /// 2026-10-22 D64.98:`sortOrder` 不传时**落在同类的最后**(max + 1),
  /// 不再默认 0。
  /// 原来默认 0 → 新建的分类跟该类型第一类的 sortOrder 撞车,两条都是 0,
  /// 谁在前面由 SQLite 决定(实际按 rowid)→ **看起来是"随机插在中间"**。
  /// 用户能拖动排序之后,新建分类明确追加到末尾才说得通(要挪可以自己拖)。
  Future<int> create({
    required String name,
    required String icon,
    required int color,
    required String type,
    int? sortOrder,
  }) async {
    var order = sortOrder;
    if (order == null) {
      final tail = await (_db.select(_db.categories)
            ..where((c) => c.type.equals(type))
            ..orderBy([(c) => OrderingTerm.desc(c.sortOrder)])
            ..limit(1))
          .get();
      order = tail.isEmpty ? 0 : tail.first.sortOrder + 1;
    }
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: name,
            icon: icon,
            color: color,
            type: type,
            isSystem: const Value(false),
            sortOrder: Value(order),
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
      // 2026-10-14 加:福利分类色同步(同结构)
      for (final c in DefaultCategories.benefit) {
        batch.update(
          _db.categories,
          CategoriesCompanion(color: Value(c.color.toARGB32())),
          where: (cat) => cat.name.equals(c.name) & cat.isSystem.equals(true),
        );
      }
      // 2026-10-14 加:债权段 1 cat 色同步(负债)
      for (final c in DefaultCategories.receivable) {
        batch.update(
          _db.categories,
          CategoriesCompanion(color: Value(c.color.toARGB32())),
          where: (cat) => cat.name.equals(c.name) & cat.isSystem.equals(true),
        );
      }
      // 2026-10-14 D57 加:其它段 1 cat 色同步(其它,同福利/债权 pattern)
      for (final c in DefaultCategories.other) {
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
