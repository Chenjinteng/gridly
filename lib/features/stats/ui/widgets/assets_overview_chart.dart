// lib/features/stats/ui/widgets/assets_overview_chart.dart
// stats 资产视角总览卡 —— 总资产 + 6 大类汇总
//
// 2026-10-12 P4 commit 加(P4 · 资产分布 + 雷达图):
//   - 跟 budget_overview_chart 同款 viewport-aware 触发入场
//     (GlobalKey + Scrollable.position 监听,任意部分进入 viewport 才触发)
//   - 顶部"总资产" + 大数字 0→total 滚动(1200ms aquaIn)
//   - 6 行 type chip:icon + 类型名 + 余额(纯展示,点击无效果)
//     顺序:现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
//   - 黑底卡片(ink 风格,跟 settings_page "关于"卡 / range_summary 一致)
//
// 2026-10-13 P6 改 4 段 → 6 段(跟 asset_form 6 段同步,删"负债"加投资/福利/债权)
//
// 数据源:assetTotalsProvider
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';

class AssetsOverviewChart extends ConsumerStatefulWidget {
  const AssetsOverviewChart({super.key});

  @override
  ConsumerState<AssetsOverviewChart> createState() =>
      _AssetsOverviewChartState();
}

class _AssetsOverviewChartState extends ConsumerState<AssetsOverviewChart> {
  /// viewport-aware 触发(跟 budget_overview_chart 同款,commit 102):
  ///   - false:widget 还没进入 scroll viewport,数字显示 0
  ///   - true:viewport 进入后,数字从 0 滚动到目标值 —— 一次性,不再重置
  bool _appeared = false;

  final GlobalKey _chartKey = GlobalKey();

  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollPos = Scrollable.maybeOf(context)?.position;
      _scrollPos?.addListener(_checkInView);
      _checkInView();
    });
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  void _checkInView() {
    if (_appeared) return;
    final ctx = _chartKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final scrollableBox =
        _scrollPos?.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollableBox == null) return;
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      _appeared = true;
      _scrollPos?.removeListener(_checkInView);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalsAsync = ref.watch(assetTotalsProvider);
    final theme = Theme.of(context);
    return Container(
      key: _chartKey,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
        // rim light border + 黑底阴影,跟其他黑底卡保持一致
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: totalsAsync.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Text(
            '加载资产失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
        data: (totals) {
          // 总资产 = 6 类之和(简单累加,P4 文档明确"按大类 currentBalance 总和")
          final totalAll =
              totals.totalCashFlow +
              totals.totalInvestment +
              totals.totalBenefit +
              totals.totalReceivable +
              totals.totalFixedAsset +
              totals.totalOther;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '总资产',
                    style: TextStyle(
                      color: AppGray.g400,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    '6 大类',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s1),
              // 大数字(进入 viewport 后从 0 滚动到 total)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedCounter(
                  prefix: '¥',
                  value: _appeared ? totalAll : 0,
                  // 2026-10-13 UAT fix:总资产跟 6 段明细用同一单位
                  //   - 6 段明细(尤其"不动产 ¥100.00万")都用 withUnit: true 带"万"
                  //   - 总资产 ≥ 100 万时也得带"万",否则 ¥172.89 跟 ¥100.00万
                  //     看起来不像是 1 个量级的(用户问"为什么是 172.89")
                  //   - 实际 1,728,990 / 10000 = 172.899 → 172.89万 才跟 6 段对得上
                  formatter: (v) => Formatters.amount(v, withUnit: true),
                  duration: const Duration(milliseconds: 1200),
                  curve: AppMotion.aquaIn,
                  style: const TextStyle(
                    color: AppSecondary.cream,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              const Divider(height: 1, color: AppGray.g600),
              const SizedBox(height: AppSpacing.s3),
              // 6 大类汇总(2026-10-13 P6:顺序按日常查看频度)
              _TypeRow(
                icon: Icons.account_balance_wallet_rounded,
                label: '现金流',
                amount: _appeared ? totals.totalCashFlow : 0,
                color: AppBrand.teal,
              ),
              const SizedBox(height: AppSpacing.s2),
              _TypeRow(
                icon: Icons.trending_up_rounded,
                label: '投资',
                amount: _appeared ? totals.totalInvestment : 0,
                color: AppBrand.gold,
              ),
              const SizedBox(height: AppSpacing.s2),
              _TypeRow(
                icon: Icons.favorite_rounded,
                label: '福利',
                amount: _appeared ? totals.totalBenefit : 0,
                color: AppStatus.success,
              ),
              const SizedBox(height: AppSpacing.s2),
              _TypeRow(
                icon: Icons.handshake_rounded,
                label: '债权/借出',
                amount: _appeared ? totals.totalReceivable : 0,
                color: AppStatus.warning,
              ),
              const SizedBox(height: AppSpacing.s2),
              _TypeRow(
                icon: Icons.home_rounded,
                label: '不动产',
                amount: _appeared ? totals.totalFixedAsset : 0,
                color: AppStatus.info,
              ),
              const SizedBox(height: AppSpacing.s2),
              _TypeRow(
                icon: Icons.category_rounded,
                label: '其它',
                amount: _appeared ? totals.totalOther : 0,
                color: AppGray.g600,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 6 大类单行(跟 AssetSummaryCard._TypeRow 同款,这里独立避免跨文件依赖)
class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });
  final IconData icon;
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brXs,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppGray.g400, fontSize: 13),
          ),
        ),
        Text(
          '¥${Formatters.amount(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
