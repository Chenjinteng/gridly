// test/features/ledger/ui/summary_semantic_color_test.dart
// 2026-10-20 D64.75
//
// 目的:锁死「小结正负 = 绿 / 红」且**全主题恒定**。
//
// 背景(user 反馈原文):
//   "每天的小结,+是黄色,-是红色,这个是一定要调整的;
//    切换到粉色主题的话,每日小结正负就都是红色了,这个也要统一。
//    小结这里是要绿色为正,红色为负。"
//
// 成因:
//   收入金额色走 theme.colorScheme.secondary —— 默认主题 = AppBrand.gold(金黄),
//   粉红主题 = AppPinkBrand.gold(#FF5C8A 亮粉)。亮粉跟支出红(#EF4444)在粉底上
//   几乎分不开 → 视觉上「正负都是红」。
//
// 修复:
//   收支金额色统一走 AppSemantic.income(绿 #14B8A6)/ AppSemantic.expense(红 #EF4444),
//   硬编码 brand 色,**不跟 palette / colorScheme 走**。
//
// 覆盖 3 个小结面 × 4 个主题(默认浅 / 默认深 / 粉浅 / 粉深):
//   1. 每日小结  —— ledger_page.dart `_DaySection` 的 +收入 / -支出
//   2. 月度汇总卡 —— monthly_summary.dart `MonthlySummary` 的 收入 / 支出 cell
//   3. 区间汇总  —— range_summary.dart `RangeSummary` 的 收入 / 支出 stat
//
// 外加一条防回退断言:小结色 ≠ colorScheme.secondary
//   (有人再把收入色改回跟随 palette,这条立刻炸)
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/theme/app_colors.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/core/theme/gridly_palette.dart';
import 'package:gridly/core/utils/asset_balance_provider.dart';
import 'package:gridly/features/ledger/application/transactions_providers.dart';
import 'package:gridly/features/ledger/ui/ledger_page.dart';
import 'package:gridly/features/ledger/ui/widgets/monthly_summary.dart';
import 'package:gridly/features/stats/application/stats_providers.dart';
import 'package:gridly/features/stats/ui/widgets/range_summary.dart';

/// 4 个主题 —— 正负语义色必须在这 4 个下完全一致
final Map<String, ThemeData> _themes = {
  '默认浅色': AppTheme.light(),
  '默认深色': AppTheme.dark(),
  '粉红浅色': AppTheme.pinkLight(),
  '粉红深色': AppTheme.darkWithPalette(GridlyPalette.darkPink),
};

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await Migrator(db).createAll();
  });

  tearDown(() async {
    await db.close();
  });

  Transaction mkTx({
    required int id,
    required double amount,
    required String type,
    required DateTime occurredAt,
  }) {
    return Transaction(
      id: id,
      amount: amount,
      type: type,
      categoryId: 1,
      occurredAt: occurredAt,
      note: 'n$id',
      accountId: 1,
      createdAt: occurredAt,
      updatedAt: occurredAt,
    );
  }

  /// 通用 override:分类 / 资产都空(小结口径不受影响),DB 走 in-memory
  List<Override> baseOverrides() => [
    databaseProvider.overrideWith((ref) => db),
    allCategoriesProvider.overrideWith((ref) async => <Category>[]),
    allAssetsProvider.overrideWith((ref) async => <Asset>[]),
  ];

  group('每日小结(流水页 _DaySection)', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:+收入 = 绿,-支出 = 红', (tester) async {
        final theme = entry.value;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final grouped = {
          today: [
            mkTx(
              id: 1,
              amount: 500,
              type: 'income',
              occurredAt: today.add(const Duration(hours: 10)),
            ),
            mkTx(
              id: 2,
              amount: 120,
              type: 'expense',
              occurredAt: today.add(const Duration(hours: 11)),
            ),
          ],
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...baseOverrides(),
              filteredTransactionsByDayProvider.overrideWith(
                (ref) async => grouped,
              ),
            ],
            child: MaterialApp(theme: theme, home: const LedgerPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // 每日小结渲染成 '+¥500.00 '(带尾空格)+ '-¥120.00';
        // 流水 tile 渲染成 '+ ¥500.00'(prefix 后有空格)→ 两者不会撞
        final income = tester.widget<Text>(find.text('+¥500.00 '));
        final expense = tester.widget<Text>(find.text('-¥120.00'));

        expect(
          income.style?.color,
          AppBrand.teal,
          reason: '${entry.key} 每日小结收入必须是绿(AppBrand.teal)',
        );
        expect(
          expense.style?.color,
          AppStatus.error,
          reason: '${entry.key} 每日小结支出必须是红(AppStatus.error)',
        );
        // 防回退:不能又变回跟随 palette 的 colorScheme.secondary
        expect(
          income.style?.color,
          isNot(theme.colorScheme.secondary),
          reason: '${entry.key} 小结色不能跟 colorScheme.secondary(会随主题变)',
        );
      });
    }
  });

  group('月度汇总卡(MonthlySummary)', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:收入 = 绿,支出 = 红', (tester) async {
        final theme = entry.value;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...baseOverrides(),
              monthSummaryProvider.overrideWithValue(
                const MonthSummary(income: 1000, expense: 200),
              ),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MonthlySummary(
                  localVisible: true,
                  onToggleLocal: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // 卡片里 3 个金额:结余 ¥800.00 / 收入 ¥1,000.00 / 支出 ¥200.00
        final income = tester.widget<Text>(find.text('¥1,000.00'));
        final expense = tester.widget<Text>(find.text('¥200.00'));

        expect(
          income.style?.color,
          AppBrand.teal,
          reason: '${entry.key} 月度汇总收入必须是绿',
        );
        expect(
          expense.style?.color,
          AppStatus.error,
          reason: '${entry.key} 月度汇总支出必须是红',
        );
        expect(
          income.style?.color,
          isNot(theme.colorScheme.secondary),
          reason: '${entry.key} 月度汇总收入色不能跟 colorScheme.secondary',
        );
      });
    }
  });

  group('区间汇总(RangeSummary)', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:收入 = 绿,支出 = 红', (tester) async {
        final theme = entry.value;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...baseOverrides(),
              statsSummaryProvider.overrideWithValue(
                const StatsSummary(income: 1000, expense: 200),
              ),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(body: const RangeSummary()),
            ),
          ),
        );
        await tester.pump();
        // AnimatedCounter 480ms 滚动到位
        await tester.pump(const Duration(milliseconds: 600));

        final income = tester.widget<Text>(find.text('¥1,000.00'));
        final expense = tester.widget<Text>(find.text('¥200.00'));

        expect(
          income.style?.color,
          AppBrand.teal,
          reason: '${entry.key} 区间汇总收入必须是绿',
        );
        expect(
          expense.style?.color,
          AppStatus.error,
          reason: '${entry.key} 区间汇总支出必须是红',
        );
      });
    }
  });

  group('语义 token 本身', () {
    test('AppSemantic.income = 绿,expense = 红', () {
      expect(AppSemantic.income, AppBrand.teal);
      expect(AppSemantic.expense, AppStatus.error);
    });

    test('balanceFor 正绿负红(跟 income/expense 同源)', () {
      expect(AppSemantic.balanceFor(1), AppSemantic.income);
      expect(AppSemantic.balanceFor(-1), AppSemantic.expense);
    });
  });
}
