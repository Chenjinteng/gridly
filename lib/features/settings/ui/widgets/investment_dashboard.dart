// lib/features/settings/ui/widgets/investment_dashboard.dart
// 资产页"投资情况"dashboard — 累计净收益 + 本年 12 月双柱
//
// 2026-10-16 D64.68 加(user UAT 反馈):
//   - user 反馈"资产页面开始增加投资的投入和收益情况的图,你看看是图表好"
//   - 选定方案:汇总卡 + 双柱(完整 dashboard)
//     ① 顶部"累计净收益"label + 大字 AnimatedCounter 滚动
//     ② 末尾小字"全时间" / "本年投入 ¥X / 收益 ¥Y"
//     ③ 12 月双柱(left 投入 red,right 收益 teal)
//   - 视觉系统:沿用 ChartCard(surface bg + outlineVariant border + light shadow),
//     跟 stats 债务情况卡片同款,资产页保持 surface 调(不破坏 navy 主题)
//
// 跟 debt_dashboard.dart 关系:本 widget 跟 stats 端 investment 不重复
//   - debt_dashboard 走"债务情况"(receivable 段),在 stats 资产 tab 顶部
//   - 本 widget 走"投资情况"(investment 段),在资产管理页"投资" group 上方
//   - 两 dashboard 段位 + 位置都不同,信息互补
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/investment_providers.dart';

/// 资产页"投资情况"dashboard
class InvestmentDashboard extends ConsumerWidget {
  const InvestmentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(investmentMonthlyProvider);
    final netTotalAsync = ref.watch(investmentNetTotalProvider);

    // loading 态:不画(避免卡片高度跳动)
    if (summaryAsync.isLoading || netTotalAsync.isLoading) {
      return const SizedBox.shrink();
    }
    final summary = summaryAsync.valueOrNull;
    if (summary == null) return const SizedBox.shrink();
    final hasAny = summary.monthly.any((m) => m.invested > 0 || m.returned > 0);

    final theme = Theme.of(context);
    // 空态也画卡片(跟 stats 其他 widget 一致 — 永远展示容器,内部分支)
    // 让 stats 父级 SizedBox(s3) 分隔符在所有 user 都生效,空态显示一行 hint
    return ChartCard(
      title: '投资情况',
      // 右侧 legend:投入 dot + 收益 dot(仅数据时显示)
      trailing: hasAny
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendDot(color: AppStatus.error, label: '投入'),
                const SizedBox(width: AppSpacing.s3),
                // D71.2:收益 dot 跟随 palette(浅粉 → 深粉,默认 → 青绿)
                _LegendDot(color: Theme.of(context).colorScheme.primary, label: '收益'),
              ],
            )
          : null,
      child: hasAny
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部:累计净收益大字
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s3,
                    AppSpacing.s4,
                    AppSpacing.s2,
                  ),
                  child: _NetTotalHeader(netTotalAsync: netTotalAsync),
                ),
                // 12 月双柱
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s2,
                    AppSpacing.s2,
                    AppSpacing.s2,
                    AppSpacing.s4,
                  ),
                  child: _YearlyBars(summary: summary),
                ),
                // 底部补充说明(本年投入/收益合计)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    0,
                    AppSpacing.s4,
                    AppSpacing.s3,
                  ),
                  child: _YearTotals(
                    invested: summary.investedYTD,
                    returned: summary.returnedYTD,
                    net: summary.netYTD,
                    theme: theme,
                  ),
                ),
              ],
            )
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
              child: Center(
                child: Text(
                  '本年暂无投资',
                  style: TextStyle(fontSize: 12, color: AppGray.g400),
                ),
              ),
            ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppGray.g600,
          ),
        ),
      ],
    );
  }
}

/// 累计净收益 header
class _NetTotalHeader extends StatelessWidget {
  const _NetTotalHeader({required this.netTotalAsync});
  final AsyncValue<double> netTotalAsync;

  @override
  Widget build(BuildContext context) {
    return netTotalAsync.when(
      data: (net) {
        final isProfit = net >= 0;
        // 2026-10-16 D65.3 改:整段累计净收益全红/全绿对齐
        //   - 之前:仅 +/- 符号用 isProfit 颜色,¥ + number 硬编 AppGray.g900(灰)
        //   - 视觉割裂:用户看到"− 红 + 数字灰"会迟疑这个数字到底代表什么
        //   - 改:整段(符号 + ¥ + 数字)统一用 isProfit 颜色,跟 footer "净 ±¥X" 全红/全绿 呼应
        final profitColor = isProfit ? AppStatus.success : AppStatus.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '累计净收益',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppGray.g600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  isProfit ? '+' : '−',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: profitColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.s05),
                Text(
                  '¥',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: profitColor, // D65.3:跟随 isProfit 颜色
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedCounter(
                      value: net.abs(),
                      prefix: '',
                      formatter: (v) => Formatters.amount(v),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: profitColor, // D65.3:跟随 isProfit 颜色
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        '加载失败:$e',
        style: const TextStyle(fontSize: 12, color: AppStatus.error),
      ),
    );
  }
}

/// 本年 12 月双柱
/// 2026-10-16 D64.88 改:接 `InvestmentYearSummary` 而不是 `List<MonthlyInvestment>`,
///   maxVal 直接从 summary.maxMonthlyValue 读,不再本地 fold
class _YearlyBars extends StatelessWidget {
  const _YearlyBars({required this.summary});
  final InvestmentYearSummary summary;

  @override
  Widget build(BuildContext context) {
    final monthly = summary.monthly;
    final maxVal = summary.maxMonthlyValue;
    final chartNeedsWan = maxVal >= Formatters.wanThreshold;
    // D64.69 修:必须包 SizedBox(height: 200) 给 AnimatedBarChart 显式高度
    //   - 直接在 Column(ChartCard child, unbounded vertical max)里放 chart
    //     会让 fl_chart BarChart 报 "BoxConstraints forces an infinite height"
    //   - 跟 consumption_trend 用 TabBarView 包 chart 不一样,InvestmentDashboard
    //     不用 tab,需要在 chart 自身给 bounded height
    //   - 200 px 跟 AnimatedLineChart savings_trend 220→260 同档,12 月双柱足够
    return SizedBox(
      height: 200,
      child: AnimatedBarChart(
      bars: [
        for (final m in monthly)
          BarChartBar(
            label: '${m.month}月',
            value: m.invested,
            secondaryValue: m.returned,
          ),
      ],
      maxVal: maxVal,
      minVal: summary.minMonthlyValue, // D65.3:负值启用负轴 + 0 线突出
      chartNeedsWan: chartNeedsWan,
      primaryColor: AppStatus.error,
      // D65.4 改:用 secondaryColorResolver 替代 D65.3 写错的 barColorResolver
      //   - barColorResolver 只作用于主柱(投入),D65.3 误用导致主柱变 teal
      //   - 正确做法:主柱固定红,次柱(收益)按值变色
      //   - 收益 ≥ 0 绿(默认) / 收益 < 0 变红(财务直觉:亏 = 红)
      secondaryColorResolver: (i, b) {
        final ret = b.secondaryValue ?? 0;
        // D71.2:收益 ≥ 0 跟随 palette(浅粉 → 深粉,默认 → 青绿)
        return ret < 0
            ? AppStatus.error
            : Theme.of(context).colorScheme.primary;
      },
      barWidth: 5,
      barsSpace: 1,
      groupsSpace: 3,
      // 12 月全标 label 太密 → 稀疏化到 1 / 3 / 6 / 9 / 12
      xLabelBuilder: (i, b) {
        final m = monthly[i].month;
        final show = m == 1 || m == 3 || m == 6 || m == 9 || m == 12;
        if (!show) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            b.label,
            style: const TextStyle(fontSize: 9, color: AppGray.g600),
          ),
        );
      },
      touchedLabelBuilder: (i, b) => '${monthly[i].month}月',
      tooltipBuilder: (i, b) {
        final m = monthly[i];
        return '投 ¥${Formatters.amount(m.invested)}\n收 ¥${Formatters.amount(m.returned)}';
      },
    ),
    );
  }
}

/// 底部本年合计
class _YearTotals extends StatelessWidget {
  // 2026-10-16 D64.88 改:接 invested/returned/net 直接,不再 fold
  //   - 之前从 List<MonthlyInvestment> monthly 自己 fold 算 3 个聚合
  //   - 改:InvestmentDashboard.build 传 investment/returned/net 进来,跟 _YearlyBars
  //     一样从 summary 字段读(provider 一次性算,不在 widget 重复 fold)
  const _YearTotals({
    required this.invested,
    required this.returned,
    required this.net,
    required this.theme,
  });
  final double invested;
  final double returned;
  final double net;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isProfit = net >= 0;
    // 2026-10-16 D64.71 修:投资情况 dashboard footer overflow 39px
    //   - 之前外层 Row 直接 spaceBetween ["本年合计" 44px] + 内层 Row[3 段金额 200+px]
    //   - 数据规模 4.7 万级 → 总宽 278px,撑爆 chart card 249px 可用宽度
    //   - 修法:右侧整块用 Flexible + FittedBox(scaleDown) 兜底
    //     - 不溢出时按 11sp 原样显示
    //     - 溢出时按比例缩小字号(最小 ~9sp),保留 3 段信息不省略
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '本年合计',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '投 ¥${Formatters.amount(invested)}',
                  style: const TextStyle(fontSize: 11, color: AppGray.g600),
                ),
                const SizedBox(width: AppSpacing.s3),
                Text(
                  '收 ¥${Formatters.amount(returned)}',
                  style: const TextStyle(fontSize: 11, color: AppGray.g600),
                ),
                const SizedBox(width: AppSpacing.s3),
                Text(
                  '净 ${isProfit ? '+' : '−'}¥${Formatters.amount(net.abs())}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isProfit ? AppStatus.success : AppStatus.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
