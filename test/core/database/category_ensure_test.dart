// test/core/database/category_ensure_test.dart
// 2026-10-22 D64.94
//
// 目的:锁死「隐藏系统分类的幂等插入按 (name, type) 判重」
//
// 背景(gridly 迁移库实测):库里同时存在
//   id=22  name=其它  type=other    is_system=1   ← 系统隐藏兜底(其它段账户用)
//   id=46  name=其它  type=expense  is_system=0   ← 用户分类(旧账单迁移来的,105 笔流水)
//
// 两条**同名**。原来的 ensure*Categories 只按 name 判重
// (`if (!names.contains(c.name))`),名字被 id=46 占住 → 系统那条
// (其它, other) 永远补不上 → 一旦它被删,「其它段」账户记流水时
// fallback 找不到分类 → transactions.category_id NOT NULL 拿不到值。
//
// 2026-10-22 D64.95:系统隐藏那条改名「其它」→「其它资产」(跟资产段 label 统一),
// 用户的「其它」保持不变 → 上面的场景不再天然触发,但**判重口径不能退回按 name**:
// 用户随时可能自建一个叫「其它资产」的分类,占住名字。下面的夹具已按新名重写。
//
// 隐藏分类的语义由 **type** 决定,不是名字 → 判重必须按 (name, type)。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';

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

  Future<List<(int, String, String)>> cats() async {
    final rows = await db.select(db.categories).get();
    return rows.map((c) => (c.id, c.name, c.type)).toList();
  }

  test('D64.94:用户自建了同名分类(其它/expense)时,系统隐藏那条(其它/other)仍能补上',
      () async {
    // 模拟迁移后的库:用户分类「其它资产」type=expense 已存在
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '其它资产',
        icon: 'more_horiz',
        color: 0xFF9CA3AF,
        type: 'expense',
        sortOrder: const Value(122),
      ),
    );
    expect(await cats(), hasLength(1));

    await repo.ensureOtherCategories();

    final after = await cats();
    expect(
      after,
      hasLength(2),
      reason: '系统隐藏的(其它/other)必须补上 —— 名字被用户分类占了不代表它存在',
    );
    expect(after.any((c) => c.$2 == '其它资产' && c.$3 == 'other'), isTrue);
    expect(after.any((c) => c.$2 == '其它资产' && c.$3 == 'expense'), isTrue,
        reason: '用户那条不能被动到');
  });

  test('D64.94:已存在正确的那条时不重复插(幂等)', () async {
    await repo.ensureOtherCategories();
    final first = await cats();
    expect(first.where((c) => c.$3 == 'other'), hasLength(1));

    // 再跑 3 次(模拟 app 每次启动都调)
    await repo.ensureOtherCategories();
    await repo.ensureOtherCategories();
    await repo.ensureOtherCategories();

    final after = await cats();
    expect(after, hasLength(first.length));
    expect(after.where((c) => c.$3 == 'other'), hasLength(1));
  });

  test('D64.94:5 个 ensure*Categories 都能在同名用户分类存在时补上', () async {
    // 一次性把 5 个隐藏分类的名字都占掉(当用户分类,type=expense)
    for (final name in ['投资投入', '投资收益', '福利', '债务', '其它资产']) {
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          name: name,
          icon: 'more_horiz',
          color: 0xFF9CA3AF,
          type: 'expense',
          sortOrder: const Value(200),
        ),
      );
    }
    final before = await cats();
    expect(before, hasLength(5));

    await repo.ensureInvestmentCategories();
    await repo.ensureBenefitCategories();
    await repo.ensureReceivableCategories();
    await repo.ensureOtherCategories();

    final after = await cats();
    // 6 个系统隐藏分类(投资 3 + 福利 1 + 债务 1 + 其它 1)全补上
    //   投资是 3 条:投资投入 / 投资收益 / 投资亏损(D64.83 加的)
    expect(after, hasLength(11));
    expect(after.where((c) => c.$3 == 'investment'), hasLength(3));
    expect(after.where((c) => c.$3 == 'benefit'), hasLength(1));
    expect(after.where((c) => c.$3 == 'liability'), hasLength(1));
    expect(after.where((c) => c.$3 == 'other'), hasLength(1));
    // 用户那 5 条一条没少
    expect(after.where((c) => c.$3 == 'expense'), hasLength(5));
  });
}
