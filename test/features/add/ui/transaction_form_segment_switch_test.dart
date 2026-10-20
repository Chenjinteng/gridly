// test/features/add/ui/transaction_form_segment_switch_test.dart
// 2026-10-20 D64.83
//
// 目的:锁死「切段后账户槽位跟新段匹配」(Bug 1 —— 记一笔(投资)切段残留)
//
// user 2026-10-20 UAT 截图(记一笔 · 投资):
//   投入段预填 工资卡 → 基金,切到「收益」段后:
//   - source 槽位仍显示工资卡(收益段只允许投资账户)
//   - dest 槽位残留「基金」,而 source picker 拿 dest 当 excludeId
//     → 打开 picker 时「基金」被排除掉,一个可选账户都没有,来回切才能恢复
//
// 根因(旧代码):toggle onChanged 里先 `_intent = v` 再用 `_needsDualAccount`
//   判断要不要清,而 _needsDualAccount 读的是**新** intent → 语义反了。
//   回归引入于 0d953f8(D64.79)。
//
// 断言:
//   1. 投入 → 收益:source 换成投资账户(基金),工资卡不残留
//   2. 投入 → 收益:source picker 里「基金」可选(不被残留 dest 排除掉)
//   3. 投入 → 调拨:转出 / 转入都空(调拨不预填 —— P8 UAT "只清理就好")
//   4. cash_flow 支出 ↔ 收入:账户保留(P16 UAT 要求,防本次改动踩坏)
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/features/add/ui/transaction_form.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
    // id=1 招行工资卡(cash_flow) / id=2 基金(investment)
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '招行工资卡', type: 'cash_flow'),
    );
    await db.into(db.assets).insert(
      AssetsCompanion.insert(name: '基金', type: 'investment'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    String assetType = 'investment',
  }) async {
    // 表单带 Numpad(5 行 × 56px)+ toggle + 金额 + 操作行,默认 800x600 会溢出
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
    // initState 的 postFrameCallback 里加载资产 + 预填,多 pump 几帧让它落地
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('投资段切段', () {
    testWidgets('投入 → 收益:source 换成投资账户,工资卡不残留', (tester) async {
      await pumpForm(tester);

      // 初始:投入段预填 工资卡 → 基金
      expect(find.text('招行工资卡'), findsOneWidget);
      expect(find.text('基金'), findsOneWidget);

      await tester.tap(find.text('收益'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 收益段是单账户:source 应是投资账户(基金),工资卡不能残留
      expect(find.text('基金'), findsOneWidget);
      expect(find.text('招行工资卡'), findsNothing);
    });

    testWidgets('投入 → 收益:source picker 里「基金」可选(不被残留 dest 排除)',
        (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('收益'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 打开 source picker
      await tester.tap(find.text('基金'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // picker 头部显示可选账户数:收益段只允许 investment 账户 → 1 个(基金)
      // 回归时这里是 0 个 + 空态文案(唯一可选账户被残留 dest 排除掉)
      expect(find.text('1 个'), findsOneWidget);
      expect(find.text('还没有账户,请先到"我的 > 资产"新建'), findsNothing);
    });

    testWidgets('投入 → 调拨:转出 / 转入都空(调拨不预填)', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('调拨'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('转出'), findsOneWidget);
      expect(find.text('转入'), findsOneWidget);
      expect(find.text('招行工资卡'), findsNothing);
      expect(find.text('基金'), findsNothing);
    });

    testWidgets('收益 → 投入:source / dest 回到投入段默认(cash → investment)',
        (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('收益'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('招行工资卡'), findsNothing);

      await tester.tap(find.text('投入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('招行工资卡'), findsOneWidget);
      expect(find.text('基金'), findsOneWidget);
    });
  });

  group('cash_flow 段切段(防 P16 回归)', () {
    testWidgets('支出 ↔ 收入:账户保留(不清空)', (tester) async {
      await pumpForm(tester, assetType: 'cash_flow');

      expect(find.text('招行工资卡'), findsOneWidget);

      await tester.tap(find.text('收入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // P16 UAT user:"切换支出收入的话,这个选账户还是会清空" —— 不能清
      expect(find.text('招行工资卡'), findsOneWidget);
    });
  });
}
