// lib/features/stats/ui/widgets/stats_view_tabs.dart
// 报表视角切换 —— 3 段 tab(支出 / 收入 / 资产)
// 顶部层级,跟下方的"时间范围 tabs(本月/本年)"正交:这套切"看什么",
// 那套切"看多久"。
//
// 设计:跟 range_tabs 同款(整段 InkWell + 选中态背景 + 圆角 ripple),
//  简化掉 dropdown / picker / 清除按钮 —— 视角是离散 3 态,不需要。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/stats_providers.dart';

class StatsViewTabs extends ConsumerWidget {
  const StatsViewTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(statsViewProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Row(
          children: [
            Expanded(
              child: _ViewSegment(
                label: '支出',
                selected: view == StatsView.expense,
                onTap: () => ref
                    .read(statsViewProvider.notifier)
                    .state = StatsView.expense,
              ),
            ),
            Expanded(
              child: _ViewSegment(
                label: '收入',
                selected: view == StatsView.income,
                onTap: () => ref
                    .read(statsViewProvider.notifier)
                    .state = StatsView.income,
              ),
            ),
            Expanded(
              child: _ViewSegment(
                label: '资产',
                selected: view == StatsView.assets,
                onTap: () => ref
                    .read(statsViewProvider.notifier)
                    .state = StatsView.assets,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewSegment extends StatelessWidget {
  const _ViewSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: AppRadius.brLg,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: fg,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
