// lib/features/stats/ui/widgets/range_summary.dart
// 当前时间窗的汇总(收入/支出/结余 三色块)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/stats_providers.dart';

class RangeSummary extends ConsumerWidget {
  const RangeSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSummaryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
        // rim light border,与月度汇总卡保持一致
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
          width: 1.0,
        ),
        // 黑底卡:重阴影,与月度汇总卡保持一致(dark mode 自动切白阴影)
        boxShadow: CardShadows.dark(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              // 单位标签按值动态切 (元)/(万元) —— Formatters.amount 同步切万
              label: Formatters.labelledUnit('收入', s.income),
              amount: s.income,
              color: AppBrand.gold,
            ),
          ),
          Container(width: 1, height: 32, color: AppGray.g600),
          Expanded(
            child: _Stat(
              label: Formatters.labelledUnit('支出', s.expense),
              amount: s.expense,
              color: AppStatus.error,
            ),
          ),
          Container(width: 1, height: 32, color: AppGray.g600),
          Expanded(
            child: _Stat(
              label: Formatters.labelledUnit('结余', s.balance),
              amount: s.balance,
              // 结余按值动态选色(正 teal / 负 error / 零 cream)
              // 2026-10-11 UAT:之前的常量 cream 让 -3726 这种重要数字"白底白字"
              // 不直观。颜色主题与设计稿保持一致:
              //   绿/正 → AppBrand.teal #14B8A6
              //   红/负 → AppStatus.error #EF4444
              color: AppSemantic.balanceFor(s.balance),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppGray.g400, fontSize: 11),
        ),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            // label `收入(万元)` 已经声明单位,数字不重复带"万"
            '¥${Formatters.amount(amount, withUnit: false)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
