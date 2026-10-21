// test/features/stats/ui/top_expenses_count_tab_test.dart
// 2026-10-21 D64.90
//
// 目的:锁死「年视角 Top 10 支出改「笔数 / 均价」tab」
//
// user 2026-10-21 UAT:
//   "切换到全年视角的话,TOP10 的单笔支出就基本是每个月的房租,
//    12 个月的话 top10 被它霸屏了,有用的就只有 top10 分类"
//   → 年视角下"单笔"的排序键(单笔金额)被固定开销占满,信息密度归零
//   → 年视角第一个 tab 换成"笔数":每行 = 分类 + 均价 + 合计 + N 笔
//   → 月视角不动(一个月里房租就一条,单笔榜是正常的)
//
// 断言:
//   1. 年视角 tab = 笔数 / 分类(没有"单笔")
//   2. 月视角 tab = 单笔 / 分类(没动)
//   3. 笔数 tab 每行 = 分类名 + "均价 ¥X · 合计 ¥Y" + 大号 "N 笔"
//   4. 排序按笔数降序(笔数多的排前面)
//   5. 回归:12 笔房租在年视角只占 1 行(不再霸屏 12 行)
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/features/stats/application/stats_providers.dart';
import 'package:gridly/features/stats/ui/widgets/top_expenses.dart';

void main() {
  late AppDatabase db;
  late int rentCatId;
  late int mealCatId;
  late int photoCatId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '现金', type: 'cash_flow'),
    );
    rentCatId = await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '房租',
        icon: 'home',
        color: 0xFFF59E0B,
        type: 'expense',
      ),
    );
    mealCatId = await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '正餐',
        icon: 'restaurant',
        color: 0xFFEF4444,
        type: 'expense',
      ),
    );
    photoCatId = await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: '胶片摄影',
        icon: 'camera',
        color: 0xFF8B5CF6,
        type: 'expense',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 记一笔支出
  Future<void> addExpense(
    int catId,
    double amount,
    DateTime at, {
    String type = 'expense',
  }) async {
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: amount,
        type: type,
        categoryId: catId,
        accountId: 1,
        occurredAt: at,
      ),
    );
  }

  /// 造一份"年视角"数据:12 笔房租(每月 1 笔)+ 5 笔正餐 + 1 笔胶片摄影
  Future<void> seedYearData() async {
    final now = DateTime.now();
    for (int m = 1; m <= 12; m++) {
      await addExpense(rentCatId, 3400, DateTime(now.year, m, 1));
    }
    for (int i = 0; i < 5; i++) {
      await addExpense(mealCatId, 60, DateTime(now.year, 3, 2 + i));
    }
    await addExpense(photoCatId, 9353, DateTime(now.year, 4, 28));
  }

  /// 造一份"月视角"数据(本月内):2 笔房租 + 1 笔正餐
  Future<void> seedMonthData() async {
    final now = DateTime.now();
    await addExpense(rentCatId, 3400, DateTime(now.year, now.month, 1));
    await addExpense(rentCatId, 3400, DateTime(now.year, now.month, 2));
    await addExpense(mealCatId, 60, DateTime(now.year, now.month, 3));
  }

  Widget wrap(StatsRange range) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        statsRangeProvider.overrideWith((ref) => range),
      ],
      child: const MaterialApp(home: Scaffold(body: TopExpenses())),
    );
  }

  /// 测试视口默认 800x600,放不下 ChartCard(标题 + 520 高的 TabBarView)会溢出
  /// 真机里这张卡在滚动视图里,空间充足
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('年视角:第一个 tab 是「笔数」,没有「单笔」', (tester) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('笔数'), findsOneWidget);
    expect(find.text('单笔'), findsNothing);
    expect(find.text('分类'), findsOneWidget);
  });

  testWidgets('月视角:保持「单笔」,没有「笔数」', (tester) async {
    useTallViewport(tester);
    await seedMonthData();
    await tester.pumpWidget(wrap(StatsRange.thisMonth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('单笔'), findsOneWidget);
    expect(find.text('笔数'), findsNothing);
  });

  testWidgets('笔数 tab:每行 = 分类 + 均价/合计 + N 笔,按笔数降序', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 笔数:房租 12 / 正餐 5 / 胶片摄影 1
    expect(find.text('12 笔'), findsOneWidget);
    expect(find.text('5 笔'), findsOneWidget);
    expect(find.text('1 笔'), findsOneWidget);

    // 均价 + 合计
    expect(find.text('均价 ¥3,400 · 合计 ¥40,800'), findsOneWidget);
    expect(find.text('均价 ¥60 · 合计 ¥300'), findsOneWidget);
    expect(find.text('均价 ¥9,353 · 合计 ¥9,353'), findsOneWidget);

    // 排序:笔数多的在上
    final rentY = tester.getTopLeft(find.text('房租')).dy;
    final mealY = tester.getTopLeft(find.text('正餐')).dy;
    final photoY = tester.getTopLeft(find.text('胶片摄影')).dy;
    expect(rentY, lessThan(mealY));
    expect(mealY, lessThan(photoY));
  });

  testWidgets('回归:12 笔房租在年视角只占 1 行,不再霸屏', (tester) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 「房租」只出现一次(旧口径下会出现 12 行)
    expect(find.text('房租'), findsOneWidget);
    // 分类行总数 = 3 个分类(+ 不应再有 12 个重复的房租行)
    expect(find.text('12 笔'), findsOneWidget);
  });

  testWidgets('窄屏(390 宽)不溢出:均价/合计 副标题能截断', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 副标题「均价 ¥3,400 · 合计 ¥40,800」在窄屏放不下时按 ellipsis 截断,
    // 不能抛 RenderFlex overflow
    expect(tester.takeException(), isNull);
    expect(find.text('12 笔'), findsOneWidget);
  });
}
