// lib/features/stats/ui/widgets/savings_rate_card.dart
// 报表第 7 张卡:储蓄率(本月结余 / 收入 × 100%)
//   - 跟 range_summary 的"结余"区别:结余是绝对值,储蓄率是百分比,直观可比
//   - 同比:本月储蓄率 vs 上月储蓄率(箭头 + 百分比)
//   - 数据源:复用 statsSummaryProvider + monthlyYoYProvider(都是 D62/D62.4 口径)
//
// 2026-10-15 D63 加
// 2026-10-15 D64.3 改:容器改用 `ChartCard`,trailing 传同比 badge
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../application/stats_providers.dart';

class SavingsRateCard extends ConsumerWidget {
  const SavingsRateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSummaryProvider);
    final yoyAsync = ref.watch(monthlyYoYProvider);
    final yoy = yoyAsync.valueOrNull ?? MonthlyYoY.empty;
    // 储蓄率 = balance / income × 100
    // income = 0 时返回 0(避免 Infinity)
    final savingsRate = s.income > 0 ? (s.balance / s.income) * 100 : 0.0;
    // 储蓄率颜色:正 → teal(健康),负 → error(超支),零 → 中性
    final rateColor = savingsRate > 0
        ? AppBrand.teal
        : savingsRate < 0
        ? AppStatus.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ChartCard(
      title: '储蓄率',
      showDivider: false,
      trailing: _SavingsYoYBadge(
        currRate: savingsRate,
        currBalance: s.balance,
        currIncome: s.income,
        yoy: yoy.balance,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // 大数字:储蓄率百分比
              Text(
                '${savingsRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: rateColor,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              // 副文案:结余 / 收入
              Expanded(
                child: Text(
                  '本月结余 ¥${Formatters.amount(s.balance, withUnit: false)} / 收入 ¥${Formatters.amount(s.income, withUnit: false)}',
                  style: const TextStyle(fontSize: 11, color: AppGray.g600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 储蓄率同比 badge:
///   - 上月有数据(>0) → 显示百分比或绝对值(走 balance YoY text,跟 range_summary 同款)
///   - 上月无数据 → "—" 占位
class _SavingsYoYBadge extends StatelessWidget {
  const _SavingsYoYBadge({
    required this.currRate,
    required this.currBalance,
    required this.currIncome,
    required this.yoy,
  });
  final double currRate;
  final double currBalance;
  final double currIncome;
  final YoYDelta? yoy;

  @override
  Widget build(BuildContext context) {
    final y = yoy;
    if (y == null) return const SizedBox.shrink();
    final isFlat = y.text == '0.0%';
    final Color color;
    final IconData icon;
    if (isFlat) {
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      icon = Icons.remove_rounded;
    } else if (y.isUp) {
      color = AppBrand.teal;
      icon = Icons.arrow_drop_up_rounded;
    } else {
      color = AppStatus.error;
      icon = Icons.arrow_drop_down_rounded;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      // FittedBox(scaleDown) 防同比文字过长 overflow,跟 range_summary _YoYBadge 同款
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 1),
            Text(
              y.text,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '同比储蓄率',
              style: TextStyle(fontSize: 11, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}
