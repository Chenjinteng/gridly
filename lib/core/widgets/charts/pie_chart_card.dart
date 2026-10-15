// lib/core/widgets/charts/pie_chart_card.dart
// 2026-10-15 D64.2 加:圆环 + 中心数字 + 右侧图例 通用卡片
//
// 复用 `category_pie.dart` / `expense_by_asset.dart` 同款结构:
//   - 标题栏(标题 + 可选 trailing "共 ¥X")
//   - 140×140 圆环 + 中心"总支出" + "¥X" 数字
//   - 右侧图例列表(色块 10×10 + name + 百分比)
//   - 圆环限制 8 段(>8 段薄片难辨认);legend 显示全部并可滚动
//
// 2026-10-15 D64.7 加 `play` 参数:viewport-aware 触发圆环动画,跟
//   BudgetOverviewChart 同模式。`category_pie` 默认 true(立即播,卡片在
//   stats_page 顶部几乎都可见);`expense_by_asset` 业务 widget 自己控制。
//
// 2026-10-15 D64.12 改:抽出 `PieChartContent` —— 只含 ring + center + legend
//   body,无 ChartCard 包装。给 tabbed 模块(expense_analysis.dart)直接用,
//   避免嵌套 "支出分类" 标题(原 PieChartCard 套 2 层 ChartCard 在
//   SizedBox(height: 220) 内 overflow 28px)。`PieChartCard` 保留作为
//   ChartCard + PieChartContent 的薄壳,向后兼容原调用。
//
// 2026-10-15 D64.15 改:legend vertical:3 → 2,name fontSize:13 → 12 紧凑(每项
//   节省 4dp),legend 改成 SingleChildScrollView 支持 >8 项滚动(圆环仍 take(8)
//   视觉清爽)。user UAT 反馈"分类后面一定会很多,如果超过了要做成图例滑动的
//   操作"。固定 SizedBox(height: 168)= 8 紧凑项正好填满,<8 项自然空,<8=
//   不滚,>8 项内部滚。
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
/// 给 tabbed 模块(expense_analysis)直接放进 SizedBox 用,避免嵌套 ChartCard
/// 占 ~50dp title bar 导致 legend overflow。
///
/// D64.15:legend 改成可滚动,>8 项时 user 上滑看全部。
class PieChartContent extends StatelessWidget {
  const PieChartContent({
    super.key,
    required this.items,
    required this.total,
    required this.centerLabel,
    required this.centerValueText,
    this.play = true,
  });

  /// 全部数据项(legend 显示全部,圆环 take(8))
  final List<PieChartLegendItem> items;

  /// 总金额(用于计算百分比)
  final double total;

  /// 中心 label(默认 "总支出")
  final String centerLabel;

  /// 中心数字文本(可格式化的,如 "¥9,609" 或 "¥1.2万")
  final String centerValueText;

  /// 是否触发圆环入场动画(viewport-aware 场景)。参考 D64.7。
  final bool play;

  /// D64.15:圆环固定 8 段(>8 段薄片难辨认,legend 显示全部可滚动看完整数据)
  static const int _ringMaxSections = 8;

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
    final ringShown = items.take(_ringMaxSections).toList();
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
                    ringShown
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
                  sections: ringShown
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
          // 右侧图例:D64.15 可滚动
          //   - SizedBox(height: 168) 固定 = 8 紧凑项(vertical:2 + fontSize:12 = 21dp/项)正好填满
          //   - 8 项内:Column 自然高度 < 168,顶部对齐,下方空白(可接受,<8 时本来就不满)
          //   - 8 项:Column 自然高度 = 168,完美填满
          //   - >8 项:Column 自然高度 > 168,SingleChildScrollView 内部滚动
          Expanded(
            child: SizedBox(
              height: 168,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((e) {
                    final pct = total == 0 ? 0 : (e.value / total * 100);
                    return Padding(
                      // D64.15:vertical: 3 → 2,name fontSize: 13 → 12 紧凑
                      //   节省每项 ~4dp,8 项共 ~32dp
                      padding: const EdgeInsets.symmetric(vertical: 2),
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
                              style: const TextStyle(fontSize: 12),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// 带标题 + trailing 的完整卡片(ChartCard + PieChartContent)
///   - 老调用方(category_pie / expense_by_asset / 独立卡片场景)继续用
///   - tabbed 模块(expense_analysis)直接用 PieChartContent 避免嵌套
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

  /// 全部数据项(legend 显示全部,圆环 take(8),D64.15)
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
