// lib/features/stats/ui/widgets/assets_by_type.dart
// 报表"按资产 6 段分析"模块 —— 1 张 ChartCard + 柱状图
//
// 2026-10-15 D64.28 加:user UAT D64.27 上线后反馈'stats_page 加 4 个新模块,
// 第 4 个是按资产 6 段分析(全年)'。
//
// 设计:
// - 6 段 = cash_flow / investment / benefit / receivable / fixed_asset / other
// - 从 expenseByAssetProvider(已有,range-aware)聚合 6 段总值
// - 6 柱条按段配色(AppSegment.colorFor),无支出段 amount=0 仍显示空柱
// - chart height 220(同消费趋势)
// - 跟 ExpenseAnalysis 的"账户" tab 区别:这里是按段(6 类),不是按账户(N 个)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/animated_bar_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

class AssetsByType extends ConsumerWidget {
  const AssetsByType({super.key});

  static const _segmentTypes = [
    'cash_flow',
    'investment',
    'benefit',
    'receivable',
    'fixed_asset',
    'other',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseByAssetProvider);
    final assetsAsync = ref.watch(allAssetsProvider);
    return expenseAsync.when(
      loading: () => _loading(),
      error: (e, _) => _error(context, e),
      data: (byAsset) {
        final assetList = assetsAsync.valueOrNull ?? const <Asset>[];
        final assetById = {for (final a in assetList) a.id: a};

        final byType = <String, double>{};
        for (final e in byAsset) {
          final asset = assetById[e.assetId];
          if (asset == null) continue;
          byType[asset.type] = (byType[asset.type] ?? 0) + e.amount;
        }

        if (byType.values.every((v) => v == 0)) {
          return ChartCard(
            title: '按资产 6 段分析',
            showDivider: false,
            child: const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  '本段暂无支出',
                  style: TextStyle(color: AppGray.g600, fontSize: 13),
                ),
              ),
            ),
          );
        }

        final maxVal = byType.values.fold<double>(0, (a, b) => a > b ? a : b);
        final chartNeedsWan = maxVal >= Formatters.wanThreshold;

        return ChartCard(
          title: '按资产 6 段分析',
          showDivider: false,
          child: SizedBox(
            height: 220,
            child: AnimatedBarChart(
              bars: [
                for (final t in _segmentTypes)
                  BarChartBar(
                    label: AppSegment.labelFor(t),
                    value: byType[t] ?? 0,
                  ),
              ],
              maxVal: maxVal,
              chartNeedsWan: chartNeedsWan,
              barWidth: 18,
              // 颜色按段配置(AppSegment.colorFor)
              barColorResolver: (i, b) =>
                  AppSegment.colorFor(_segmentTypes[i]),
              xLabelBuilder: (i, b) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  b.label,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              touchedLabelBuilder: (i, b) => b.label,
              tooltipBuilder: (i, b) =>
                  '${b.label} ¥${Formatters.amount(b.value)}',
            ),
          ),
        );
      },
    );
  }

  Widget _loading() {
    return ChartCard(
      title: '按资产 6 段分析',
      showDivider: false,
      child: const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _error(BuildContext context, Object e) {
    return ChartCard(
      title: '按资产 6 段分析',
      showDivider: false,
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Text(
            '加载失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
      ),
    );
  }
}
