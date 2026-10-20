// test/features/stats/animated_bar_chart_slanted_labels_test.dart
// 2026-10-20 D64.72
//
// 目的:守住"消费趋势 类别 tab"的 X 轴 label 排版 —— 9 个中文分类名
// (给家里/房租/水电燃气/会员咖啡…)在手机宽度下横排必然重叠。
//
// 背景(实测数据,真机 ChartCard 内容宽 ≈ 296dp,9 分类平均 28dp/个):
//   45° 斜排 + 10sp → 5 对重叠 / +9sp → 3 对 / +8sp → 1 对(都放不下)
//   55°/60° + 8sp   → 0 对(但字太小)
//   70° + 9sp       → 0 对(但字符被转 70°,读要歪头)
//   中文竖排 + 9sp  → 0 对,字最清楚 ← user 选定(D64.72)
//
// 测法:取每个 label 的 RenderBox,用 localToGlobal 取 4 个角算轴对齐包围盒
// (AABB),两两比较是否相交。
// 注意:Transform.rotate 是 RenderTransform,会 applyPaintTransform 到子节点,
// 所以 localToGlobal 取到的是旋转后的真实坐标。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gridly/core/widgets/charts/animated_bar_chart.dart';
import 'package:gridly/core/widgets/charts/vertical_bar_label.dart';

/// 取 widget 变换后的轴对齐包围盒(全局坐标)
Rect _aabbOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final topLeft = box.localToGlobal(Offset.zero);
  final topRight = box.localToGlobal(Offset(box.size.width, 0));
  final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
  final bottomRight =
      box.localToGlobal(Offset(box.size.width, box.size.height));
  return Rect.fromPoints(topLeft, topRight)
      .expandToInclude(Rect.fromPoints(bottomLeft, bottomRight));
}

/// 统计 rects 两两重叠的对数
int _countOverlaps(Map<String, Rect> rects) {
  final names = rects.keys.toList();
  var overlaps = 0;
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      if (rects[names[i]]!.overlaps(rects[names[j]]!)) {
        overlaps++;
        // ignore: avoid_print
        print('❌ 重叠: "${names[i]}" vs "${names[j]}"');
      }
    }
  }
  return overlaps;
}

void main() {
  // 模拟 user 截图里的 9 个分类名(4 字 / 3 字 / 2 字混合)
  const labels = [
    '给家里',
    '房租',
    '水电燃气',
    '餐饮',
    '支出',
    '银行卡',
    '会员咖啡',
    '下午茶',
    '交通',
  ];

  /// 真机 ChartCard 内容宽:360 - 2×16(margin) - 2×16(padding) = 296
  const realChartWidth = 296.0;

  group('D64.72 消费趋势 类别 tab X 轴 label', () {
    testWidgets('中文竖排(交付方案):9 个长分类名两两不重叠', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [
                    for (var i = 0; i < labels.length; i++)
                      BarChartBar(label: labels[i], value: 100.0 - i * 10),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  xLabelReservedSize: 64,
                  xLabelBuilder: (i, b) => VerticalBarLabel(b.label),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rects = <String, Rect>{};
      for (var i = 0; i < labels.length; i++) {
        rects[labels[i]] = _aabbOf(tester, find.byType(VerticalBarLabel).at(i));
      }
      expect(_countOverlaps(rects), 0, reason: '竖排后 label 仍有重叠');
    });

    testWidgets('中文竖排:label 不越出 chart 底部(不被切)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [
                    for (var i = 0; i < labels.length; i++)
                      BarChartBar(label: labels[i], value: 100.0 - i * 10),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  xLabelReservedSize: 64,
                  xLabelBuilder: (i, b) => VerticalBarLabel(b.label),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chartRect = tester.getRect(find.byType(AnimatedBarChart));
      for (var i = 0; i < labels.length; i++) {
        final r = _aabbOf(tester, find.byType(VerticalBarLabel).at(i));
        expect(
          r.bottom,
          lessThanOrEqualTo(chartRect.bottom + 0.5),
          reason: '竖排 label "${labels[i]}" 超出 chart 底部: $r vs $chartRect',
        );
      }
    });

    testWidgets('中文竖排:超长分类名(>7 字)截断不溢出', (tester) async {
      const longLabel = '一二三四五六七八九';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [const BarChartBar(label: longLabel, value: 100)],
                  maxVal: 100,
                  chartNeedsWan: false,
                  xLabelReservedSize: 64,
                  xLabelBuilder: (i, b) => VerticalBarLabel(b.label),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final r = _aabbOf(tester, find.byType(VerticalBarLabel));
      final chartRect = tester.getRect(find.byType(AnimatedBarChart));
      expect(r.bottom, lessThanOrEqualTo(chartRect.bottom + 0.5),
          reason: '超长 label 截断后仍溢出: $r vs $chartRect');
      // 截断后应显示 6 字 + 省略号 = 7 行
      expect(find.byType(VerticalBarLabel), findsOneWidget);
    });

    testWidgets('水平排(默认 xLabelAngle=0)短 label 不回归', (tester) async {
      // 每日/周几 tab 的短 label("1日"/"一")走水平路径
      const shortLabels = ['1日', '2日', '3日', '4日', '5日', '6日', '7日'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [
                    for (var i = 0; i < shortLabels.length; i++)
                      BarChartBar(label: shortLabels[i], value: 100.0 - i * 10),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  xLabelBuilder: (i, b) => Text(
                    b.label,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rects = <String, Rect>{};
      for (final l in shortLabels) {
        rects[l] = _aabbOf(tester, find.text(l));
      }
      expect(_countOverlaps(rects), 0, reason: '水平排短 label 也重叠了');
    });

    testWidgets('斜排参数扫描(数据记录,不断言重叠数)', (tester) async {
      // 记录各 (角度, 字号) 在真机宽度下的重叠情况,便于后续调参参考。
      // 结论见文件头注释:45° 在此宽度下无论多大字都放不下 → 走中文竖排。
      final results = <String, int>{};
      for (final angleDeg in [45.0, 55.0, 60.0, 70.0]) {
        for (final fs in [10.0, 9.0, 8.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: realChartWidth,
                    height: 300,
                    child: AnimatedBarChart(
                      bars: [
                        for (var i = 0; i < labels.length; i++)
                          BarChartBar(label: labels[i], value: 100.0 - i * 10),
                      ],
                      maxVal: 100,
                      chartNeedsWan: false,
                      xLabelAngle: -angleDeg * math.pi / 180,
                      xLabelBuilder: (i, b) => Text(
                        b.label,
                        style: TextStyle(fontSize: fs),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final rects = <String, Rect>{};
          for (final l in labels) {
            rects[l] = _aabbOf(tester, find.text(l));
          }
          final n = _countOverlaps(rects);
          results['${angleDeg.toStringAsFixed(0)}°/$fs'] = n;
          // ignore: avoid_print
          print('SCAN ${angleDeg.toStringAsFixed(0)}° fs=$fs → 重叠 $n 对');
        }
      }
      expect(results, isNotEmpty);
    });
  });
}
