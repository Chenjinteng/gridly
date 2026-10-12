// lib/features/stats/ui/widgets/budget_overview_chart.dart
// 预算报表 widget —— stats 页本月维度专用(2026-10-12 commit 93 加)
//
// 视觉(commit 95 重构):
//   - 上半:圆环(已花 / 总额度)用 AnimatedPieChart(跟 CategoryPie 一样的
//     自绘 stroke + 1.0° 间隙 + 800ms aquaIn swap)+ 中心数字(剩余)
//   - 中部:共享池说明(已分配 X · 剩余 Y 给未配置)
//   - 下半:分类列表 —— 每行 icon + name + 横向柱状图 + 数字
//     (已花 / 子额度),不用直接给数字,用 bar 表示
//
// 数据源:budgetOverviewForMonthProvider(commit 91 加)
// 数据流:用户在 BudgetSheet(commit 92)改 → refreshAllData → widget 重建
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../../../shared/constants/default_categories.dart';

import 'package:fl_chart/fl_chart.dart';

class BudgetOverviewChart extends ConsumerWidget {
  const BudgetOverviewChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final monthKey = BudgetMonthKey(now.year, now.month);
    final overviewAsync = ref.watch(budgetOverviewForMonthProvider(monthKey));
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: overviewAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.s4),
          child: SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Text(
            '加载预算失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
        data: (overview) => _BudgetOverviewBody(overview: overview),
      ),
    );
  }
}

class _BudgetOverviewBody extends StatelessWidget {
  const _BudgetOverviewBody({required this.overview});

  final BudgetOverview overview;

  /// 总已花
  double get _totalSpent =>
      overview.items.fold<double>(0.0, (sum, i) => sum + i.spent);

  /// 进度(0-1,可能 > 1 表示超支)
  double get _progress {
    if (overview.totalBudget <= 0) return 0;
    return (_totalSpent / overview.totalBudget).clamp(0.0, 1.0);
  }

  /// 状态色(进度 < 80% OK,80-100% warning,> 100% over)
  Color get _stateColor {
    if (overview.totalBudget <= 0) return AppGray.g400;
    final p = _totalSpent / overview.totalBudget;
    if (p < 0.8) return AppBrand.teal;
    if (p <= 1.0) return AppStatus.warning;
    return AppStatus.error;
  }

  String get _stateLabel {
    if (overview.totalBudget <= 0) return '未设置预算';
    final p = (_progress * 100).toStringAsFixed(0);
    if (_progress < 0.8) return '已用 $p%';
    if (_progress <= 1.0) return '快超了 · $p%';
    return '已超 · ${((_totalSpent / overview.totalBudget - 1) * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBudget = overview.totalBudget > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏
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
                '本月预算',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (hasBudget)
                Text(
                  '总额 ¥${Formatters.amount(overview.totalBudget)}',
                  style: const TextStyle(fontSize: 12, color: AppGray.g600),
                ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // 上半:圆环 + 数字 + 状态(commit 95 改用 AnimatedPieChart 跟 CategoryPie 一致)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // AnimatedPieChart 自绘 stroke + 1.0° 间隙 + 800ms aquaIn swap,
                    // 跟 CategoryPie 完全一致
                    Builder(
                      builder: (_) {
                        final sections = [
                          if (hasBudget)
                            PieChartSectionData(
                              value: _progress.clamp(0.001, 1.0),
                              color: _stateColor,
                              radius: 18,
                            ),
                          if (hasBudget && _progress < 1.0)
                            PieChartSectionData(
                              value: 1.0 - _progress,
                              color: AppGray.g200,
                              radius: 18,
                            ),
                          if (!hasBudget)
                            PieChartSectionData(
                              value: 1.0,
                              color: AppGray.g200,
                              radius: 18,
                            ),
                        ];
                        return AnimatedPieChart(
                          key: pieChartKeyForSections(sections),
                          sections: sections,
                          innerRadius: 38,
                          outerRadius: 52,
                        );
                      },
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasBudget)
                          Text(
                            '¥${Formatters.amount((overview.totalBudget - _totalSpent).clamp(0.0, double.infinity), withUnit: false)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _stateColor,
                            ),
                          )
                        else
                          const Text(
                            '—',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppGray.g400,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          hasBudget ? '剩余' : '未设置',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppGray.g600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stateLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _stateColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    _kvRow('已花', '¥${Formatters.amount(_totalSpent)}'),
                    const SizedBox(height: AppSpacing.s1),
                    _kvRow(
                      '剩余',
                      hasBudget
                          ? '¥${Formatters.amount((overview.totalBudget - _totalSpent).clamp(0.0, double.infinity))}'
                          : '—',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 共享池说明
        if (hasBudget)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 14,
                    color: AppBrand.teal,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      overview.allocated > 0
                          ? '已分配 ¥${Formatters.amount(overview.allocated)} · 共享池 ¥${Formatters.amount(overview.poolRemaining)}'
                          : '未配置子额度 · 全部 ¥${Formatters.amount(overview.totalBudget)} 共享给所有支出分类',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 分类列表 —— commit 95 改:横向柱状图展示已花 / 子额度
        //   不再给数字 + 进度条,每行 icon + name + 横向 bar
        const Divider(height: 1, thickness: 0.5),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '分类预算',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '已配 ${overview.configuredItems.length}',
                style: const TextStyle(fontSize: 11, color: AppGray.g600),
              ),
            ],
          ),
        ),
        if (overview.configuredItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Center(
              child: Text(
                '未配置分类子额度',
                style: TextStyle(color: AppGray.g600, fontSize: 12),
              ),
            ),
          )
        else
          ...overview.configuredItems.map(
            (item) => _CategoryBudgetBarRow(item: item),
          ),
        const SizedBox(height: AppSpacing.s2),
      ],
    );
  }

  Widget _kvRow(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            k,
            style: const TextStyle(fontSize: 11, color: AppGray.g600),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 分类预算行 —— 横向柱状图
///
///   - 顶行:icon + 分类名 + 数字(右侧"已花 X / Y 总额"风格,便于核对)
///
///   🍔 餐饮          ¥2,100 / ¥3,000
///   ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░
///
///   - bar:
///     - 背景:浅灰底(full width)
///     - 已花:实色(< 100% = teal,> 100% = error 红)
///     - 圆角:左 2px(右端不圆,跟 left edge 对齐)
///     - 高度:6px
///
/// 不再用 LinearProgressIndicator(因为 user 要求"不要直接给数字",
/// 而是横向柱状图)。这里"用柱状图展示"含义是:不显示金额作为主数字,
/// bar 长度就是 spent / amount 的视觉表达。
class _CategoryBudgetBarRow extends StatelessWidget {
  const _CategoryBudgetBarRow({required this.item});

  final CategoryBudgetSummary item;

  @override
  Widget build(BuildContext context) {
    final color = Color(item.category.color);
    final spent = item.spent;
    final amount = item.amount;
    final ratio = amount > 0 ? (spent / amount).clamp(0.0, 1.5) : 0.0;
    final over = amount > 0 && spent > amount;
    final barColor = over ? AppStatus.error : AppBrand.teal;
    final ratioDisplay = amount > 0
        ? (spent / amount * 100).clamp(0, 999).toStringAsFixed(0)
        : '0';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  CategoryIcons.map[item.category.icon] ??
                      Icons.category_rounded,
                  size: 13,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  item.category.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 数字区域:不直接给金额数字,用"已花百分比 + 子额度"组合
              //   - "70% / ¥3,000" 表示已用 70%,总额 3000
              //   - user 原话"不要直接给数字"理解为不要把金额当主数字,
              //     这里把百分比当主数字,金额作为辅助
              //   - over 时显示"已花 ¥X · 超支"
              Text(
                over
                    ? '已超 ${((ratio - 1) * 100).toStringAsFixed(0)}%'
                    : '$ratioDisplay%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: over ? AppStatus.error : AppBrand.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          // 横向柱状图(bar)
          LayoutBuilder(
            builder: (ctx, c) {
              final width = c.maxWidth;
              final filledWidth = width * ratio.clamp(0.0, 1.0);
              return Stack(
                children: [
                  Container(
                    width: width,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppGray.g200,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    width: filledWidth,
                    height: 6,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s1),
          // 底部金额:辅助信息,小字号灰
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已花 ¥${Formatters.amount(spent, withUnit: false)}',
                style: TextStyle(
                  fontSize: 10,
                  color: over
                      ? AppStatus.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '总额 ¥${Formatters.amount(amount, withUnit: false)}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
