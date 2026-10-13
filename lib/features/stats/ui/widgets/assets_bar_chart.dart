// lib/features/stats/ui/widgets/assets_bar_chart.dart
// stats 资产视角 — 6 段横向条形图(替换原 fl_chart RadarChart)
//
// 2026-10-13 P6 commit 替换(2026-10-13 12:14 UAT:"雷达图现金流只少 10 块
//   视觉上明显内缩,算法不合理"):
//   - fl_chart 0.69 RadarChart 算法特性:
//     `centerValue = data.minEntry.value - (data.maxEntry.value - data.minEntry.value) / tickCount`
//     归一化 = (point.value - centerValue) / (data.maxEntry.value - centerValue)
//     当 6 段数据非常接近时(max-min 极小),差异会被"挤"在最外 1 个 tick 圈里
//     视觉放大(0.1% 实际差异 → 80% 视觉差异)
//   - fl_chart 0.69 的 RadarChartData 没有 maxValue 字段可手动设,无法修复
//   - 改方案 A:6 段横向条形图 + 自定义归一化:
//       归一化 = value / max(values) (直接除,我们自己控制)
//       9990 / 10000 = 0.999 (视觉上几乎贴满 max bar)
//       差异按真实比例显示,不再放大
//
// 设计:
//   - 6 行 horizontal bar,顺序按日常查看频度:
//     现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
//   - 每行:icon chip(32)+ label + 进度条(0-1 归一化)+ 金额数字
//   - 进度条:Stack 画灰色底 + 彩色 fill;fill 长度 = abs(value) / max(abs(values))
//   - 颜色跟 type 配色一致(teal/gold/success/warning/info/gray)
//   - 金额直接显示原值(¥9,990.00),不显示坐标轴 tick(规避 user 偏好
//     "图表 tick 不要渲染 maxY 实际值")
//   - viewport-aware 触发(同款 pattern:GlobalKey + Scrollable.position 监听)
//   - TweenAnimationBuilder 0→1 让 fill 从 0 撑开到目标比例,
//     跟总览卡 AnimatedCounter 数字滚动同步(1200ms aquaIn)
//   - 替代 AssetsRadar(class 名改成 AssetsBarChart)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/staggered_fade_in.dart';

class AssetsBarChart extends ConsumerStatefulWidget {
  const AssetsBarChart({super.key});

  @override
  ConsumerState<AssetsBarChart> createState() => _AssetsBarChartState();
}

class _AssetsBarChartState extends ConsumerState<AssetsBarChart> {
  /// viewport-aware 触发(跟 AssetsOverviewChart / 原 AssetsRadar 同款)
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
    final theme = Theme.of(context);
    final totalsAsync = ref.watch(assetTotalsProvider);
    return Container(
      key: _chartKey,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行(沿用原 AssetsRadar 文案)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '资产分布',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '正负值都反映',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s3),
            child: totalsAsync.when(
              loading: () => const SizedBox(
                height: 200,
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
                // 6 段(顺序按日常查看频度,跟总览卡一致)
                final entries = <_BarEntry>[
                  _BarEntry(
                    label: '现金流',
                    value: totals.totalCashFlow,
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppBrand.teal,
                  ),
                  _BarEntry(
                    label: '投资',
                    value: totals.totalInvestment,
                    icon: Icons.trending_up_rounded,
                    color: AppBrand.gold,
                  ),
                  _BarEntry(
                    label: '福利',
                    value: totals.totalBenefit,
                    icon: Icons.favorite_rounded,
                    color: AppStatus.success,
                  ),
                  _BarEntry(
                    label: '债权',
                    value: totals.totalReceivable,
                    icon: Icons.handshake_rounded,
                    color: AppStatus.warning,
                  ),
                  _BarEntry(
                    label: '不动产',
                    value: totals.totalFixedAsset,
                    icon: Icons.home_rounded,
                    color: AppStatus.info,
                  ),
                  _BarEntry(
                    label: '其它',
                    value: totals.totalOther,
                    icon: Icons.category_rounded,
                    color: AppGray.g600,
                  ),
                ];
                // 极端 case:6 个都 0 → 显示空态
                if (entries.every((e) => e.value.abs() == 0)) {
                  return const SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        '还没有资产数据',
                        style: TextStyle(color: AppGray.g600, fontSize: 13),
                      ),
                    ),
                  );
                }
                // max 用于归一化(取 abs 后的最大值,跟原雷达图 abs 一致)
                //   - 用 abs 而不是 raw:防止负值(欠款)让 max 出奇,
                //     让所有 bar 归一化合理
                final maxAbs = entries
                    .map((e) => e.value.abs())
                    .reduce((a, b) => a > b ? a : b);

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: _appeared ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: AppMotion.aquaIn,
                  builder: (context, progress, _) {
                    return Column(
                      children: [
                        for (int i = 0; i < entries.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i < entries.length - 1
                                  ? AppSpacing.s3
                                  : 0,
                            ),
                            // 沿用 stats_page 的 30ms 错峰 fade-in
                            child: StaggeredFadeIn(
                              index: i,
                              enabled: _appeared,
                              child: _BarRow(
                                entry: entries[i],
                                maxAbs: maxAbs,
                                progress: progress,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行:icon + label + 进度条(Stack 画 fill)+ 金额
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.entry,
    required this.maxAbs,
    required this.progress,
  });

  final _BarEntry entry;
  final double maxAbs;
  final double progress;

  @override
  Widget build(BuildContext context) {
    // 归一化:abs(value) / maxAbs,但 progress 让 fill 从 0 撑开
    // - progress=0 → 全部 fill 长度 0
    // - progress=1 → fill 长度 = 真实归一化比例(0-1)
    final ratio = maxAbs == 0 ? 0.0 : (entry.value.abs() / maxAbs) * progress;
    final theme = Theme.of(context);

    return Row(
      children: [
        // icon chip 32(跟 type 配色)
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: entry.color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brSm,
          ),
          child: Icon(entry.icon, color: entry.color, size: 18),
        ),
        const SizedBox(width: AppSpacing.s3),
        // label(13sp 灰)
        SizedBox(
          width: 48,
          child: Text(
            entry.label,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 进度条(Stack 画 fill,LayoutBuilder 控制高度)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // 底
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: AppRadius.brSm,
                    ),
                  ),
                  // fill
                  AnimatedContainer(
                    duration: Duration.zero, // 走外层 TweenAnimationBuilder
                    height: 14,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: entry.color,
                      borderRadius: AppRadius.brSm,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        // 金额(右对齐,固定宽度容纳 999,999.99 之类)
        SizedBox(
          width: 80,
          child: Text(
            '¥${Formatters.amount(entry.value)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: entry.color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _BarEntry {
  const _BarEntry({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final double value;
  final IconData icon;
  final Color color;
}
