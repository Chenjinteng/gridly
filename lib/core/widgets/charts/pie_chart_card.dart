// lib/core/widgets/charts/pie_chart_card.dart
// 2026-10-15 D64.2 加:圆环 + 中心数字 + 右侧图例 通用卡片
//
// 复用 `category_pie.dart` / `expense_by_asset.dart` 同款结构:
//   - 标题栏(标题 + 可选 trailing "共 ¥X")
//   - 140×140 圆环 + 中心"总支出" + "¥X" 数字
//   - 右侧图例列表(色块 10×10 + name + 百分比)
//   - 自动 take(8) 截取前 8 个,跟原 widget 行为一致
//
// 2026-10-15 D64.7 加 `play` 参数:viewport-aware 触发圆环动画,跟
//   BudgetOverviewChart 同模式。`category_pie` 默认 true(立即播,卡片在
//   stats_page 顶部几乎都可见);`expense_by_asset` 业务 widget 自己控制。
//
// 2026-10-15 D64.12 改:抽出 `PieChartContent` —— 只含 ring + center + legend
//   body,无 ChartCard 包装。给 tabbed 模块(payment_analysis.dart)直接用,
//   避免嵌套 "支出分类" 标题(原 PieChartCard 套 2 层 ChartCard 在
//   SizedBox(height: 220) 内 overflow 28px)。`PieChartCard` 保留作为
//   ChartCard + PieChartContent 的薄壳,向后兼容原调用。
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

/// 2026-10-15 D64.12:圆环 + 中心数字 + 右侧图例的纯 body widget,无卡片包装。
/// 给 tabbed 模块(payment_analysis)直接放进 SizedBox 用,避免嵌套 ChartCard
/// 占 ~50dp title bar 导致 legend overflow。
class PieChartContent extends StatelessWidget {
  const PieChartContent({
    super.key,
    required this.items,
    required this.total,
    required this.centerLabel,
    required this.centerValueText,
    this.play = true,
  });

  /// 全部数据项(超过 8 个时只显示前 8)
  final List<PieChartLegendItem> items;

  /// 总金额(用于计算百分比)
  final double total;

  /// 中心 label(默认 "总支出")
  final String centerLabel;

  /// 中心数字文本(可格式化的,如 "¥9,609" 或 "¥1.2万")
  final String centerValueText;

  /// 是否触发圆环入场动画(viewport-aware 场景)。参考 D64.7。
  final bool play;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
        child: Center(
          child: Text(
            '该时段无数据',
            style: TextStyle(color: AppGray.g600, fontSize: 13),
          ),
        ),
      );
    }
    final shown = items.take(8).toList();
    return Padding(
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
                  play: play,
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
                      style: const TextStyle(fontSize: 11, color: AppGray.g600),
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
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // D64.12:固定宽度 36dp 防止百分比 Text 撑爆 Row 触发右侧
                      //   overflow 9.9px("100%" 4 字 × 7sp ≈ 28dp + 默认 padding)
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${pct.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppGray.g600,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
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
    );
  }
}

/// 带标题 + trailing 的完整卡片(ChartCard + PieChartContent)
///   - 老调用方(category_pie / expense_by_asset / 独立卡片场景)继续用
///   - tabbed 模块(payment_analysis)直接用 PieChartContent 避免嵌套
class PieChartCard extends StatelessWidget {
  const PieChartCard({
    super.key,
    required this.title,
    required this.items,
    required this.total,
    required this.centerLabel,
    required this.centerValueText,
    this.totalLabel,
    this.play = true,
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

  /// 是否触发圆环入场动画(viewport-aware 场景)
  final bool play;

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      title: title,
      trailing: totalLabel == null
          ? null
          : Text(
              totalLabel!,
              style: const TextStyle(fontSize: 12, color: AppGray.g600),
            ),
      child: PieChartContent(
        items: items,
        total: total,
        centerLabel: centerLabel,
        centerValueText: centerValueText,
        play: play,
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
