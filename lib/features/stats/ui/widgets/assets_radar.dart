// lib/features/stats/ui/widgets/assets_radar.dart
// stats 资产视角 — 6 维雷达图
//
// 2026-10-12 P4 commit 加(P4 · 资产分布 + 雷达图):
//   - fl_chart RadarChart 6 维:现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
//   - 累加不取 abs(让 user 看到"实际欠多少/待收多少",正值/负值都反映)
//   - fl_chart 0.69 自动 scale 到 max value,不需要手动指定 maxValue
//   - title style:11px w600
//   - 数据源:assetTotalsProvider
//   - viewport-aware 触发 fade-in(opacity 0→1,360ms aquaIn)
//     (fl_chart RadarChart 暂没原生入场动画,这里用 AnimatedOpacity 兜底)
//
// 2026-10-13 P6 改 4 维 → 6 维(跟 asset_form 6 段同步)
//
// 风险(P4 文档):数值差异大 → fl_chart 默认线性 scale,大值维度压扁小值维度
//   - 备选 log scale 在这里不实现,先跑通线性看效果再调
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';

class AssetsRadar extends ConsumerStatefulWidget {
  const AssetsRadar({super.key});

  @override
  ConsumerState<AssetsRadar> createState() => _AssetsRadarState();
}

class _AssetsRadarState extends ConsumerState<AssetsRadar> {
  /// viewport-aware 触发(跟 AssetsOverviewChart 同款)
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
                // 雷达图维度(2026-10-13 P6:4 维 → 6 维,跟 asset_form 6 段同步)
                // - 取 abs 防止负值穿透:虽然累计可能负(欠款),但雷达图显示"幅度对比"
                // - 6 段顺序按日常查看频度:现金 / 投资 / 福利 / 债权 / 不动产 / 其它
                final values = [
                  totals.totalCashFlow.abs(),
                  totals.totalInvestment.abs(),
                  totals.totalBenefit.abs(),
                  totals.totalReceivable.abs(),
                  totals.totalFixedAsset.abs(),
                  totals.totalOther.abs(),
                ];
                // 极端 case:6 个都 0 → 雷达图中央 0 点,显示空态
                final allZero = values.every((v) => v == 0);
                if (allZero) {
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
                return SizedBox(
                  height: 240,
                  child: AnimatedOpacity(
                    opacity: _appeared ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 360),
                    curve: AppMotion.aquaIn,
                    child: RadarChart(
                      RadarChartData(
                        radarShape: RadarShape.polygon,
                        // tickCount 4:网格 4 圈(0, 1/4, 2/4, 3/4, max)
                        // fl_chart 0.69 自动 scale 到 max value,所以不需要手动指定 maxValue
                        tickCount: 4,
                        ticksTextStyle: const TextStyle(
                          color: Colors.transparent,
                          fontSize: 0, // 隐藏 tick 文字
                        ),
                        radarBorderData: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                        gridBorderData: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                        tickBorderData: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                        getTitle: (i, _) {
                          final labels = const [
                            '现金流',
                            '投资',
                            '福利',
                            '债权',
                            '不动产',
                            '其它',
                          ];
                          return RadarChartTitle(
                            text: labels[i],
                            positionPercentageOffset: 0.05,
                          );
                        },
                        titleTextStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        dataSets: [
                          RadarDataSet(
                            fillColor: AppBrand.teal.withValues(alpha: 0.18),
                            borderColor: AppBrand.teal,
                            borderWidth: 2,
                            entryRadius: 3,
                            dataEntries: values
                                .map((v) => RadarEntry(value: v))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
