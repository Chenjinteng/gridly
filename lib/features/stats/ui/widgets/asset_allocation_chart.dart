// lib/features/stats/ui/widgets/asset_allocation_chart.dart
// 报表"资产"视角 dashboard —— 资产配置分布环形图
//
// 2026-10-16 D64.62 加(user UAT 反馈):
//   - user 反馈"增加一个环形图,叫资产配置分布,是把所有资产账号统计起来
//     作比例,不含借入的债务,但包含借出的债务"
//   - 6 段比例:
//     cash_flow / investment / benefit / receivable_lend / fixed_asset / other
//     - 借出 receivable (isLender=true) 计入 receivable_lend 维度
//       颜色用 AppSegment.receivable(橙 0xFFF59E0B)
//     - 借入 receivable (isLender=false) **不计入**(在 LiabilitiesDashboard 独立显示警示)
//   - 复用 ExpenseAnalysis 风格:fl_chart PieChartContent(圆环 + 中心数字 +
//     右侧图例),跟报表其它图表视觉一致
//
// 跟 AssetsRadar 的口径对比:
//   - AssetsRadar:5 维真资产占比(cash_flow / investment / benefit / fixed_asset / other),
//     **不含 receivable 段任何账户**
//   - AssetAllocationChart:6 维(比 radar 多 1 维 "receivable_lend"),
//     把借出 receivable 算作资产侧的"债权"维度
//   - 2 张图并存,提供不同视角:
//     - radar 看"5 段真资产内部"占比(无外部债权)
//     - allocation 看"全部 6 段资产"占比(包含我应收的债权)
//
// 数据源:
//   - allAssetsProvider(全部账户)
//   - assetBalancesProvider(Map<assetId, currentBalance>)
//   - 算 byType 累加,receivable 段只累加 isLender=true 的 balance
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';

/// 报表"资产配置分布"环形图 dashboard
///   - 6 段比例(cash_flow / investment / benefit / receivable_lend / fixed_asset / other)
///   - 借出 receivable 计入,借入 receivable 不计入
class AssetAllocationChart extends ConsumerWidget {
  const AssetAllocationChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // 累加各段余额(同 LiabilitiesDashboard byType 模式)
    final byType = <String, double>{
      'cash_flow': 0.0,
      'investment': 0.0,
      'benefit': 0.0,
      'fixed_asset': 0.0,
      'other': 0.0,
    };
    // receivable_lend 单独算 isLender=true 的累加(借入 receivable 不算)
    double receivableLend = 0.0;

    for (final a in assets) {
      final bal = balances[a.id] ?? 0.0;
      if (a.type == 'receivable') {
        if (a.isLender && bal > 0) {
          receivableLend += bal;
        }
        // 借入(isLender=false)跳过,不进任何累加
      } else if (byType.containsKey(a.type)) {
        byType[a.type] = (byType[a.type] ?? 0.0) + bal;
      }
    }

    // 6 段 legend 数据(>0 才显示,空段不画)
    // - 颜色走 AppSegment 集中数据源(跟其它 dashboard / 报表 6 段色一致)
    // - 顺序:现金 / 投资 / 福利 / 借出 / 不动产 / 其它(按段位顺序,跟
    //   AssetSummaryCard _segmentOrder 一致,只把 receivable_lend 插在
    //   benefit 后 / fixed_asset 前)
    final items = <_AllocationItem>[];
    void addIfPositive(String key, String label, String type) {
      final v = key == 'receivable_lend' ? receivableLend : (byType[key] ?? 0);
      if (v > 0) {
        items.add(_AllocationItem(
          name: label,
          value: v,
          color: _colorFor(type),
        ));
      }
    }

    addIfPositive('cash_flow', '流动资金', 'cash_flow');
    addIfPositive('investment', '投资', 'investment');
    addIfPositive('benefit', '福利', 'benefit');
    addIfPositive('receivable_lend', '债权', 'receivable'); // 借用 receivable 段色
    addIfPositive('fixed_asset', '不动产', 'fixed_asset');
    addIfPositive('other', '其它', 'other');

    // 按 value 降序(占比大的在前面),跟 ExpenseAnalysis 同款排序
    items.sort((a, b) => b.value.compareTo(a.value));

    final total = items.fold<double>(0, (s, e) => s + e.value);

    return ChartCard(
      title: '资产配置分布',
      showDivider: true,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s5),
              child: Center(
                child: Text(
                  '当前无资产',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          : Padding(
              // D64.12:PieChartContent 是纯 body widget,自己 padding 控制边距;
              // 这里跟 ExpenseAnalysis 同款给 AppSpacing.s4(其它字段已包在 ChartCard 里)
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 左侧圆环(140×140)+ 中心数字
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 复用 AnimatedPieChart 直接渲染(不走 PieChartContent,
                        // 因为 PieChartContent 中心数字用 Text widget 静态,
                        // 我们想要 AnimatedCounter 数字滚动 — D64.62 数字动画要求)
                        _AllocationPieRing(items: items),
                        // 中心:总资产大字 + 标签(D64.62 加 AnimatedCounter)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '总资产',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedCounter(
                                value: total,
                                prefix: '¥',
                                formatter: (v) => Formatters.amount(v),
                                duration: const Duration(milliseconds: 480),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  // 右侧图例(垂直列表,6 段)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.s1),
                          _AllocationLegendRow(
                            name: items[i].name,
                            color: items[i].color,
                            percent: total > 0
                                ? (items[i].value / total)
                                : 0,
                            value: items[i].value,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 6 段色 token(D64.62:走 AppSegment 集中数据源,跟 AssetSummaryCard /
  /// 报表其它卡片色一致)
  Color _colorFor(String type) {
    switch (type) {
      case 'cash_flow':
        return AppSegment.cashFlow;
      case 'investment':
        return AppSegment.investment;
      case 'benefit':
        return AppSegment.benefit;
      case 'receivable':
        return AppSegment.receivable; // 借出 receivable_lend 借用 receivable 段色
      case 'fixed_asset':
        return AppSegment.fixedAsset;
      default:
        return AppSegment.other;
    }
  }
}

/// 单段数据
class _AllocationItem {
  const _AllocationItem({
    required this.name,
    required this.value,
    required this.color,
  });
  final String name;
  final double value;
  final Color color;
}

/// 图例行:小色块 + 名称 + 占比 + 金额
class _AllocationLegendRow extends StatelessWidget {
  const _AllocationLegendRow({
    required this.name,
    required this.color,
    required this.percent,
    required this.value,
  });

  final String name;
  final Color color;
  final double percent;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // 小色块(8x8 圆角 2)
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 名称(限宽)
        SizedBox(
          width: 48,
          child: Text(
            name,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 占比 + 金额(右对齐)
        Expanded(
          child: Text(
            '${(percent * 100).toStringAsFixed(0)}% ¥${Formatters.amount(value)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// 左侧圆环:6 段 fl_chart PieChart
///   - 不走 PieChartContent(它中心数字是 Text 静态),自己组装 Stack 让中心
///     数字走 AnimatedCounter
///   - AnimatedPieChart 接 `List<PieChartSectionData>`(fl_chart 类型),
///     不是 PieChartLegendItem,这里手动 map 转换
class _AllocationPieRing extends StatelessWidget {
  const _AllocationPieRing({required this.items});

  final List<_AllocationItem> items;

  @override
  Widget build(BuildContext context) {
    // 转成 PieChartSectionData(fl_chart 类型)
    final sections = [
      for (final i in items)
        PieChartSectionData(
          value: i.value,
          color: i.color,
          title: '',
          radius: 18,
        ),
    ];
    return AnimatedPieChart(sections: sections);
  }
}