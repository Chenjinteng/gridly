// test/features/add/ui/edit_transaction_amount_refresh_test.dart
// 2026-10-22 D64.93
//
// 目的:锁死「编辑流水后,再次打开编辑页显示的是**新**金额」
//
// user 2026-10-22 UAT 截图(流水页 → 其它 -¥28.00 → 左滑 → 编辑):
//   ① 流水列表显示 -¥28.00        ✓ 对
//   ② 资产总额也按 28 算            ✓ 对
//   ③ **再次打开这条 28 的流水,编辑页显示 ¥32.5**(旧金额)  ✗ 错
//
// user 操作序列:原始金额 32.5(记错了)→ 编辑 → 计算器做 32.5 - 4.5 = 28
//   → 保存 → 流水和资产都变 28 → 但再开编辑页还是 32.5
//
// 根因:EditTransactionPage 用 `ref.watch(transactionByIdProvider(id))` 取这笔流水,
//   而 refreshAllData()(保存后统一刷新用)��的 provider 清单里**漏了
//   transactionByIdProvider** → 它的缓存里还是 amount=32.5 的旧对象。
//   → 重新打开编辑页时 provider 立刻返回旧值 → TransactionForm.initState
//     用 t.amount 填 _calc.display → 显示 32.5。
//
//   流水列表走 allTransactionsByDayProvider / filteredTransactionsByDayProvider
//   (都在刷新清单里)→ 显示 28 ✓
//   资产走 assetBalancesProvider(在清单里)→ 余额对 ✓
//   → 三处表现不一致,正是因为只有编辑页这条数据路径漏刷。
//
// 这个 bug 模式在本项目**已经犯过两次**(commit 84 / D64.83),refresh_providers.dart
// 里都留了"跟 commit 84 同模式 bug 重复犯"的注释 —— 本测试防止第三次。
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/features/add/ui/edit_transaction_page.dart';
import 'package:gridly/features/add/ui/widgets/amount_display.dart';
import 'package:gridly/features/add/ui/widgets/numpad.dart';

void main() {
  late AppDatabase db;
  late int cashId;
  late int catOther;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
    cashId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '招行工资卡', type: 'cash_flow'),
    );
    // 余额给足,避免被"余额不足"拦在保存之前
    await (db.update(db.assets)..where((a) => a.id.equals(cashId)))
        .write(AssetsCompanion(initialBalance: const Value(10000.0)));
    await CategoryRepository(db).seedDefaultsIfEmpty();
    // 用「餐饮」(cat.type='expense')—— 跟用户真机那条流水同属 cash_flow 场景
    // (迁移库里有两条「其它」:一条 type=other、一条 type=expense;
    //  用户截图那条是 type=expense 的,所以编辑页显示的是「支出/收入/调拨」)
    catOther = await (db.select(db.categories)
          ..where((c) => c.name.equals('餐饮')))
        .getSingle()
        .then((c) => c.id);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addTx({required double amount, String? note}) {
    return db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: amount,
        type: 'expense',
        categoryId: catOther,
        accountId: cashId,
        note: Value(note),
        occurredAt: DateTime(2026, 10, 21, 9, 0),
      ),
    );
  }

  /// 起一个带编辑路由的 app,返回 router
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/edit/:id',
          builder: (context, state) => EditTransactionPage(
            transactionId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    // 2026-10-22:跟生产 main.dart 结构**完全一致** —— UncontrolledProviderScope
    // + 独立 root ProviderContainer(不是 ProviderScope)
    //   原因:ProviderScope(overrides:) 会额外建一层**子 container**,
    //   而 Riverpod 的 family provider invalidate 走的是
    //   `_overrideForFamily[family]?.container ?? _root ?? this` 这条路径,
    //   root / 子 container 走的是不同的 _stateReaders —— 用错结构测就可能有盲区。
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    await tester.pump();
    return router;
  }

  /// push 进编辑页并等稳
  Future<void> openEditor(WidgetTester tester, GoRouter router, int txId) async {
    router.push('/edit/$txId');
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 当前编辑页显示的金额数字(AmountDisplay 里的数字部分)
  String shownAmount(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(AmountDisplay),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    // AmountDisplay 结构:¥ + 数字(可能前置负号)
    return texts.where((t) => t != '¥' && t != '-').join();
  }

  Future<void> tapKey(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(Numpad),
      matching: find.text(label),
    ));
    await tester.pump();
  }

  testWidgets('D64.93:用计算器改金额保存后,再次打开编辑页显示新金额',
      (tester) async {
    final id = await addTx(amount: 32.5, note: '烟');
    final router = await pumpApp(tester);

    // ── 第一次打开:显示原始金额 32.5 ──
    await openEditor(tester, router, id);
    expect(shownAmount(tester), '32.5');

    // ── 用计算器做 32.5 - 4.5 ──
    await tapKey(tester, '-');
    await tapKey(tester, '4');
    await tapKey(tester, '.');
    await tapKey(tester, '5');
    await tapKey(tester, '=');
    expect(shownAmount(tester), '28');

    // ── 保存 ──
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 库里确实是 28(列表 / 资产显示对就是靠这个)
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(tx.amount, 28);

    // ── 再次打开编辑页:必须显示 28,不能还是 32.5 ──
    await openEditor(tester, router, id);
    expect(
      shownAmount(tester),
      '28',
      reason: 'D64.93:编辑页显示的是旧金额 —— transactionByIdProvider '
          '没进 refreshAllData 的 invalidate 清单,缓存里还是 32.5',
    );
  });
}
