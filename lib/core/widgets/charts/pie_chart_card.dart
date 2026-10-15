// lib/core/widgets/charts/pie_chart_card.dart
// 2026-10-15 D64.2 加:圆环 + 中心数字 + 右侧图例 通用卡片
//
// 复用 `category_pie.dart` / `expense_by_asset.dart` 同款结构:
//   - 标题栏(标题 + 可选 trailing "共 ¥X")
//   - 140×140 圆环 + 中心"总支出" + "¥X" 数字
//   - 右侧图例列表(色块 10×10 + name + 百分比)
//   - 自动 take(8) 截取前 8 个,跟原 widget 行为一致
//
// 内部用 `AnimatedPieChart`(`core/widgets/animated_pie_chart.dart`)。
// 数据源:业务 widget 把 `List<({String name, double value, int color})>`
// 直接传进来,不需要自己转 PieChartSectionData。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../animated_pie_chart.dart';
import 'chart_card.dart';

/// 圆环 + 图例的单个数据项(业务侧 widget 把数据转成这个)
class PieChartLegendItem {
  const PieChartLegendItem({
    required this.name,
    required this.value,
    required this.color,
  });
  final String name;
  final double value;
  final int color;
}

class PieChartCard extends StatelessWidget {
  const PieChartCard({
    super.key,
    required this.title,
    required this.items,
    required this.total,
    required this.centerLabel,
    required this.centerValueText,
    this.totalLabel,
  });

  /// 卡片标题(左对齐)
  final String title;

  /// 全部数据项(超过 8 个时只显示前 8)
  final List<PieChartLegendItem> items;

  /// 总金额(用于计算百分比)
  final double total;

  /// 中心 label(默认 "总支出")
  final String centerLabel;

  /// 中心数字文本(可格式化的,如 "¥9,609" 或 "¥1.2万")
  final String centerValueText;

  /// 标题右侧文案(可选,如 "共 ¥X" — null 时不显示)
  final String? totalLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ChartCard(
        title: title,
        trailing: totalLabel == null
            ? null
            : Text(
                totalLabel!,
                style: const TextStyle(fontSize: 12, color: AppGray.g600),
              ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
          child: Center(
            child: Text(
              '该时段无数据',
              style: TextStyle(color: AppGray.g600, fontSize: 13),
            ),
          ),
        ),
      );
    }
    final shown = items.take(8).toList();
    return ChartCard(
      title: title,
      trailing: totalLabel == null
          ? null
          : Text(
              totalLabel!,
              style: const TextStyle(fontSize: 12, color: AppGray.g600),
            ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧圆环(140×140)+ 中心文字
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedPieChart(
                    key: pieChartKeyForSections(
                      shown
                          .map(
                            (e) => PieChartSectionData(
                              value: e.value,
                              color: Color(e.color),
                              title: '',
                              radius: 18,
                            ),
                          )
                          .toList(),
                    ),
                    innerRadius: 48,
                    outerRadius: 64,
                    sections: shown
                        .map(
                          (e) => PieChartSectionData(
                            value: e.value,
                            color: Color(e.color),
                            title: '',
                            radius: 18,
                          ),
                        )
                        .toList(),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centerLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppGray.g600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerValueText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            // 右侧图例(最多 8 条)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: shown.map((e) {
                  final pct = total == 0 ? 0 : (e.value / total * 100);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(e.color),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.name,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppGray.g600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 内部工具:从 `List<T>` 转 `List<PieChartLegendItem>`
///
/// 业务 widget 用,避免自己 `.map` 一遍(图表库不依赖具体业务 data class)。
///
/// 用法:
/// ```dart
/// final items = buildPieChartItems<CategoryExpense>(
///   data,
///   nameOf: (e) => e.name,
///   valueOf: (e) => e.amount,
///   colorOf: (e) => e.color,
/// );
/// ```
List<PieChartLegendItem> buildPieChartItems<T>(
  List<T> data, {
  required String Function(T) nameOf,
  required double Function(T) valueOf,
  required int Function(T) colorOf,
}) {
  return [
    for (final d in data)
      PieChartLegendItem(name: nameOf(d), value: valueOf(d), color: colorOf(d)),
  ];
}
