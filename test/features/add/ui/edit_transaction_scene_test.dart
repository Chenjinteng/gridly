// test/features/add/ui/edit_transaction_scene_test.dart
// 2026-10-20 D64.84
//
// 目的:锁死「编辑一笔流水时,打开的必须是这笔记录所属的记一笔场景」
//
// user 2026-10-20 UAT 截图(流水页 → 投资记录 → 点「编辑」):
//   打开的却是「支出 / 收入 / 调拨」的 cash_flow 表单,不是「投入 / 收益 /
//   调拨」的投资表单 —— 切换条完全不对。
//
// 根因:EditTransactionPage 只传了 editTransaction,没传 preselectedAssetType,
//   TransactionForm 的 _isInvestmentContext 全靠 widget.preselectedAssetType
//   判定 → 一律落到 cash_flow 分支。
//   (D64.84/D64.85 在 form 里写的"投资记录编辑 pre-fill 映射"因此是死代码)
//
// 用错表单的三重数据风险:
//   ① type='balance' 记录(投入 / 调拨)→ destForSave=null → **转入账户被丢弃**
//   ② 分类选择器出现 → user 可能把分类换成普通分类 → 记录脱离投资口径
//   ③ 债务记录 type='lend_out' 不在 cashFlowSegments 里 → toggle 无选中态
//
// 覆盖:
//   1. 各分类 → 各场景的 toggle(投入/收益/借出/支出)+ 选中段
//   2. 投资亏损行(迁移数据 cat=投资收益 + type=expense + 正金额)→ 收益段
//      + 金额展示为负
//   3. 保存投资投入记录 → 转入账户不丢
//   4. 保存投资亏损记录 → 规范化成 type=income + 负金额 + 「投资亏损」分类,
//      且**余额效果不变**
//   5. 编辑模式余额校验:只改备注(金额没动)也能存
import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/database/repositories/asset_repository.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/features/add/ui/edit_transaction_page.dart';
import 'package:gridly/features/add/ui/widgets/amount_display.dart';

void main() {
  late AppDatabase db;
  late int cashId; // 招行工资卡 cash_flow
  late int fundId; // 基金 investment
  late int debtId; // 花呗 receivable
  late int catInvestIn; // 投资投入
  late int catInvestOut; // 投资收益
  late int catDebt; // 债务
  late int catFood; // 餐饮(普通分类)

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
    cashId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '招行工资卡', type: 'cash_flow'),
    );
    fundId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '基金', type: 'investment'),
    );
    debtId = await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '花呗', type: 'receivable'),
    );
    await CategoryRepository(db).seedDefaultsIfEmpty();
    Future<int> catId(String name) async {
      final c = await (db.select(db.categories)
            ..where((c) => c.name.equals(name)))
          .getSingle();
      return c.id;
    }

    catInvestIn = await catId('投资投入');
    catInvestOut = await catId('投资收益');
    catDebt = await catId('债务');
    catFood = await catId('餐饮');
    // 「投资费用」不在 App 内置分类里(迁移库带过来的),这里补一个用于测试
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '投资费用',
        icon: 'receipt_long',
        color: 0xFF9CA3AF,
        type: 'investment',
        sortOrder: const Value(3),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addTx({
    required int categoryId,
    required String type,
    required double amount,
    required int accountId,
    int? destId,
    String? note,
  }) {
    return db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: amount,
        type: type,
        categoryId: categoryId,
        accountId: accountId,
        destinationAccountId: Value(destId),
        note: Value(note),
        occurredAt: DateTime(2026, 10, 20, 10, 30),
      ),
    );
  }

  /// 泵出编辑页(带最小 GoRouter,给 context.pop() 用)
  Future<GoRouter> pumpEdit(WidgetTester tester, int txId) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => db)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    await tester.pump();
    // 从首页 push 进编辑页(保存后 context.pop() 要有栈可退)
    router.push('/edit/$txId');
    // 等两件事落地:
    //   ① 路由 push 过渡(AppMotion.normal ≈ 480ms)
    //   ② D64.85 的"投入 vs 调拨"判定(异步查 source asset 后 setState)
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  /// 段是否选中(选中的 fontWeight=w700,未选 w500)
  bool isSelected(WidgetTester tester, String label) {
    final ctx = tester.element(find.text(label));
    return DefaultTextStyle.of(ctx).style.fontWeight == FontWeight.w700;
  }

  group('编辑页按分类推导场景', () {
    testWidgets('投资投入记录 → 投资 toggle(投入/收益/调拨)+ 投入选中',
        (tester) async {
      final id = await addTx(
        categoryId: catInvestIn,
        type: 'balance',
        amount: 1000,
        accountId: cashId,
        destId: fundId,
      );
      await pumpEdit(tester, id);

      expect(find.text('投入'), findsOneWidget);
      expect(find.text('收益'), findsOneWidget);
      expect(find.text('支出'), findsNothing); // 不是 cash_flow 表单
      expect(isSelected(tester, '投入'), isTrue);
    });

    testWidgets('投资收益记录 → 投资 toggle + 收益选中', (tester) async {
      final id = await addTx(
        categoryId: catInvestOut,
        type: 'income',
        amount: 592.77,
        accountId: fundId,
      );
      await pumpEdit(tester, id);

      expect(find.text('投入'), findsOneWidget);
      expect(find.text('支出'), findsNothing);
      expect(isSelected(tester, '收益'), isTrue);
    });

    testWidgets('投资亏损行(迁移数据)→ 收益段 + 金额展示为负', (tester) async {
      // 迁移数据口径:cat=投资收益 + type='expense' + 正金额(语义是亏损)
      final id = await addTx(
        categoryId: catInvestOut,
        type: 'expense',
        amount: 592.77,
        accountId: fundId,
        note: '整月',
      );
      await pumpEdit(tester, id);

      expect(isSelected(tester, '收益'), isTrue);
      // 金额规范化成负数展示(保存后 type=income + 负金额,余额效果不变)
      // AmountDisplay 把负号拆出来放 ¥ 前面 → 数字部分是绝对值
      final amountArea = find.byType(AmountDisplay);
      expect(
        find.descendant(of: amountArea, matching: find.text('592.77')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: amountArea, matching: find.text('-')),
        findsOneWidget,
      );
    });

    testWidgets('债务借出记录 → 债务 toggle(借出/借入/调拨)+ 借出选中',
        (tester) async {
      final id = await addTx(
        categoryId: catDebt,
        type: 'lend_out',
        amount: 500,
        accountId: debtId,
      );
      await pumpEdit(tester, id);

      expect(find.text('借出'), findsOneWidget);
      expect(find.text('借入'), findsOneWidget);
      expect(find.text('支出'), findsNothing);
      expect(isSelected(tester, '借出'), isTrue);
    });

    testWidgets('日常支出记录 → cash_flow toggle + 支出选中', (tester) async {
      final id = await addTx(
        categoryId: catFood,
        type: 'expense',
        amount: 88,
        accountId: cashId,
      );
      await pumpEdit(tester, id);

      expect(find.text('支出'), findsOneWidget);
      expect(find.text('收入'), findsOneWidget);
      expect(find.text('投入'), findsNothing);
      expect(isSelected(tester, '支出'), isTrue);
    });
  });

  group('编辑保存不丢数据', () {
    testWidgets('投资投入记录保存后转入账户不丢', (tester) async {
      // 源账户余额给足 —— 否则会被"余额不足"拦在保存之前,
      // 断言会"因为根本没保存"而假通过
      await (db.update(db.assets)
            ..where((a) => a.id.equals(cashId)))
          .write(AssetsCompanion(initialBalance: const Value(10000.0)));
      final id = await addTx(
        categoryId: catInvestIn,
        type: 'balance',
        amount: 1000,
        accountId: cashId,
        destId: fundId,
      );
      await pumpEdit(tester, id);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('余额'), findsNothing);
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tx.destinationAccountId, fundId);
      expect(tx.type, 'balance');
      expect(tx.accountId, cashId);
    });

    testWidgets('投资亏损行保存后规范化:type=income + 负金额 + 投资亏损分类',
        (tester) async {
      final id = await addTx(
        categoryId: catInvestOut,
        type: 'expense',
        amount: 592.77,
        accountId: fundId,
      );
      await pumpEdit(tester, id);

      // 改动前:expense + 正金额 → 余额 delta = -592.77
      final before =
          await AssetRepository(db).balanceDeltaByAssetId();
      expect(before[fundId], -592.77);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tx.type, 'income');
      expect(tx.amount, -592.77);
      final cat = await (db.select(db.categories)
            ..where((c) => c.id.equals(tx.categoryId)))
          .getSingle();
      expect(cat.name, '投资亏损');
      expect(cat.type, 'investment');

      // 余额效果不变(expense -Σ(+592.77) == income +Σ(-592.77))
      final after = await AssetRepository(db).balanceDeltaByAssetId();
      expect(after[fundId], before[fundId]);
    });

    testWidgets('编辑模式余额校验:只改备注(金额没动)也能存', (tester) async {
      // 账户余额刚好被本笔扣光:余额 0,本笔 1000
      await (db.update(db.assets)
            ..where((a) => a.id.equals(cashId)))
          .write(AssetsCompanion(initialBalance: const Value(1000.0)));
      final id = await addTx(
        categoryId: catFood,
        type: 'expense',
        amount: 1000,
        accountId: cashId,
        note: '改备注',
      );
      await pumpEdit(tester, id);

      // 余额已被本笔扣成 0 —— 不修校验的话这里会被"余额不足"拦死
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('余额'), findsNothing);
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tx.amount, 1000);
    });

    testWidgets('投资费用(手续费)编辑后保持原样:不被当成亏损', (tester) async {
      // 「投资费用」cat + type='expense' + 正金额 = 真费用(迁移库实测 4 条)
      // 不能跟「投资收益 + expense」(亏损)混为一谈
      final feeCatId = await (db.select(db.categories)
            ..where((c) => c.name.equals('投资费用')))
          .getSingle();
      final id = await addTx(
        categoryId: feeCatId.id,
        type: 'expense',
        amount: 39.08,
        accountId: fundId,
        note: '转换手续',
      );
      await pumpEdit(tester, id);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tx.type, 'expense'); // 保持 expense(不是 income)
      expect(tx.amount, 39.08); // 金额不被取负
      expect(tx.categoryId, feeCatId.id); // 分类不被换成"投资收益"/"投资亏损"
    });

    testWidgets('编辑时分类保持原样(不被重新推导)', (tester) async {
      await (db.update(db.assets)
            ..where((a) => a.id.equals(cashId)))
          .write(AssetsCompanion(initialBalance: const Value(10000.0)));
      final id = await addTx(
        categoryId: catInvestIn,
        type: 'balance',
        amount: 1000,
        accountId: cashId,
        destId: fundId,
      );
      await pumpEdit(tester, id);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(tx.categoryId, catInvestIn);
    });
  });
}
