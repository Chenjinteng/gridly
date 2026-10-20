// test/features/add/ui/type_toggle_color_test.dart
// 2026-10-20 D64.76
//
// 目的:锁死"记一笔 toggle 的收入 / 支出恒定绿 / 红",不再跟 palette 走。
//
// 背景(user 反馈):
//   "你说的那个问题,新增流水表单的收入支出也统一"
//   —— toggle 段色 vs 同屏 AmountDisplay 大数字,在 4 个主题里有 3 个对不上:
//      默认深色:toggle 浅青 #A7F3E0 ≠ 大数字 #14B8A6
//      粉红浅色:toggle 深粉 #E84B7F ≠ 绿
//      粉红深色:toggle 亮粉 #FF5C8A ≠ 绿
//
// 改法:_mapSegmentColor 不再把 teal(收入)映射成 scheme.primary。
//   收支语义色恒定;投资段(gold)和调拨(softGold)是品牌强调色,继续跟 palette。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/theme/app_colors.dart';
import 'package:gridly/core/theme/app_theme.dart';
import 'package:gridly/core/theme/gridly_palette.dart';
import 'package:gridly/features/add/ui/widgets/type_toggle.dart';

final Map<String, ThemeData> _themes = {
  '默认浅色': AppTheme.light(),
  '默认深色': AppTheme.dark(),
  '粉红浅色': AppTheme.pinkLight(),
  '粉红深色': AppTheme.darkWithPalette(GridlyPalette.darkPink),
};

void main() {
  /// 取 toggle 里某个 label 的**生效**文字色
  /// (_Segment 用 AnimatedDefaultTextStyle 承载,Text 自己的 style 是 null)
  Color toggleLabelColor(WidgetTester tester, String label) {
    final ads = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    );
    return ads.style.color!;
  }

  group('记一笔 toggle · 收支段色恒定', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:收入绿 / 支出红', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: TypeToggle(
                value: 'income',
                onChanged: (_) {},
                segments: TypeToggle.cashFlowSegments,
              ),
            ),
          ),
        );
        await tester.pump();

        // 选中段('收入')用段语义色
        expect(toggleLabelColor(tester, '收入'), AppSemantic.income);
        // 未选中段('支出')是灰 —— 选中时才用语义色
        // 切到支出验证支出色
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: TypeToggle(
                value: 'expense',
                onChanged: (_) {},
                segments: TypeToggle.cashFlowSegments,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(toggleLabelColor(tester, '支出'), AppSemantic.expense);
      });
    }
  });

  group('记一笔 toggle · 粉红主题不回退成粉', () {
    for (final name in ['粉红浅色', '粉红深色']) {
      testWidgets('$name:收入段 ≠ 粉色系', (tester) async {
        final theme = _themes[name]!;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: TypeToggle(
                value: 'income',
                onChanged: (_) {},
                segments: TypeToggle.cashFlowSegments,
              ),
            ),
          ),
        );
        await tester.pump();

        final c = toggleLabelColor(tester, '收入');
        expect(c, AppSemantic.income);
        expect(c, isNot(AppPinkBrand.gold)); // 亮粉 #FF5C8A
        expect(c, isNot(AppPinkBrand.teal)); // 深粉 #E84B7F
        expect(c, isNot(theme.colorScheme.primary));
        expect(c, isNot(theme.colorScheme.secondary));
      });
    }
  });

  group('记一笔 toggle · 投资段仍跟 palette', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}:投入 = secondary(品牌强调色)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: TypeToggle(
                value: 'input',
                onChanged: (_) {},
                segments: TypeToggle.investmentSegments,
              ),
            ),
          ),
        );
        await tester.pump();

        // 投资段是品牌强调色(gold),继续跟 palette 走 —— 不属于收支语义色
        expect(
          toggleLabelColor(tester, '投入'),
          entry.value.colorScheme.secondary,
        );
      });
    }
  });

  group('记一笔 toggle · 债务段语义色不变', () {
    test('借出橙 / 借入红(D51 决策,不套普通收支绿红)', () {
      final byKey = {
        for (final s in TypeToggle.receivableSegments) s.key: s.color,
      };
      expect(byKey['lend_out'], AppSegment.receivable);
      expect(byKey['borrow_in'], AppStatus.error);
    });
  });
}
