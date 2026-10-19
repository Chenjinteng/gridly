// lib/features/stats/ui/widgets/range_summary.dart
// 当前时间窗的汇总(收入/支出/结余 三色块)
//
// 2026-10-12 ColorOS 风数字入场:三个 _Stat 内 Text 改 AnimatedCounter,
// 首次进入页面 / 切换时间范围时,数字从 0(或旧值)滚动到新值,360ms aquaIn
// 颜色色 / 进制(万元 mode) 仍由 Formatters 处理。
//
// 2026-10-12 P5 commit 加同比箭头:本月维度显示 ▲▼ + 百分比(零除边界 = 绝对值 ±),
// 本年维度不显示。月度汇总的"变"信息让 user 一眼看到趋势。
//
// 2026-10-15 D64.9 改:footer 行复用,左对齐储蓄率(= balance / income * 100),
//   右对齐保留"同比上月/去年"。user UAT 反馈"同比提示一行很空,可以把储蓄率
//   放左对齐"。储蓄率 % 跟结余同色逻辑(正 teal / 负 error / 零 neutral)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/theme/gridly_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
import '../../application/stats_providers.dart';

class RangeSummary extends ConsumerWidget {
  const RangeSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSummaryProvider);
    final range = ref.watch(statsRangeProvider);
    // D62.3:按 range 选对应同比 provider
    //   - 本月 → monthlyYoYProvider(本月 vs 上月)
    //   - 本年 → yearlyYoYProvider(本年 vs 去年整年)
    final yoyAsync = ref.watch(
      range == StatsRange.thisMonth ? monthlyYoYProvider : yearlyYoYProvider,
    );
    final yoy = yoyAsync.valueOrNull ?? MonthlyYoY.empty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // D62.2 UAT 加 footer 提示,D62.3 扩展:本月显示"同比上月",本年显示"同比去年"
    //   - user 反馈"± 与上一个月的同比吗"(D62.2 起源)
    //   - D62.3 user 又要求"年度小卡片也需要" — 本年维度补 footer
    final yoyFooterLabel = range == StatsRange.thisMonth ? '同比上月' : '同比去年';
    // 2026-10-15 D64.9:当月/当年储蓄率 = balance / income * 100
    //   - income == 0 时给 0.0(不可计算,显示中性值,避免除 0)
    //   - 颜色逻辑跟结余一致:正 teal(健康) / 负 error(超支) / 零 onSurfaceVariant
    final savingsRate = s.income > 0 ? (s.balance / s.income) * 100 : 0.0;
    final savingsRateColor = savingsRate > 0
        ? Theme.of(context).colorScheme.primary
        : savingsRate < 0
        ? AppStatus.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        // D71.3:永远走 inkPalette.inkSurface(深色模式不变 cream)
        color: Theme.of(context).extension<GridlyPalette>()!.inkSurface,
        borderRadius: AppRadius.brLg,
        // rim light border,与月度汇总卡保持一致
        border: Border.all(
          color: Theme.of(context)
              .extension<GridlyPalette>()!
              .onInkSurface
              .withValues(alpha: isDark ? 0.08 : 0.15),
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
                  // D71.2:收入色跟随 palette(浅粉 → 亮粉,默认 → 金黄)
                  color: Theme.of(context).colorScheme.secondary,
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
          // D62.2 + D62.3:右对齐灰色 10sp 小字,本月显示"同比上月",本年显示"同比去年"
          //   - user 反馈 ± 不知道是跟哪个维度对比,直接在卡片上明示
          //   - 本年维度 footer + 同比箭头同时存在(D62.3 加 yearlyYoYProvider)
          // D64.9:左对齐加储蓄率(label 灰 + % 着色),同一行 footer 复用空间。
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Text(
                '储蓄率 ',
                style: const TextStyle(color: AppGray.g400, fontSize: 10),
              ),
              Text(
                '${savingsRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: savingsRateColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                yoyFooterLabel,
                style: const TextStyle(color: AppGray.g400, fontSize: 10),
              ),
            ],
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
      color = Theme.of(context).colorScheme.primary;
      icon = Icons.arrow_drop_up_rounded;
    } else {
      color = AppStatus.error;
      icon = Icons.arrow_drop_down_rounded;
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s05),
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
