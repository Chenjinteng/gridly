// lib/features/stats/ui/widgets/range_summary.dart
// 当前时间窗的汇总(收入/支出/结余 三色块)
//
// 2026-10-12 ColorOS 风数字入场:三个 _Stat 内 Text 改 AnimatedCounter,
// 首次进入页面 / 切换时间范围时,数字从 0(或旧值)滚动到新值,360ms aquaIn
// 颜色色 / 进制(万元 mode) 仍由 Formatters 处理。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
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
    // 2026-10-11 UAT:数字长(¥16,540.32 / ¥13,085.08)时,"¥" 字符贴着
    // card 左边线,"32" 几乎碰到分隔线,看着像没居中。Column 加 4px
    // 水平内边距,数字跟分隔线 / 卡片边之间留出视觉呼吸位。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppGray.g400, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: AnimatedCounter(
              // 2026-10-12 count-up:首次从 0 滚到当前 amount;值变化时
              // 从旧值滚到新值(切月份 / 视角时数据更新自然滚动到位)。
              // Formatters.amount 接 double 输出 "¥16,540" 这种格式,
              // withUnit:false 是因为 label `收入(万元)` 已经声明单位,
              // 数字部分只输出纯数字。
              prefix: '¥',
              value: amount,
              formatter: (v) => Formatters.amount(v, withUnit: false),
              duration: const Duration(milliseconds: 480),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}
