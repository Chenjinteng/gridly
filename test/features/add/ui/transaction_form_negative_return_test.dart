// test/features/add/ui/transaction_form_negative_return_test.dart
// 2026-10-20 D64.83
//
// 目的:锁死「投资亏损(负收益)能记下来」(Bug 2 —— 记一笔(收益)记不了负收益)
//
// user 2026-10-20 UAT:
//   "并且想记录负收益时,不可以" —— 输入 0 - 184.88 后保存被 "金额要大于 0" 拦死
//
// 设计(方案 B,user 拍板):
//   DB 约定 type='income' + amount 为负(余额公式 +Σ → 账户余额减少,数学正确)
//   + 新分类「投资亏损」(cat.type='investment')
//   下游(余额公式 / 投资看板 returned / D65.3 负轴 / 报表口径)本来就按负收益设计好,
//   只是入口一直被拦住 + 显示层没按符号分色
//
// 断言:
//   1. 收益段输入负数 → 存成 type='income' + amount=-184.88 + cat='投资亏损'
//   2. 账户余额 delta = -184.88(余额公式正确)
//   3. 收益段输入 0 → 拦(金额不能为 0)
//   4. 支出段输入负数 → 仍拦(其它段不放行负数)
//   5. 流水 tile:负收益显示 "- ¥184.88" + 红色(不是 "+ ¥-184.88" 绿)
//   6. 投资看板:只记亏损时不再是"本年暂无投资"空态
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/database/repositories/asset_repository.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/theme/app_colors.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/core/utils/asset_balance_provider.dart';
import 'package:gridly/features/add/ui/transaction_form.dart';
import 'package:gridly/features/add/ui/widgets/amount_display.dart';
import 'package:gridly/features/add/ui/widgets/numpad.dart';
import 'package:gridly/features/ledger/application/transactions_providers.dart';
import 'package:gridly/features/ledger/ui/widgets/transaction_tile.dart';
import 'package:gridly/features/settings/ui/widgets/investment_dashboard.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
    // id=1 基金(investment)—— 收益记在这个账户上
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '基金', type: 'investment'),
    );
    // seed 默认分类(含 D64.83 新增的「投资亏损」)
    await CategoryRepository(db).seedDefaultsIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  /// Numpad 上的按键(限定在 Numpad 子树里,避免跟大数字显示撞)
  Finder key(String label) => find.descendant(
    of: find.byType(Numpad),
    matching: find.text(label),
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    String assetType = 'investment',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TransactionForm(preselectedAssetType: assetType),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 切到「收益」段(单账户)
  Future<void> switchToReturn(WidgetTester tester) async {
    await tester.tap(find.text('收益'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 用 Numpad 输入 "0 - 184.88 ="
  Future<void> typeNegativeReturn(WidgetTester tester) async {
    await tester.tap(key('-'));
    await tester.pump();
    for (final k in ['1', '8', '4', '.', '8', '8']) {
      await tester.tap(key(k));
      await tester.pump();
    }
    await tester.tap(key('='));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('记一笔(投资 · 收益)负收益', () {
    testWidgets('负数能保存:type=income + amount 为负 + 「投资亏损」分类',
        (tester) async {
      await pumpForm(tester);
      await switchToReturn(tester);
      await typeNegativeReturn(tester);

      // 大数字显示:"- ¥184.88"(负号在 ¥ 前,红色)
      final amountArea = find.byType(AmountDisplay);
      expect(
        find.descendant(of: amountArea, matching: find.text('184.88')),
        findsOneWidget,
      );
      final signText = tester.widget<Text>(
        find.descendant(of: amountArea, matching: find.text('-')),
      );
      expect(signText.style!.color, AppSemantic.expense);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final txs = await db.select(db.transactions).get();
      expect(txs.length, 1);
      final tx = txs.first;
      expect(tx.amount, -184.88);
      expect(tx.type, 'income');
      expect(tx.accountId, 1); // 基金
      expect(tx.destinationAccountId, isNull); // 收益是单账户

      // 分类 = 投资亏损(cat.type='investment',不进月度收支口径)
      final cat = await (db.select(db.categories)
            ..where((c) => c.id.equals(tx.categoryId)))
          .getSingle();
      expect(cat.name, '投资亏损');
      expect(cat.type, 'investment');
    });

    testWidgets('余额 delta = -184.88(余额公式正确)', (tester) async {
      await pumpForm(tester);
      await switchToReturn(tester);
      await typeNegativeReturn(tester);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final deltas = await AssetRepository(db).balanceDeltaByAssetId();
      expect(deltas[1], -184.88);
    });

    testWidgets('收益段输入 0 → 拦下(金额不能为 0)', (tester) async {
      await pumpForm(tester);
      await switchToReturn(tester);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('金额不能为 0'), findsOneWidget);
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    testWidgets('支出段输入负数 → 仍然拦(其它段不放行负数)', (tester) async {
      await pumpForm(tester, assetType: 'cash_flow');
      await typeNegativeReturn(tester);

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('金额要大于 0'), findsOneWidget);
      expect(await db.select(db.transactions).get(), isEmpty);
    });
  });

  group('负收益显示', () {
    Transaction mkTx({required int id, required double amount}) {
      final now = DateTime(2026, 10, 20, 10, 30);
      return Transaction(
        id: id,
        amount: amount,
        type: 'income',
        categoryId: 1,
        occurredAt: now,
        note: null,
        accountId: 1,
        createdAt: now,
        updatedAt: now,
      );
    }

    testWidgets('流水 tile:负收益 = "- ¥184.88" + 红色(不是绿)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) => db),
            allCategoriesProvider.overrideWith((ref) async => <Category>[]),
            allAssetsProvider.overrideWith((ref) async => <Asset>[]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: TransactionTile(transaction: mkTx(id: 1, amount: -184.88)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final text = tester.widget<Text>(find.text('- ¥184.88'));
      expect(text.style!.color, AppSemantic.expense);
      // 防回退:不能又变回 "+ ¥-184.88"(双负号)
      expect(find.textContaining('+-'), findsNothing);
      expect(find.textContaining('¥-'), findsNothing);
    });

    testWidgets('投资看板:只记亏损时不再是空态', (tester) async {
      // 一笔投资亏损:cat.type='investment' + type='income' + 负金额
      final lossCat = await (db.select(db.categories)
            ..where((c) => c.name.equals('投资亏损')))
          .getSingle();
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          amount: -184.88,
          type: 'income',
          categoryId: lossCat.id,
          accountId: 1,
          occurredAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) => db)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: InvestmentDashboard()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('本年暂无投资'), findsNothing);
      expect(find.text('投资情况'), findsOneWidget);
    });
  });
}
