// lib/features/stats/ui/widgets/range_tabs.dart
// 时间范围选择 —— 3 段自定义 tab(本月 / 本年 / 全部)
// "本月" 段内嵌 chevron 弹月份 sheet,选过的具体月份直接显示在 label 上
// 不在 SegmentedButton 之外额外加 dropdown,保持 3 段紧凑
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
    final custom = ref.watch(statsCustomMonthProvider);
    final isThisMonth = range == StatsRange.thisMonth;

    // 本月段 label:选了具体月就显示"X 年 X 月",否则显示"本月"
    final monthLabel = isThisMonth
        ? (custom == null
            ? '本月'
            : '${custom.year} 年 ${custom.month} 月')
        : '本月';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
        ),
        child: Row(
          children: [
            Expanded(
              child: _RangeSegment(
                label: monthLabel,
                selected: isThisMonth,
                showChevron: true,
                onLabelTap: () {
                  ref.read(statsRangeProvider.notifier).state =
                      StatsRange.thisMonth;
                },
                onChevronTap: () => _pickMonth(context, ref, custom),
              ),
            ),
            Expanded(
              child: _RangeSegment(
                label: '本年',
                selected: range == StatsRange.thisYear,
                showChevron: false,
                onLabelTap: () {
                  ref.read(statsRangeProvider.notifier).state =
                      StatsRange.thisYear;
                  ref.read(statsCustomMonthProvider.notifier).state = null;
                },
              ),
            ),
            Expanded(
              child: _RangeSegment(
                label: '全部',
                selected: range == StatsRange.all,
                showChevron: false,
                onLabelTap: () {
                  ref.read(statsRangeProvider.notifier).state = StatsRange.all;
                  ref.read(statsCustomMonthProvider.notifier).state = null;
                },
              ),
            ),
          ],
        ),
      ),
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

/// 单段 tab —— 整体选中态背景,label 可点切到该段,chevron 可点弹月份 sheet
class _RangeSegment extends StatelessWidget {
  const _RangeSegment({
    required this.label,
    required this.selected,
    required this.showChevron,
    required this.onLabelTap,
    this.onChevronTap,
  });

  final String label;
  final bool selected;
  final bool showChevron;
  final VoidCallback onLabelTap;
  final VoidCallback? onChevronTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: AppRadius.brLg,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            borderRadius: AppRadius.brSm,
            onTap: onLabelTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          if (showChevron)
            InkWell(
              borderRadius: AppRadius.brSm,
              onTap: onChevronTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: AppSpacing.s1,
                ),
                child: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: fg,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 月份选择 sheet —— 12 个月 grid + 翻年箭头 + "回到本月"按钮
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

  bool get _isOnAnchorMonth =>
      widget.currentYear == widget.anchorYear &&
      widget.currentMonth == widget.anchorMonth;

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
                children: [
                  const Text(
                    '选择月份',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  // 仅当选过具体月份时,才显示"回到本月"
                  if (!_isOnAnchorMonth)
                    TextButton.icon(
                      icon: const Icon(Icons.today_rounded, size: 16),
                      label: const Text('回到本月'),
                      onPressed: () => Navigator.pop(
                        context,
                        (year: widget.anchorYear, month: widget.anchorMonth),
                      ),
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