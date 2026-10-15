// lib/features/stats/ui/widgets/expense_by_asset.dart
// 报表第 8 张卡:按支付账户/资产支出分布(类似 category_pie 但按账户)
//   - user 多账户场景:看现金账户 / 各信用卡 / 花呗 各花了多少
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 还款(现金→债务调拨)accountId 是 source 现金账户,归到现金账户
//   - 复用 AnimatedPieChart 跟 category_pie 风格一致
//
// 2026-10-15 D63 加
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../application/stats_providers.dart';

class ExpenseByAssetChart extends ConsumerWidget {
  const ExpenseByAssetChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(expenseByAssetProvider);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '支付账户',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                assetsAsync.maybeWhen(
                  data: (data) {
                    if (data.isEmpty) return const SizedBox.shrink();
                    final total = data.fold<double>(0, (s, e) => s + e.amount);
                    return Text(
                      '共 ¥${Formatters.amount(total)}',
                      style: const TextStyle(fontSize: 12, color: AppGray.g600),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          assetsAsync.when(
            data: (data) {
              if (data.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
                  child: Center(
                    child: Text(
                      '该时段无支出',
                      style: TextStyle(color: AppGray.g600, fontSize: 13),
                    ),
                  ),
                );
              }
              final total = data.fold<double>(0, (s, e) => s + e.amount);
              final shown = data.take(8).toList();
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 左侧圆环
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
                                      value: e.amount,
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
                                    value: e.amount,
                                    color: Color(e.color),
                                    title: '',
                                    radius: 18,
                                  ),
                                )
                                .toList(),
                          ),
                          // 中心"总支出"文字
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '总支出',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppGray.g600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '¥${Formatters.amount(total)}',
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
                          final pct = (e.amount / total * 100);
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
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.s3),
              child: Text(
                '加载失败:$e',
                style: const TextStyle(color: AppStatus.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
