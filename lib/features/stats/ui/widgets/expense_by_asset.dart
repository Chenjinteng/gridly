// lib/features/stats/ui/widgets/expense_by_asset.dart
// 报表第 8 张卡:按支付账户/资产支出分布(类似 category_pie 但按账户)
//   - user 多账户场景:看现金账户 / 各信用卡 / 花呗 各花了多少
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 还款(现金→债务调拨)accountId 是 source 现金账户,归到现金账户
//   - 复用 AnimatedPieChart 跟 category_pie 风格一致
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 改:viewport-aware 触发动画 — 默认 mount 立即 forward
//   会导致排在 stats_page 末尾的 expense_by_asset 在 user 滚到它时
//   动画已播完。改为检测到 viewport 可见时再 forward,跟 monthly_trend
//   _AnimatedBarChart 同样的入场策略。
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

class ExpenseByAssetChart extends ConsumerStatefulWidget {
  const ExpenseByAssetChart({super.key});

  @override
  ConsumerState<ExpenseByAssetChart> createState() =>
      _ExpenseByAssetChartState();
}

class _ExpenseByAssetChartState extends ConsumerState<ExpenseByAssetChart> {
  // viewport-aware 触发(2026-10-15 D63.1):false → AnimatedPieChart.play=false 不 forward
  //   true → 触发动画(用 _appeared 防重)
  bool _appeared = false;
  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollPos = Scrollable.maybeOf(context)?.position;
        _scrollPos?.addListener(_checkInView);
        _checkInView();
      }
    });
  }

  void _checkInView() {
    if (_appeared) return;
    final ctx = _chartKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      setState(() => _appeared = true);
      return;
    }
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null) return;
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      setState(() => _appeared = true);
    }
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    // 左侧圆环(viewport-aware 触发入场动画)
                    SizedBox(
                      key: _chartKey,
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
                            // D63.1:viewport-aware,_appeared=true 时才 forward 动画
                            play: _appeared,
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
