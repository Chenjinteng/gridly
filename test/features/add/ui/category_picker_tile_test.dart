// test/features/add/ui/category_picker_tile_test.dart
// 2026-10-22 D64.97
//
// 目的:锁死「分类名太长时换行完整显示,但小卡片尺寸不变」
//
// 起因(user UAT 截图):分类选择 sheet 里「加餐零食饮料」「咖啡下午茶」
// 「房租水电燃媒」这些长名被 ellipsis 截成「加餐零…」「咖啡下…」「房租水…」,
// 用户要的是**换行**显示完整,而不是截断。
//
// 四个断言:
//   1. 长名**真的排了 2 行**(用 RenderParagraph.getBoxesForSelection 数渲染行数)
//   2. 长名**没被省略号截断**(按 widget 自己的 style/maxLines/overflow 排一遍,
//      didExceedMaxLines == false)
//   3. 1 行的分类和 2 行的分类,**icon 在同一行里 y 坐标一致**
//      (label 区域固定 2 行高 → Column 高度恒定 → 图标不跳)
//   4. 超长名(分类名 schema 上限 16 字)不溢出卡片,卡片比例 0.85 不变
//
// **测量的坑(自己踩过)**:
//   - label 区域是 SizedBox(height: 2 行) → **高度是 tight 的** →
//     RenderParagraph.size.height 恒等于盒高(2 行名和 1 行名一样),
//     **量高度量不出行数**,必须用 getBoxesForSelection 数渲染出来的行盒
//   - 第一版用「自己另排一遍 TextPainter」来测 → 那个 TextPainter 写死了
//     maxLines: 2,widget 改成 1 行测试照样绿 → **回归有效性为零**
//     (跟 D64.96 同一个坑:测试要量真实渲染,不能量自己的复刻)
//
// 网格参数跟 picker 生产代码一致(4 列 / spacing 8 / padding 16 / 比例 0.85),
// 比例 0.85 就是**卡片尺寸**本身 —— 断言"卡片大小不变"就是断言它没被动过。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/theme/app_spacing.dart';
import 'package:gridly/features/add/ui/widgets/category_picker_tile.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Category> insertCat(String name, {int sortOrder = 0}) async {
    final id = await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        icon: 'more_horiz',
        color: 0xFFA1A1AA,
        type: 'expense',
        isSystem: const Value(false),
        sortOrder: Value(sortOrder),
      ),
    );
    return await (db.select(db.categories)..where((c) => c.id.equals(id)))
        .getSingle();
  }

  /// 按 picker 生产参数铺一个 4 列网格
  Future<void> pumpGrid(WidgetTester tester, List<Category> cats) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.s4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: AppSpacing.s2,
              crossAxisSpacing: AppSpacing.s2,
              childAspectRatio: 0.85,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) => CategoryPickerTile(
              category: cats[i],
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderParagraph paragraphOf(WidgetTester tester, String text) {
    return tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
  }

  /// **真实渲染出来的**行数(一个行盒 = 一行)
  ///
  /// 不能用 para.size.height —— label 区域是固定高度的 SizedBox,
  /// 高度 tight,1 行名和 2 行名的段落高度一样,量不出来。
  int renderedLines(WidgetTester tester, String text) {
    return paragraphOf(tester, text)
        .getBoxesForSelection(TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        ))
        .length;
  }

  /// tile 内 label 的可用宽度(tile 宽 - 左右 padding)
  double labelWidth(WidgetTester tester) {
    final size = tester.getSize(find.byType(CategoryPickerTile).first);
    return size.width - AppSpacing.s2 * 2;
  }

  /// 按 **widget 自己的** style / maxLines / overflow 排一遍,看有没有被省略号截断
  ///
  /// 属性全部从树上的 Text 读 —— 写死 maxLines 的话,
  /// widget 改了行数这个检查就测不到(第一版的坑)。
  bool truncatedLikeWidget(WidgetTester tester, String text, double maxWidth) {
    final t = tester.widget<Text>(find.text(text));
    final tp = TextPainter(
      text: t.textSpan ?? TextSpan(text: text),
      textAlign: t.textAlign ?? TextAlign.center,
      textDirection: t.textDirection ?? TextDirection.ltr,
      strutStyle: t.strutStyle,
      maxLines: t.maxLines,
      ellipsis: t.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: t.locale,
    )..layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
  }

  testWidgets('D64.97:长分类名换行完整显示,不被省略号截断', (tester) async {
    // 用户真机上真实出现过的长名
    final cats = [
      await insertCat('交通', sortOrder: 0),
      await insertCat('加餐零食饮料', sortOrder: 1),
      await insertCat('咖啡下午茶', sortOrder: 2),
      await insertCat('房租水电燃媒', sortOrder: 3),
      await insertCat('爱好-胶片摄影', sortOrder: 4),
    ];
    await pumpGrid(tester, cats);

    final width = labelWidth(tester);

    // 断言 1:短名 1 行,长名**真的渲染成 2 行**
    expect(renderedLines(tester, '交通'), 1);
    for (final c in cats.skip(1)) {
      expect(renderedLines(tester, c.name), 2,
          reason: '「${c.name}」没排成 2 行 —— 还是被 maxLines=1 截了');
    }

    // 断言 2:widget 允许 2 行
    for (final c in cats) {
      expect(tester.widget<Text>(find.text(c.name)).maxLines, 2,
          reason: '「${c.name}」的 maxLines 不是 2');
    }

    // 断言 3:2 行放得下完整名字(没被省略号截断)
    for (final c in cats) {
      expect(truncatedLikeWidget(tester, c.name, width), isFalse,
          reason: '「${c.name}」在 ${width.toStringAsFixed(1)}px 宽里 '
              '2 行放不下,会被省略号截断');
    }

    expect(tester.takeException(), isNull, reason: '有溢出异常');
  });

  testWidgets('D64.97:1 行和 2 行的分类,icon 在同一行里 y 坐标一致',
      (tester) async {
    final cats = [
      await insertCat('交通', sortOrder: 0),
      await insertCat('加餐零食饮料', sortOrder: 1),
      await insertCat('超市购物', sortOrder: 2),
      await insertCat('房租水电燃媒', sortOrder: 3),
    ];
    await pumpGrid(tester, cats);

    final icons = find.descendant(
      of: find.byType(CategoryPickerTile),
      matching: find.byType(Icon),
    );
    expect(icons, findsNWidgets(4));

    final tops = <double>[];
    for (var i = 0; i < 4; i++) {
      tops.add(tester.getTopLeft(icons.at(i)).dy);
    }
    // 同一行内(前 4 个 = 第 1 行)icon 的 y 应该完全一致
    final maxDelta = tops
        .map((t) => (t - tops.first).abs())
        .reduce((a, b) => a > b ? a : b);
    expect(maxDelta, lessThan(0.01),
        reason: '同一行里 icon 的 y 不一致(差 ${maxDelta.toStringAsFixed(2)}px)'
            ' —— label 区域必须固定 2 行高,否则 1 行和 2 行的分类会把 icon 顶得高低不齐');
  });

  testWidgets('D64.97:卡片尺寸不变(比例 0.85),超长名也不溢出', (tester) async {
    final cats = [
      await insertCat('交通', sortOrder: 0),
      await insertCat('爱好-胶片摄影', sortOrder: 1),
      // 分类名 schema 上限 16 字 —— 超长时 ellipsis 兜底,不能撑破卡片
      await insertCat('一二三四五六七八九十', sortOrder: 2),
    ];
    await pumpGrid(tester, cats);

    final tile = tester.getSize(find.byType(CategoryPickerTile).first);
    // 比例 0.85 = 宽 / 高 → 高 = 宽 / 0.85
    expect(tile.height, closeTo(tile.width / 0.85, 0.5),
        reason: '卡片比例被改了 —— 卡片尺寸必须跟改动前一致');

    expect(tester.takeException(), isNull, reason: '有溢出异常');
  });
}
