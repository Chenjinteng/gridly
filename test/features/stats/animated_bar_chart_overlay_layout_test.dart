// test/features/stats/animated_bar_chart_overlay_layout_test.dart
// 2026-10-20 D64.73
//
// 目的:守住触摸 overlay(顶部 label + 金额 tooltip)的排版 ——
//   1) 靠右的柱子,touch 后 tooltip / 顶部 label 会横向溢出 chart,
//      被外层 ChartCard 的边界切掉(user 实测截图:每日 tab 右下角
//      tooltip 只剩半个 "31" 和 "¥0.0")
//   2) 顶部 label 固定 56px 宽,装不下长中文分类名("房租水电燃媒" 6 字)
//      → 换行成 2 行(高 ≈ 60px),而 tooltip 从 top: 28 开始 → 两者垂直重叠
//      (user 实测截图:类别 tab 上两个框叠在一起)
//
// 测法:取 overlay 的 RenderBox,用 localToGlobal 取 4 个角算 AABB,
//   跟 chart 的 AABB 比边界、两个 overlay 之间比相交。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gridly/core/widgets/charts/animated_bar_chart.dart';

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

/// 真机 ChartCard 内容宽:360 - 2×16(margin) - 2×16(padding) = 296
const realChartWidth = 296.0;

/// touch chart 靠右的柱(最右一根)
///
/// fl_chart 内部对长按有 500ms 的 pending timer,必须在测试体结束前
/// 把它 pump 走,否则 flutter_test 报 "A Timer is still pending"。
Future<TestGesture> _touchRightmostBar(WidgetTester tester) async {
  final chartRect = tester.getRect(find.byType(AnimatedBarChart));
  final gesture = await tester.startGesture(
    Offset(chartRect.right - 5, chartRect.center.dy),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return gesture;
}

void main() {
  group('D64.73 触摸 overlay 布局', () {
    testWidgets('靠右的柱:tooltip 不横向溢出 chart', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [
                    for (var i = 0; i < 9; i++)
                      BarChartBar(label: '分类$i', value: 100.0 - i * 10),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  barWidth: 8,
                  touchedLabelBuilder: (i, b) => b.label,
                  tooltipBuilder: (i, b) => '¥${b.value}',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await _touchRightmostBar(tester);
      addTearDown(gesture.up);

      final chartRect = tester.getRect(find.byType(AnimatedBarChart));
      final tooltipRect = _aabbOf(tester, find.byKey(const Key('chart-tooltip')));
      // ignore: avoid_print
      print('chart=$chartRect  tooltip=$tooltipRect');
      expect(
        tooltipRect.right,
        lessThanOrEqualTo(chartRect.right + 0.5),
        reason: 'tooltip 横向溢出 chart 右边界: $tooltipRect vs $chartRect',
      );
    });

    testWidgets('靠右的柱:顶部 label 不横向溢出 chart', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: [
                    for (var i = 0; i < 9; i++)
                      BarChartBar(label: '分类$i', value: 100.0 - i * 10),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  barWidth: 8,
                  touchedLabelBuilder: (i, b) => b.label,
                  tooltipBuilder: (i, b) => '¥${b.value}',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await _touchRightmostBar(tester);
      addTearDown(gesture.up);

      final chartRect = tester.getRect(find.byType(AnimatedBarChart));
      final labelRect =
          _aabbOf(tester, find.byKey(const Key('chart-touched-label')));
      // ignore: avoid_print
      print('chart=$chartRect  label=$labelRect');
      expect(
        labelRect.right,
        lessThanOrEqualTo(chartRect.right + 0.5),
        reason: '顶部 label 横向溢出 chart 右边界: $labelRect vs $chartRect',
      );
    });

    testWidgets('长中文分类名:顶部 label 与 tooltip 不垂直重叠', (tester) async {
      // user 截图里的分类名 + 每日 tab 那种短 label 两档都测
      for (final label in ['房租水电燃媒', '31日']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: realChartWidth,
                  height: 300,
                  child: AnimatedBarChart(
                    bars: [
                      for (var i = 0; i < 6; i++)
                        BarChartBar(
                          label: i == 2 ? label : '分类$i',
                          value: 100.0 - i * 10,
                        ),
                    ],
                    maxVal: 100,
                    chartNeedsWan: false,
                    barWidth: 8,
                    touchedLabelBuilder: (i, b) => b.label,
                    tooltipBuilder: (i, b) =>
                        '${b.label}\n¥${b.value.toStringAsFixed(2)}',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // touch 中间那根(分类名长的那根)
        final chartRect = tester.getRect(find.byType(AnimatedBarChart));
        final gesture = await tester.startGesture(
          Offset(chartRect.left + realChartWidth * 0.45, chartRect.center.dy),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        addTearDown(gesture.up);

        final labelRect =
            _aabbOf(tester, find.byKey(const Key('chart-touched-label')));
        final tooltipRect =
            _aabbOf(tester, find.byKey(const Key('chart-tooltip')));
        // ignore: avoid_print
        print('"$label" label=$labelRect  tooltip=$tooltipRect');
        expect(
          labelRect.overlaps(tooltipRect),
          isFalse,
          reason: '顶部 label 与 tooltip 重叠("$label"): '
              '$labelRect vs $tooltipRect',
        );
      }
    });

    testWidgets('showTouchedLabel=false:只渲染 tooltip 一个浮层', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: realChartWidth,
                height: 300,
                child: AnimatedBarChart(
                  bars: const [
                    BarChartBar(label: '房租水电燃媒', value: 100),
                    BarChartBar(label: '正餐支出', value: 50),
                  ],
                  maxVal: 100,
                  chartNeedsWan: false,
                  barWidth: 8,
                  showTouchedLabel: false,
                  touchedLabelBuilder: (i, b) => b.label,
                  tooltipBuilder: (i, b) => '${b.label}\n¥${b.value}',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await _touchRightmostBar(tester);
      addTearDown(gesture.up);

      expect(find.byKey(const Key('chart-touched-label')), findsNothing);
      expect(find.byKey(const Key('chart-tooltip')), findsOneWidget);
    });
  });
}
