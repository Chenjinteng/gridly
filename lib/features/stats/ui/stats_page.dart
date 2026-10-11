// lib/features/stats/ui/stats_page.dart
// 报表:AppBar(报表 title + 视角 dropdown)→ 时间范围 tabs → 汇总 → 内容
//
// 视角选择放在 AppBar 右端(2026-10-11 UAT:\"不要增加一个 row,放在
// 与报表 title 同一级别即可,用下拉\"),不占 body 高度。下拉选完
// 后正文自动 switch,眼睛也不用离开页面顶部。
//
// 下拉刷新:广谱 invalidate 所有依赖 provider(流水 / 月度汇总 / 分类)
//
// 视角路由:
//   expense → CategoryPie + TopExpenses + MonthlyTrend
//   income  → IncomePie + MonthlyTrend
//   assets  → 占位(2026-10-11 资产功能预留)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import 'widgets/category_pie.dart';
import 'widgets/income_pie.dart';
import 'widgets/monthly_trend.dart';
import 'widgets/range_summary.dart';
import 'widgets/range_tabs.dart';
import 'widgets/top_expenses.dart';
import '../application/stats_providers.dart' hide MonthlyTrend;

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(statsViewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('报表'),
        actions: [
          // 视角下拉 —— 与 title 同一行(AppBar 右侧 actions)
          _ViewMenu(
            current: view,
            onChange: (v) =>
                ref.read(statsViewProvider.notifier).state = v,
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshAllData(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.s6),
          children: [
            // 时间范围(本月/本年) —— 现在是该页 body 的最顶
            const RangeTabs(),
            // 汇总(收入/支出/结余)— 三个视角共享(它是"窗口内总览")
            const RangeSummary(),
            const SizedBox(height: AppSpacing.s3),
            // 视角特定内容
            ..._viewContent(view),
          ],
        ),
      ),
    );
  }

  List<Widget> _viewContent(StatsView view) {
    switch (view) {
      case StatsView.expense:
        return const [
          CategoryPie(),
          SizedBox(height: AppSpacing.s3),
          TopExpenses(),
          SizedBox(height: AppSpacing.s3),
          MonthlyTrend(),
        ];
      case StatsView.income:
        return const [
          IncomePie(),
          SizedBox(height: AppSpacing.s3),
          MonthlyTrend(),
        ];
      case StatsView.assets:
        return const [_AssetsPlaceholder()];
    }
  }
}

/// AppBar 右侧的视角 dropdown
/// - 显示当前 view 文字 + expand_more icon(常驻可见)
/// - 点击弹出 3 项菜单,选中后 onChange 回调立刻更新 provider
/// - 这里不监听 widget 自身 rebuild 状态,current 是 build 参数,onChange
///   触发后父级 StatsPage 会因 watch 重新 build,current 自动同步
class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.current, required this.onChange});

  final StatsView current;
  final ValueChanged<StatsView> onChange;

  String get _currentLabel => switch (current) {
        StatsView.expense => '支出',
        StatsView.income => '收入',
        StatsView.assets => '资产',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// 2026-10-11 UAT:之前用系统 PopupMenuButton,Material 默认深色 item + 阴影,
  /// 跟 gridly UI 风格脱节。换成自定义 bottom sheet:
  ///   - 顶部 drag handle(跟日期 picker / 月份 picker 一致)
  ///   - 标题"选择视角"
  ///   - 3 行 item:选中行 brand 色背景 + check icon;未选中行主题色
  ///   - 圆角 AppRadius.brXl 顶部,跟其它 sheet 视觉一致
  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<StatsView>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _ViewPickerSheet(current: current, onPick: (v) {
        Navigator.pop(context, v);
      }),
    );
    if (picked != null && picked != current) {
      onChange(picked);
    }
  }
}

/// 视角选择底部 sheet
class _ViewPickerSheet extends StatelessWidget {
  const _ViewPickerSheet({required this.current, required this.onPick});

  final StatsView current;
  final ValueChanged<StatsView> onPick;

  // 视角 icon 跟 kind 颜色,跟 gridly 卡片视觉对齐
  static const _options = <(StatsView, String, IconData, Color)>[
    (StatsView.expense, '支出', Icons.arrow_outward_rounded, AppStatus.error),
    (StatsView.income, '收入', Icons.south_west_rounded, AppBrand.gold),
    (StatsView.assets, '资产', Icons.account_balance_wallet_rounded, AppBrand.teal),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  const Text(
                    '选择视角',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Column(
                children: [
                  for (final (view, label, icon, color) in _options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                      child: _ViewOption(
                        label: label,
                        icon: icon,
                        color: color,
                        selected: view == current,
                        onTap: () => onPick(view),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 视角选择行:icon + label + check(选中时)
class _ViewOption extends StatelessWidget {
  const _ViewOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // icon 块:kind 颜色 18% alpha 背景 + 全 icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: AppRadius.brMd,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetsPlaceholder extends StatelessWidget {
  const _AssetsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s6,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: AppGray.g400,
            ),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              '资产结构',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s2),
            const Text(
              '即将上线',
              style: TextStyle(fontSize: 13, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}
