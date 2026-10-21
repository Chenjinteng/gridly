// test/features/stats/ui/top_expenses_count_tab_test.dart
// 2026-10-21 D64.90 / D64.92
//
// 目的:锁死「Top 10 支出」的两个 tab 结构 + 行布局
//
// D64.90(user UAT):"切换到全年视角的话,TOP10 的单笔支出就基本是每个月的房租,
//   12 个月的话 top10 被它霸屏了,有用的就只有 top10 分类"
//   → 年视角第一个 tab 从「单笔」换成「笔数」
//
// D64.92(user UAT):"居然这个一排序之后,房租的不在 top10 了"
//   → 房租"少而大"(39 笔占 20.8% 的钱)、正餐"多而小"(392 笔占 9.4%),两个维度都是真相
//   → 拆成「金额」「笔数」两个 tab,行信息完全一致,切 tab = 换排序
//
// 断言:
//   1. 年视角 tab = 金额 / 笔数(没有「单笔」)
//   2. 月视角 tab = 单笔 / 金额(没有「笔数」)
//   3. 金额 tab:按金额降序,行 = 分类 + 均价/占比 + ¥合计 + N 笔
//   4. 笔数 tab:按笔数降序,行 = 分类 + 均价/占比 + N 笔 + ¥合计
//   5. 回归:12 笔房租在笔数 tab 只占 1 行(不再霸屏)
//   6. 窄屏(390 / 320)不溢出,均价副标题完整显示不被截断
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// 年视角数据:12 笔房租(每月 1 笔)+ 5 笔正餐 + 1 笔胶片摄影
  /// 合计 40,800 + 300 + 9,353 = 50,453
  ///   按金额:房租(40,800 / 81%)→ 胶片摄影(9,353 / 19%)→ 正餐(300 / 1%)
  ///   按笔数:房租(12)→ 正餐(5)→ 胶片摄影(1)
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

  /// 月视角数据(本月内):2 笔房租 + 1 笔正餐
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

  testWidgets('年视角:tab = 金额 / 笔数,没有「单笔」', (tester) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('金额'), findsOneWidget);
    expect(find.text('笔数'), findsOneWidget);
    expect(find.text('单笔'), findsNothing);
  });

  testWidgets('月视角:tab = 单笔 / 金额,没有「笔数」', (tester) async {
    useTallViewport(tester);
    await seedMonthData();
    await tester.pumpWidget(wrap(StatsRange.thisMonth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('单笔'), findsOneWidget);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('笔数'), findsNothing);
  });

  testWidgets('金额 tab:按金额降序,行 = 均价/占比 + ¥合计 + N 笔', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 金额 tab 默认选中(第 0 个 tab)
    expect(find.text('¥40,800'), findsOneWidget); // 房租合计
    expect(find.text('12 笔'), findsOneWidget); // 房租笔数(右下小字)
    expect(find.text('均价 ¥3,400 · 81%'), findsOneWidget);
    expect(find.text('均价 ¥9,353 · 19%'), findsOneWidget);

    // 排序:金额大的在上
    final rentY = tester.getTopLeft(find.text('房租')).dy;
    final photoY = tester.getTopLeft(find.text('胶片摄影')).dy;
    final mealY = tester.getTopLeft(find.text('正餐')).dy;
    expect(rentY, lessThan(photoY));
    expect(photoY, lessThan(mealY));
  });

  testWidgets('笔数 tab:按笔数降序,行 = 均价/占比 + N 笔 + ¥合计', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 切到「笔数」tab
    await tester.tap(find.text('笔数'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('12 笔'), findsOneWidget); // 笔数是大号
    expect(find.text('¥40,800'), findsOneWidget); // 合计是右下小字
    expect(find.text('5 笔'), findsOneWidget);
    expect(find.text('1 笔'), findsOneWidget);

    // 排序:笔数多的在上
    final rentY = tester.getTopLeft(find.text('房租')).dy;
    final mealY = tester.getTopLeft(find.text('正餐')).dy;
    final photoY = tester.getTopLeft(find.text('胶片摄影')).dy;
    expect(rentY, lessThan(mealY));
    expect(mealY, lessThan(photoY));
  });

  testWidgets('回归:12 笔房租在笔数 tab 只占 1 行,不再霸屏', (tester) async {
    useTallViewport(tester);
    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('笔数'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 「房租」只出现一次(旧口径下会出现 12 行)
    expect(find.text('房租'), findsOneWidget);
    expect(find.text('12 笔'), findsOneWidget);
  });

  testWidgets('窄屏(390 宽)不溢出:均价副标题完整显示不被截断', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 不能抛 RenderFlex overflow
    expect(tester.takeException(), isNull);

    // 均价那一行必须完整显示(没被 ellipsis 截断)
    // —— user 2026-10-21 担心:"均价和合计太长,金额显示不全"
    final para = tester.renderObject<RenderParagraph>(
      find.text('均价 ¥3,400 · 81%'),
    );
    expect(para.didExceedMaxLines, isFalse);
  });

  testWidgets('窄屏(320 宽)不溢出:卡片标题行也不炸(既有 ChartCard bug)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await seedYearData();
    await tester.pumpWidget(wrap(StatsRange.thisYear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 320 宽下标题 + TabBar 自然宽度之和 > 卡片内容宽
    // (修前:RenderFlex overflowed by 39 pixels on the right)
    expect(tester.takeException(), isNull);
    final para = tester.renderObject<RenderParagraph>(
      find.text('均价 ¥3,400 · 81%'),
    );
    expect(para.didExceedMaxLines, isFalse);
  });
}
