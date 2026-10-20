// test/features/ledger/ui/transaction_amount_color_test.dart
// 2026-10-20 D64.76
//
// 目的:锁死"流水列表金额色 = 收支语义色(绿正 / 红负)",且跨主题恒定。
//
// 背景(user 反馈):
//   "因为大问题的都是流动资金,就会会有大面积的亮蓝色,有点不是很好分辨,
//    我在想要不要调整。" → 选方案 1
//
// 改前:流水金额色 = 资产段色(AppSegment.colorFor),cash_flow 段是
//   亮蓝 #0EA5E9,几乎所有流水都是这个色,收入/支出只能读 +/- 符号。
// 改后:流水金额色 = TxDisplayStyle 集中表(跟"记一笔"大数字同一张表):
//   支出红 / 收入绿 / 调拨浅金(中性) / 借出橙 / 借入红。
//   资产段色退到账户 chip 的 icon 上(信息不丢)。
//
// 覆盖:
//   1. 5 种 type 的金额色正确
//   2. × 4 主题(默认浅 / 默认深 / 粉浅 / 粉深)结果一致
//   3. 账户 chip 的 icon 仍是资产段色(段色没丢)
import 'package:drift/drift.dart' as drift;
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
import 'package:gridly/features/ledger/ui/widgets/transaction_tile.dart';

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
    await drift.Migrator(db).createAll();
    // 账户 id=1,cash_flow 段 —— chip icon 应显示流动资金段色
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '招行工资卡', type: 'cash_flow'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Transaction mkTx({
    required int id,
    required double amount,
    required String type,
  }) {
    final now = DateTime(2026, 10, 20, 10, 30);
    return Transaction(
      id: id,
      amount: amount,
      type: type,
      categoryId: 1,
      occurredAt: now,
      note: 'n$id',
      accountId: 1,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<Override> baseOverrides() => [
    databaseProvider.overrideWith((ref) => db),
    allCategoriesProvider.overrideWith((ref) async => <Category>[]),
    allAssetsProvider.overrideWith((ref) async => <Asset>[]),
  ];

  group('流水 tile 金额色', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:绿正红负,5 种 type 各归其位', (tester) async {
        final theme = entry.value;

        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Column(
                  children: [
                    TransactionTile(
                      transaction: mkTx(
                        id: 1,
                        amount: 500,
                        type: 'income',
                      ),
                    ),
                    TransactionTile(
                      transaction: mkTx(
                        id: 2,
                        amount: 120,
                        type: 'expense',
                      ),
                    ),
                    TransactionTile(
                      transaction: mkTx(
                        id: 3,
                        amount: 300,
                        type: 'balance',
                      ),
                    ),
                    TransactionTile(
                      transaction: mkTx(
                        id: 4,
                        amount: 1000,
                        type: 'lend_out',
                      ),
                    ),
                    TransactionTile(
                      transaction: mkTx(
                        id: 5,
                        amount: 2000,
                        type: 'borrow_in',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        Color colorOf(String text) =>
            tester.widget<Text>(find.text(text)).style!.color!;

        // 收入绿 / 支出红
        expect(colorOf('+ ¥500.00'), AppSemantic.income);
        expect(colorOf('- ¥120.00'), AppSemantic.expense);
        // 调拨无正负 → 中性浅金
        expect(colorOf('¥300.00'), AppSecondary.softGold);
        // D51 决策:债务段保留借出/借入自己的语义色,不套普通收支绿红
        expect(colorOf('- ¥1,000.00'), AppSegment.receivable);
        expect(colorOf('+ ¥2,000.00'), AppStatus.error);

        // 防回退:金额色不能又变回资产段色(亮蓝)
        expect(
          colorOf('+ ¥500.00'),
          isNot(AppSegment.cashFlow),
          reason: '${entry.key} 流水金额不能回退成流动资金段色(亮蓝)',
        );
        expect(colorOf('- ¥120.00'), isNot(AppSegment.cashFlow));
      });
    }
  });

  group('账户 chip 仍带资产段色', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:chip icon = 流动资金段色', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: MaterialApp(
              theme: entry.value,
              home: Scaffold(
                body: TransactionTile(
                  transaction: mkTx(id: 1, amount: 500, type: 'income'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final icons = tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(TransactionTile),
            matching: find.byType(Icon),
          ),
        );
        expect(
          icons.any((i) => i.color == AppSegment.cashFlow),
          isTrue,
          reason: '${entry.key} 账户 chip icon 应保留资产段色(段色退到 chip,没丢)',
        );
      });
    }
  });
}
