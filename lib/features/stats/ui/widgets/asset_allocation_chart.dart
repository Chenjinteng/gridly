// lib/features/stats/ui/widgets/asset_allocation_chart.dart
// 报表"资产"视角 dashboard —— 资产配置分布环形图
//
// 2026-10-16 D64.62 加(user UAT 反馈):
//   - user 反馈"增加一个环形图,叫资产配置分布,是把所有资产账号统计起来
//     作比例,不含借入的债务,但包含借出的债务"
//
// 2026-10-16 D64.63 重写(user UAT 反馈):
//   - user 反馈"你理解错了,不是把 5 类的资产做成环形,而是把现金,银行卡,
//     微信支付,余额宝等等,这些子类来进行画环形"
//   - 我之前 D64.62 按"6 段类型"(cash_flow / investment / benefit / ...)
//     做环形,user 想要按"每个具体账户"(现金/银行卡/微信支付/余额宝 ...)
//     做环形 — 资产级而非段位级
//   - 修法:
//     ① 数据源改全 6 段账户:`assets.where((a) => balance > 0)` 逐账户
//       - 借出 receivable (isLender=true,balance > 0)自动包含
//       - 借入 receivable (isLender=false,balance < 0)不计入(负债卡独立)
//     ② 每段颜色用 `Color(a.color)`(账户色,跟资产页 tile 同款),不是段色
//     ③ 图例只显示"色块 + 名称 + 占比 %",**不显示金额**
//       (user 反馈"图例不需要写具体的金额" — 数字信息在中心"总资产"大字
//       已经表达,legend 只看占比比例即可,避免冗余)
//     ④ 环形图 ringMaxSections = 8 限制(账户 >8 时圆环只显示前 8,
//       legend 显示全部可滚动;同 PieChartContent 同款策略)
//     ⑤ stats_page 顺序调整:负债 → 借出 → 雷达图 → **资产配置分布**
//       (user 反馈"放在雷达图下面",从原来"雷达图前"挪到"雷达图后")
//
// 数据源:
//   - allAssetsProvider(全部账户,逐账户独立 1 段)
//   - assetBalancesProvider(Map<assetId, currentBalance>)
//   - filter:`bal > 0`(负余额账户如花呗/借出 balance=0 不计入,
//     在 LiabilitiesDashboard 独立显示)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';

/// 报表"资产配置分布"环形图 dashboard
///   - 每个具体账户 1 段(不是 6 段类型)
///   - 借出 receivable 计入,借入 receivable 不计入
class AssetAllocationChart extends ConsumerWidget {
  const AssetAllocationChart({super.key});

  /// 圆环最大扇区数(>8 时圆环只显示前 8,legend 显示全部可滚动,
  /// 跟 PieChartContent._ringMaxSections 同款策略)
  static const int _ringMaxSections = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // D64.63:逐账户生成 items(账户级而非段位级)
    //   - bal > 0 才计入(负余额 = 债务,在负债卡显示)
    //   - name 用账户 name,color 用账户 Color(a.color)
    //   - 借出 receivable (isLender=true,bal > 0)自动包含(借出账户余额为正)
    //   - 借入 receivable (isLender=false,bal < 0)自动排除
    final items = <_AllocationItem>[];
    for (final a in assets) {
      final bal = balances[a.id] ?? 0.0;
      if (bal > 0) {
        items.add(_AllocationItem(
          name: a.name,
          value: bal,
          color: Color(a.color),
        ));
      }
    }
    // 按 value 降序(占比大的在前面),跟 ExpenseAnalysis 同款排序
    items.sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold<double>(0, (s, e) => s + e.value);
    final ringShown = items.take(_ringMaxSections).toList();

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
              // 跟 ExpenseAnalysis 同款 AppSpacing.s4 padding
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
                        // 复用 AnimatedPieChart 渲染圆环(只画 ringMaxSections 段)
                        _AllocationPieRing(items: ringShown),
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
                  // 右侧图例(D64.63:只显示占比 %,不显示金额)
                  //   - 高度限制 168(同 PieChartContent,D64.15 可滚动策略)
                  //   - 账户 >8 时 Column 自然高度 > 168,内部滚动
                  Expanded(
                    child: SizedBox(
                      height: 168,
                      child: SingleChildScrollView(
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
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 单账户数据
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

/// 图例行:小色块 + 名称 + 占比 %(D64.63 删金额字段)
class _AllocationLegendRow extends StatelessWidget {
  const _AllocationLegendRow({
    required this.name,
    required this.color,
    required this.percent,
  });

  final String name;
  final Color color;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // 小色块(10x10 圆角 2,跟 ExpenseAnalysis 同款)
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 名称(限宽,可省略)
        Expanded(
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
        // 占比 % (右对齐,D64.63:不再显示金额)
        Text(
          '${(percent * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// 左侧圆环:账户级 fl_chart PieChart
///   - 不走 PieChartContent(它中心数字是 Text 静态),自己组装 Stack 让中心
///     数字走 AnimatedCounter
///   - AnimatedPieChart 接 `List<PieChartSectionData>`(fl_chart 类型),
///     这里手动 map 转换
class _AllocationPieRing extends StatelessWidget {
  const _AllocationPieRing({required this.items});

  final List<_AllocationItem> items;

  @override
  Widget build(BuildContext context) {
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