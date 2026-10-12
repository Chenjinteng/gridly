// lib/features/stats/ui/widgets/budget_overview_chart.dart
// 预算报表 widget —— stats 页本月维度专用(2026-10-12 commit 93 加)
//
// 视觉:
//   - 上半:大圆环(已花 / 总额度)+ 中心数字(剩余金额)+ 状态文字(总额度 / 已花 / 状态)
//   - 中部:共享池说明(已分配 X · 剩余 Y 给未配置)
//   - 下半:分类列表
//     - 已配置子额度:icon + name + 子额度 + 进度条 + 已花 / 超支
//     - 未配置子额度:icon + name + 共享池提示 + 已花
//
// 数据源:budgetOverviewForMonthProvider(commit 91 加),watch (year, month)
// 数据流:用户在 BudgetSheet(commit 92 加)改了配置,refreshAllData 触发本 widget 重建
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/constants/default_categories.dart';

class BudgetOverviewChart extends ConsumerWidget {
  const BudgetOverviewChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 本月维度专用:用 statsWindowProvider 的 start 拿到 year/month
    //   - commit 91 的 budgetOverviewForMonthProvider 用 BudgetMonthKey(year, month)
    //   - statsWindowProvider 是 statsRange=thisMonth 时的实际查询窗口,start.month 是 month
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

  /// 总已花(已配置 + 未配置,共享池视角)
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
        // 上半:圆环 + 数字 + 状态
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: _BudgetGauge(
                  progress: _progress,
                  color: _stateColor,
                  totalSpent: _totalSpent,
                  totalBudget: overview.totalBudget,
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
                          ? '¥${Formatters.amount((overview.totalBudget - _totalSpent).clamp(0, double.infinity))}'
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
        // 分类列表 —— commit 94 改:只显示已配置子额度的分类
        //   之前显示全部分类(15-17 个),user 反馈太多
        //   改 overview.configuredItems(只显示已配置的),
        //   未配置分类的共享池信息已在中部提示,不需要每个都列出来
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
            (item) => _CategoryBudgetItemRow(
              item: item,
              poolRemaining: overview.poolRemaining,
              totalBudget: overview.totalBudget,
            ),
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

/// 单分类预算行 —— 已配置的显示子额度 + 进度,未配置的显示共享池 + 已花
class _CategoryBudgetItemRow extends StatelessWidget {
  const _CategoryBudgetItemRow({
    required this.item,
    required this.poolRemaining,
    required this.totalBudget,
  });

  final CategoryBudgetSummary item;
  final double poolRemaining;
  final double totalBudget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(item.category.color);
    final spent = item.spent;
    final progress = item.amount > 0
        ? (spent / item.amount).clamp(0.0, 1.5)
        : 0.0;
    final over = item.amount > 0 && spent > item.amount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              CategoryIcons.map[item.category.icon] ?? Icons.category_rounded,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                    if (item.isConfigured)
                      Text(
                        '¥${Formatters.amount(item.amount, withUnit: false)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: over ? AppStatus.error : scheme.onSurface,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                if (item.isConfigured) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: AppGray.g200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        over ? AppStatus.error : AppBrand.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    over
                        ? '已花 ¥${Formatters.amount(spent, withUnit: false)} · 超支'
                        : '已花 ¥${Formatters.amount(spent, withUnit: false)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: over ? AppStatus.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Text(
                    totalBudget > 0
                        ? '共享池 ¥${Formatters.amount(poolRemaining, withUnit: false)} · 已花 ¥${Formatters.amount(spent, withUnit: false)}'
                        : '未设置总额度',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 简化版圆环(单色进度环) —— 用 PieChart 内置 fl_chart 自绘 stroke + clear 1.0°
/// 不引入 AnimatedPieChart,因为预算圆环只 1 段(已花 / 总额度),不需要扇区分色
/// 内部动画用 fl_chart PieChart 默认 swapAnimation
class _BudgetGauge extends StatelessWidget {
  const _BudgetGauge({
    required this.progress,
    required this.color,
    required this.totalSpent,
    required this.totalBudget,
  });

  final double progress; // 0-1
  final Color color;
  final double totalSpent;
  final double totalBudget;

  @override
  Widget build(BuildContext context) {
    final hasBudget = totalBudget > 0;
    final remaining = (totalBudget - totalSpent).clamp(0.0, double.infinity);

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            startDegreeOffset: -90,
            sectionsSpace: 0,
            centerSpaceRadius: 38,
            sections: [
              if (hasBudget) ...[
                PieChartSectionData(
                  value: progress.clamp(
                    0.001,
                    1.0,
                  ), // 0 时 PieChart 会跳到 noData,给个 0.001
                  color: color,
                  radius: 8,
                  showTitle: false,
                ),
                if (progress < 1.0)
                  PieChartSectionData(
                    value: 1.0 - progress,
                    color: AppGray.g200,
                    radius: 8,
                    showTitle: false,
                  ),
              ] else
                PieChartSectionData(
                  value: 1.0,
                  color: AppGray.g200,
                  radius: 8,
                  showTitle: false,
                ),
            ],
          ),
          duration: const Duration(milliseconds: 800),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasBudget)
              Text(
                '¥${Formatters.amount(remaining, withUnit: false)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              )
            else
              const Text(
                '—',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppGray.g400,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              hasBudget ? '剩余' : '未设置',
              style: const TextStyle(fontSize: 10, color: AppGray.g600),
            ),
          ],
        ),
      ],
    );
  }
}
