// lib/features/stats/ui/widgets/range_summary.dart
// 当前时间窗的汇总(收入/支出/结余 三色块)
//
// 2026-10-12 ColorOS 风数字入场:三个 _Stat 内 Text 改 AnimatedCounter,
// 首次进入页面 / 切换时间范围时,数字从 0(或旧值)滚动到新值,360ms aquaIn
// 颜色色 / 进制(万元 mode) 仍由 Formatters 处理。
//
// 2026-10-12 P5 commit 加同比箭头:本月维度显示 ▲▼ + 百分比(零除边界 = 绝对值 ±),
// 本年维度不显示。月度汇总的"变"信息让 user 一眼看到趋势。
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
    final yoyAsync = ref.watch(monthlyYoYProvider);
    final yoy = yoyAsync.valueOrNull ?? MonthlyYoY.empty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // D62.2 UAT 加:仅本月维度显示"同比上月"小字提示
    //   - 本年维度没同比(provMonthlyYoYProvider 返 MonthlyYoY.empty),提示也不需要
    //   - user 反馈"± 与上一个月的同比吗" — 直接在卡片上明示,免 user 猜
    final isThisMonth = ref.watch(statsRangeProvider) == StatsRange.thisMonth;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 同比加在 _Stat 里后,Column 变高(3 行:label / number / yoy)。
          // 分隔线高度硬编码 32(不要 stretch — ListView 无限高度 + Row.stretch +
          // 无 height 子项会触发 BoxConstraints forces an infinite height 异常,
          // 整个 RangeSummary 抛错 → 报表页全空白)
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: Formatters.labelledUnit('收入', s.income),
                  amount: s.income,
                  color: AppBrand.gold,
                  yoy: yoy.income,
                ),
              ),
              Container(width: 1, height: 32, color: AppGray.g600),
              Expanded(
                child: _Stat(
                  label: Formatters.labelledUnit('支出', s.expense),
                  amount: s.expense,
                  color: AppStatus.error,
                  yoy: yoy.expense,
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
                  yoy: yoy.balance,
                ),
              ),
            ],
          ),
          // D62.2:右对齐灰色 10sp 小字"同比上月",提示 user ± 是跟上月对比
          if (isThisMonth) ...[
            const SizedBox(height: AppSpacing.s2),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                '同比上月',
                style: TextStyle(color: AppGray.g400, fontSize: 10),
              ),
            ),
          ],
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
    this.yoy,
  });
  final String label;
  final double amount;
  final Color color;

  /// 同比箭头 + 文字(2026-10-12 P5 加),null = 不显示
  final YoYDelta? yoy;

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
          // 同比箭头(2026-10-12 P5 加):仅本月维度显示,本年维度 provider 给 MonthlyYoY.empty,
          // 3 个字段全 null,Badge 渲染 SizedBox.shrink 不占空间。
          _YoYBadge(yoy: yoy),
        ],
      ),
    );
  }
}

/// 同比小徽章:箭头(▲▼ 或 —)+ 文字(百分比 / 绝对值)
///   - YoYDelta.isUp=true  → ▲ + teal(正方向)
///   - YoYDelta.isUp=false → ▼ + error(负方向)
///   - text 是 "0.0%" 时(持平):— + onSurfaceVariant(中性)
///   - null → SizedBox.shrink(本年维度 / 全 0)
class _YoYBadge extends StatelessWidget {
  const _YoYBadge({required this.yoy});
  final YoYDelta? yoy;

  @override
  Widget build(BuildContext context) {
    final y = yoy;
    if (y == null) return const SizedBox.shrink();
    // 持平 = "0.0%" 字符串判定(provider 里 pct == 0 时会精确产出 "0.0%")
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
      // D62 UAT 修:同比文字过长(±¥20,000.0)时 _YoYBadge 自然宽 > parent column
      // 宽,触发 RenderFlex overflow 0.323px。FittedBox(scaleDown) 只在溢出时缩放,
      // 短文字(0.0% / +12.5%)保持原字号不变。
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
          ],
        ),
      ),
    );
  }
}
