// test/core/utils/refresh_all_data_test.dart
// 2026-10-22 D64.93
//
// 目的:锁死「流水数据变了之后,依赖它的 provider 都拿到新值」
//
// 背景:这个 bug 模式在本项目**已经犯过三次** ——
//   commit 84  : dailyExpenseTrendProvider / yearlyExpenseTrendProvider 漏刷
//                (user:"edit 了 7 月历史支出,12 月趋势没变")
//   D64.83     : 6 个 stats provider 漏刷(同比 / 类别对比 / 周几支出 …)
//   D64.93     : transactionByIdProvider 漏刷
//                (user:"32.5 改成 28,流水和资产都显示 28,再开编辑页还是 32.5")
//
// 根因都一样:refreshAllData() 的 invalidate 清单是**手写**的,
// 新加 provider 的人忘了同步加进去 → provider 一直吃缓存。
// 清单手写 = 静默失败 = 只能靠人肉发现,所以这个测试就是那道防线。
//
// 本测试直接调 refreshAllDataWith(一个纯 invalidate 回调),
// 模拟"保存一笔流水后"的真实刷新动作,断言各 provider 读到的是新值。
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/utils/refresh_providers.dart';
import 'package:gridly/features/ledger/application/transactions_providers.dart';
import 'package:gridly/features/settings/application/investment_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int txId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();

    final cashId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '招行工资卡', type: 'cash_flow'),
    );
    final fundId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '基金', type: 'investment'),
    );
    await CategoryRepository(db).seedDefaultsIfEmpty();
    final investCat = await (db.select(db.categories)
          ..where((c) => c.name.equals('投资投入')))
        .getSingle();

    txId = await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: 1000,
        type: 'balance',
        categoryId: investCat.id,
        accountId: cashId,
        destinationAccountId: Value(fundId),
        occurredAt: DateTime(2026, 10, 21),
      ),
    );

    container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
    );
    // 常驻 listener —— 模拟"页面开着"的状态
    // (autoDispose 的 provider 在没有 listener 时会被销毁,测不出缓存问题)
    container.listen(transactionByIdProvider(txId), (_, _) {});
    container.listen(investmentNetTotalProvider, (_, _) {});
    container.listen(investmentMonthlyProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('D64.93:改流水后,编辑页用的 transactionByIdProvider 拿到新金额', () async {
    final before = await container.read(transactionByIdProvider(txId).future);
    expect(before?.amount, 1000);

    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(amount: Value(2000)));
    refreshAllDataWith(container.invalidate);
    await container.pump();

    final after = await container.read(transactionByIdProvider(txId).future);
    expect(
      after?.amount,
      2000,
      reason: 'transactionByIdProvider 漏在 refreshAllData 清单外 → '
          '编辑页再打开显示旧金额(D64.93)',
    );
  });

  test('D64.93:改流水后,投资看板的累计净收益拿到新值', () async {
    final before = await container.read(investmentNetTotalProvider.future);
    expect(before, -1000);

    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(amount: Value(2000)));
    refreshAllDataWith(container.invalidate);
    await container.pump();

    final after = await container.read(investmentNetTotalProvider.future);
    expect(
      after,
      -2000,
      reason: 'investmentNetTotalProvider 直接跑 SQL 聚合、不 watch 任何流水 provider '
          '→ 不会级联刷新,必须显式 invalidate',
    );
  });

  test('D64.93:改流水后,投资看板的本年月度汇总拿到新值(级联刷新)', () async {
    final before = await container.read(investmentMonthlyProvider.future);
    expect(before.investedYTD, 1000);

    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(amount: Value(2000)));
    refreshAllDataWith(container.invalidate);
    await container.pump();

    final after = await container.read(investmentMonthlyProvider.future);
    // 它 watch 了 allCategoriesProvider(在清单里)→ 级联重算,不用单独 invalidate
    expect(after.investedYTD, 2000);
  });
}
