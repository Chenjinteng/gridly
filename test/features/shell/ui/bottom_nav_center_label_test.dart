// test/features/shell/ui/bottom_nav_center_label_test.dart
// 2026-10-22 D64.96
//
// 目的:锁死「底栏中间 tab 的提示文案必须 1 行放下」
//
// 起因(user UAT 截图):D64.95 把第 6 段改名「其它资产」时,顺手把底栏中间
// tab 的提示文案也改成了「长按记其它资产」→ **在真机上换行了**
// (「长按记其它资」/「产」两行)。
//
// 为什么:底栏 5 个 tab **平分**屏幕宽度。360dp 屏上每槽只有 ~72dp,
// 而 CJK 汉字在字体里是全角(1em),label 11sp 下 1 个汉字 ≈ 11dp:
//   - 5 字 ≈ 55dp  ✅ 余量充足(「长按记其它」,UAT 已接受)
//   - 6 字 ≈ 66dp  ⚠️ 勉强(「长按·其它资产」当年靠那个窄点才 1 行)
//   - 7 字 ≈ 77dp  ❌ 超出槽宽 → 换行(「长按记其它资产」)
//
// 测试做法:渲染**真实的 MainShell**(不是复刻样式),量中间那条 label
// 的段落高度,跟同一条 bar 上「首页」这种 1 行 label 比 ——
// 高度明显更大就说明换行了。跟 1 行 label 比而不是跟固定像素比,
// 是为了不依赖具体字体(测试环境是 FlutterTest 字体,真机是 OPPO 的中文字体)。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/features/shell/ui/main_shell.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await drift.Migrator(db).createAll();
  });

  tearDown(() async {
    await db.close();
  });

  /// 渲染真实 MainShell,返回 tester
  Future<void> pumpShell(WidgetTester tester, {Size size = const Size(360, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => const MainShell(),
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SizedBox.shrink()),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    // 跟生产 main.dart 结构一致:独立 root ProviderContainer + UncontrolledProviderScope
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
  }

  /// 底栏 5 个 tab 的 label(按 destinations 顺序:首页/流水/中央/报表/我的)
  ///
  /// **按位置取,不按文案取** —— 按文案取的话,一旦文案被改,
  /// 测试会因为"找不到那个字符串"而红,而不是真的量到"换行了"这个 bug,
  /// 回归有效性就打折了。
  List<Text> navLabels(WidgetTester tester) {
    final labels = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byType(Text),
        ))
        .toList();
    expect(labels, hasLength(5), reason: '底栏应有 5 个 tab label');
    return labels;
  }

  /// 取某个 label 的段落高度(像素)
  double labelHeight(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: '找不到 label「$text」');
    final para = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    return para.size.height;
  }

  for (final width in [360.0, 320.0]) {
    testWidgets('D64.96:${width.toInt()}dp 屏上,底栏中间提示必须是 1 行',
        (tester) async {
      await pumpShell(tester, size: Size(width, 800));

      final labels = navLabels(tester);
      final centerText = labels[2].data!;

      // 同一条 bar 上「首页」是确定 1 行的参照物
      final singleLineHeight = labelHeight(tester, '首页');
      final centerHeight = labelHeight(tester, centerText);

      expect(
        centerHeight,
        lessThan(singleLineHeight * 1.5),
        reason: '中间提示「$centerText」换行了(${singleLineHeight.toStringAsFixed(1)}px vs '
            '${centerHeight.toStringAsFixed(1)}px)—— '
            '底栏 5 个 tab 平分宽度,${width.toInt()}dp 屏每槽只有 '
            '${(width / 5).toStringAsFixed(1)}dp,'
            '11sp 下 6 个汉字(66dp)就是上限,7 个字(77dp)必然换行',
      );
    });
  }

  testWidgets('D64.96:中间提示文案长度本身也要守门(≤6 个汉字)', (tester) async {
    await pumpShell(tester);
    final centerText = navLabels(tester)[2].data!;
    // 汉字全角 1em,11sp;槽宽 ~72dp → 最多 6 个汉字
    expect(centerText.length, lessThanOrEqualTo(6),
        reason: '「$centerText」有 ${centerText.length} 个字符,'
            '底栏槽宽只放得下 6 个汉字(11sp × 6 = 66dp < 72dp)');
  });
}
