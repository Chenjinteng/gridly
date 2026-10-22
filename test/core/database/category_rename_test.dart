// test/core/database/category_rename_test.dart
// 2026-10-22 D64.95
//
// 目的:锁死「系统分类改名迁移」的行为
//
// 背景:gridly 里「其它 / 其他」一度有 3 条,极易混淆 ——
//   id=12  name=其他  type=expense  is_system=1   ← 系统的可见支出兜底
//   id=22  name=其它  type=other    is_system=1   ← 系统隐藏的其它段标签
//   id=46  name=其它  type=expense  is_system=0   ← 用户分类(旧账单迁移来的,105 笔流水)
//
// user 拍板:系统那两条改名,用户那条保留 ——
//   「其他」(expense)→「其它支出」
//   「其它」(other)  →「其它资产」(跟资产段 label 同名,口径统一)
//
// **只改 DefaultCategories 是不够的**:那对新装设备生效(seedDefaultsIfEmpty),
// 老设备库里还是旧名。而 D64.94 起系统隐藏分类的幂等判重按 (name, type),
// 于是老设备启动时 ensure 会认为「新名不存在」→ **补插一条新行** → 变成 2 条 type='other'。
// 所以必须有 renameSystemCategories(),且必须排在 ensure* 之前。
//
// 本文件锁死 5 件事:
//   1. 老设备的系统行被改名,用户行一行不动
//   2. 改名不改 id / 不改行数(流水引用关系不受影响)
//   3. 幂等(连跑 3 次结果一致)
//   4. 改名后跑 ensure 不会补插出第二条 type='other'(最关键的一条)
//   5. 新名被同 type 的行占用时跳过改名(不产生两条同名可见分类)
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/theme/app_colors.dart';
import 'package:gridly/shared/constants/default_categories.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertCat(
    String name,
    String type, {
    required bool isSystem,
    int sortOrder = 0,
  }) async {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        icon: 'more_horiz',
        color: 0xFF9CA3AF,
        type: type,
        isSystem: Value(isSystem),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  Future<List<(int, String, String, bool)>> cats() async {
    final rows = await db.select(db.categories).get();
    return rows.map((c) => (c.id, c.name, c.type, c.isSystem)).toList();
  }

  test('D64.95:老设备的系统行被改名,用户自建的分类一行不动', () async {
    // 模拟用户手机上的迁移库:id=12 系统可见支出兜底 / id=22 系统隐藏 / id=46 用户分类
    await insertCat('其他', 'expense', isSystem: true, sortOrder: 99);
    await insertCat('其它', 'other', isSystem: true);
    await insertCat('其它', 'expense', isSystem: false, sortOrder: 122);
    final before = await cats();
    expect(before, hasLength(3));

    await repo.renameSystemCategories();

    final after = await cats();
    expect(after, hasLength(3), reason: '改名不该增删行');
    // 系统可见支出兜底 → 其它支出
    expect(after.any((c) => c.$2 == '其它支出' && c.$3 == 'expense' && c.$4),
        isTrue);
    // 系统隐藏其它段标签 → 其它资产
    expect(after.any((c) => c.$2 == '其它资产' && c.$3 == 'other' && c.$4),
        isTrue);
    // 用户自建那条**保持「其它」不变**
    expect(
      after.any((c) => c.$2 == '其它' && c.$3 == 'expense' && !c.$4),
      isTrue,
      reason: '用户自建的分类不能被改名 —— 它挂着 105 笔历史流水',
    );
    // 旧名不该残留
    expect(after.any((c) => c.$2 == '其他'), isFalse);
  });

  test('D64.95:改名只改名字,id 不变(流水引用关系不受影响)', () async {
    await insertCat('其他', 'expense', isSystem: true, sortOrder: 99);
    await insertCat('其它', 'other', isSystem: true);
    final before = await cats();

    await repo.renameSystemCategories();

    final after = await cats();
    expect(after.map((c) => c.$1).toSet(), before.map((c) => c.$1).toSet(),
        reason: 'category_id 必须原样保留 —— transactions.category_id 指向它');
    // 每个 id 对应的行数没变,只是名字换了
    expect(after.firstWhere((c) => c.$1 == before.first.$1).$2, '其它支出');
  });

  test('D64.95:改名幂等(连跑 3 次结果一致)', () async {
    await insertCat('其他', 'expense', isSystem: true, sortOrder: 99);
    await insertCat('其它', 'other', isSystem: true);
    await insertCat('其它', 'expense', isSystem: false, sortOrder: 122);

    await repo.renameSystemCategories();
    final first = await cats();
    await repo.renameSystemCategories();
    await repo.renameSystemCategories();
    final after = await cats();

    expect(after, hasLength(first.length));
    expect(after.where((c) => c.$3 == 'other'), hasLength(1));
    expect(after.where((c) => c.$3 == 'expense'), hasLength(2));
  });

  test('D64.95:改名后跑 ensure 不会补插出第二条 type=other(最关键)', () async {
    // 老设备状态:系统隐藏那条还是旧名「其它」
    await insertCat('其它', 'other', isSystem: true);

    // app 启动顺序:rename → ensure
    await repo.renameSystemCategories();
    await repo.ensureOtherCategories();

    final after = await cats();
    expect(
      after.where((c) => c.$3 == 'other'),
      hasLength(1),
      reason: '改名后 ensure 必须认出「其它资产」已经存在,不能再补一条 —— '
          '否则老设备会变成 2 条 type=other',
    );
    expect(after.singleWhere((c) => c.$3 == 'other').$2, '其它资产');
  });

  test('D64.95:新名被同 type 的行占用时跳过改名(不产生两条同名)', () async {
    // 用户自己建了个叫「其它支出」的支出分类(占住新名)
    await insertCat('其它支出', 'expense', isSystem: false, sortOrder: 122);
    // 系统可见支出兜底还是旧名
    await insertCat('其他', 'expense', isSystem: true, sortOrder: 99);

    await repo.renameSystemCategories();

    final after = await cats();
    expect(after, hasLength(2));
    // 系统那条保持旧名(宁可旧名也不要两条同名可见分类)
    expect(after.any((c) => c.$2 == '其他' && c.$4), isTrue);
    // 用户那条原样
    expect(after.any((c) => c.$2 == '其它支出' && !c.$4), isTrue);
    // 不能出现两条同名同 type
    expect(
      after.where((c) => c.$2 == '其它支出' && c.$3 == 'expense'),
      hasLength(1),
    );
  });

  test('D64.95:新装设备 seed 出来就是新名,rename 是 no-op', () async {
    await repo.seedDefaultsIfEmpty();
    final before = await cats();
    expect(before.any((c) => c.$2 == '其它支出' && c.$3 == 'expense'), isTrue);
    expect(before.any((c) => c.$2 == '其它资产' && c.$3 == 'other'), isTrue);
    expect(before.any((c) => c.$2 == '其他'), isFalse);
    expect(before.any((c) => c.$2 == '其它' && c.$3 == 'other'), isFalse);

    await repo.renameSystemCategories();

    final after = await cats();
    expect(after, hasLength(before.length), reason: '新装设备不该被 rename 影响');
  });

  test('D64.95:命名口径统一 —— 资产段 label / 隐藏分类 / 可见兜底三者对得上', () {
    // 第 6 段(asset.type='other')的 UI label
    expect(AppSegment.labelFor('other'), '其它资产');
    // 其它段没有改动的段,防止误伤
    expect(AppSegment.labelFor('cash_flow'), '流动资金');
    expect(AppSegment.labelFor('investment'), '投资');
    expect(AppSegment.labelFor('benefit'), '福利');
    expect(AppSegment.labelFor('receivable'), '债务');
    expect(AppSegment.labelFor('fixed_asset'), '不动产');

    // 隐藏分类的名字跟资产段 label 一致
    expect(DefaultCategories.other.single.name, '其它资产');
    expect(DefaultCategories.other.single.type, 'other');

    // 可见支出兜底
    final fallback =
        DefaultCategories.expense.firstWhere((c) => c.sortOrder == 99);
    expect(fallback.name, '其它支出');
    expect(DefaultCategories.expense.any((c) => c.name == '其他'), isFalse,
        reason: '旧名不该留在默认分类里');

    // 改名表覆盖这两条(改 seed 忘了加映射 = 老设备永远改不了名)
    expect(
      kSystemCategoryRenames.any((r) =>
          r.oldName == '其他' &&
          r.type == 'expense' &&
          r.newName == '其它支出'),
      isTrue,
    );
    expect(
      kSystemCategoryRenames.any((r) =>
          r.oldName == '其它' &&
          r.type == 'other' &&
          r.newName == '其它资产'),
      isTrue,
    );
  });
}
