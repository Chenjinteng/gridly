// lib/features/stats/ui/widgets/range_tabs.dart
// 时间范围选择:3 段 SegmentedButton(本月 / 本年 / 全部)
// + 本月段联动月份 dropdown(选具体某月)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/stats_providers.dart';

class RangeTabs extends ConsumerWidget {
  const RangeTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(statsRangeProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<StatsRange>(
              segments: const [
                ButtonSegment(value: StatsRange.thisMonth, label: Text('本月')),
                ButtonSegment(value: StatsRange.thisYear, label: Text('本年')),
                ButtonSegment(value: StatsRange.all, label: Text('全部')),
              ],
              selected: {range},
              onSelectionChanged: (s) {
                final newRange = s.first;
                ref.read(statsRangeProvider.notifier).state = newRange;
                // 切到非本月段时清掉自定义月份,避免回去又跳到上次选月
                if (newRange != StatsRange.thisMonth) {
                  ref.read(statsCustomMonthProvider.notifier).state = null;
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          _MonthDropdown(enabled: range == StatsRange.thisMonth),
        ],
      ),
    );
  }
}

/// 月份 dropdown —— 仅本月段激活时可用,选完弹回 statsCustomMonthProvider
class _MonthDropdown extends ConsumerWidget {
  const _MonthDropdown({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(statsCustomMonthProvider);
    final now = DateTime.now();
    final active = custom != null;
    final label = custom == null
        ? '${now.month} 月'
        : '${custom.year} 年 ${custom.month} 月';
    return _MonthDropdownField(
      label: label,
      active: active,
      enabled: enabled,
      onTap: enabled ? () => _pickMonth(context, ref, custom) : null,
    );
  }

  Future<void> _pickMonth(
    BuildContext context,
    WidgetRef ref,
    ({int year, int month})? current,
  ) async {
    final now = DateTime.now();
    final picked = await showModalBottomSheet<({int year, int month})>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => _MonthPickerSheet(
        currentYear: current?.year ?? now.year,
        currentMonth: current?.month ?? now.month,
        anchorYear: now.year,
        anchorMonth: now.month,
      ),
    );
    if (picked != null) {
      ref.read(statsCustomMonthProvider.notifier).state = picked;
    }
  }
}

/// 月份选择 sheet —— 12 个月 grid + 翻年箭头
class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({
    required this.currentYear,
    required this.currentMonth,
    required this.anchorYear,
    required this.anchorMonth,
  });
  final int currentYear;
  final int currentMonth;
  final int anchorYear;
  final int anchorMonth;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.currentYear;
  }

  bool _isFuture(int year, int month) {
    if (year > widget.anchorYear) return true;
    if (year < widget.anchorYear) return false;
    return month > widget.anchorMonth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择月份',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            // 年份翻页
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _year > widget.anchorYear - 5
                        ? () => setState(() => _year--)
                        : null,
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '$_year 年',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _year < widget.anchorYear
                        ? () => setState(() => _year++)
                        : null,
                  ),
                ],
              ),
            ),
            // 12 月 grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: 12,
                itemBuilder: (_, i) {
                  final m = i + 1;
                  final isSelected = _year == widget.currentYear &&
                      m == widget.currentMonth;
                  final disabled = _isFuture(_year, m);
                  return InkWell(
                    borderRadius: AppRadius.brMd,
                    onTap: disabled
                        ? null
                        : () => Navigator.pop(
                              context,
                              (year: _year, month: m),
                            ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.15)
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.brMd,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$m 月',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: disabled
                              ? theme.colorScheme.outlineVariant
                              : (isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
          ],
        ),
      ),
    );
  }
}

/// 紧凑 dropdown 按钮 —— label + value + 箭头
class _MonthDropdownField extends StatelessWidget {
  const _MonthDropdownField({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = !enabled
        ? theme.colorScheme.surfaceContainerLow
        : active
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow;
    final fg = !enabled
        ? theme.colorScheme.outlineVariant
        : active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: AppRadius.brMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 16,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}