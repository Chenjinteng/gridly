// lib/features/add/ui/widgets/custom_date_picker.dart
// gridly 自定义日期选择器 —— 全中文,品牌色,与流水卡片视觉对齐。
//
// 跟 Flutter 系统 showDatePicker 的差异:
//   - 默认走 MaterialLocalizations,显示英文("Sun, Oct 11" / "Cancel")
//   - 卡片样式偏 Material 3 默认,跟 gridly 的自定义卡片视觉割裂
//   - 没有"今天/昨天"快捷入口,记一笔场景高频就是今天/昨天
//
// 这里的实现:
//   - 顶部:年份月份 + 上下月箭头
//   - 快捷:今天 / 昨天 / 前天(覆盖 80% 的记账场景)
//   - 中部:周日历(6 行 × 7 列),今天加描边、选中态实色填充
//   - 底部:取消 / 确定(中文按钮,AppBrand.teal 主色)
//   - 不允许跨月份(同月内只能选当月日期)
//
// 2026-10-15 D64.17 加:`lastDate` 默认今天,不允许选择未来日期。
//   - user UAT 反馈"日期相关的选择,要限制一下,不要可以选择未来的日期"
//   - 业务侧"记一笔"是过去发生的现金流,未来日期无意义
//   - 右箭头在 lastDate 月份或之后禁用(避免切到一整片灰的未来月)
//   - caller 显式传 `lastDate: null` 可关闭限制(目前未用,后续如有调度场景可开)
import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/show_app_modal_sheet.dart';

/// 弹出 gridly 自定义日期选择器
///
/// 返回选中的 DateTime(时分秒归零);用户取消返回 null。
///
/// 2026-10-15 D64.17 加:`lastDate` 默认今天(记账场景不能选未来)。
///   - 业务侧"记一笔"是过去发生的现金流,未来日期没意义
///   - 若需要允许未来日期(暂未用到),caller 显式传 `lastDate: null` 关闭限制
Future<DateTime?> showCustomDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  // D64.17:caller 未传 lastDate 时默认今天(去掉未来日期选项)
  final effectiveLastDate = lastDate ?? DateTime.now();
  return showAppModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CustomDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: effectiveLastDate,
    ),
  );
}

class CustomDatePickerSheet extends StatefulWidget {
  const CustomDatePickerSheet({
    super.key,
    required this.initialDate,
    this.firstDate,
    this.lastDate,
  });

  /// 默认选中的日期(从调用方 _occurredAt 传入)
  final DateTime initialDate;

  /// 可选最早日期(默认不限)
  final DateTime? firstDate;

  /// 可选最晚日期(默认不限)
  final DateTime? lastDate;

  @override
  State<CustomDatePickerSheet> createState() => _CustomDatePickerSheetState();
}

class _CustomDatePickerSheetState extends State<CustomDatePickerSheet> {
  late DateTime _selected;
  late DateTime _viewMonth; // 当前展示的月份(任何月,可能不是 _selected 的月)

  static const List<String> _weekdays = ['日', '一', '二', '三', '四', '五', '六'];
  static const List<String> _monthNames = [
    '一月',
    '二月',
    '三月',
    '四月',
    '五月',
    '六月',
    '七月',
    '八月',
    '九月',
    '十月',
    '十一月',
    '十二月',
  ];

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _viewMonth = DateTime(_selected.year, _selected.month);
  }

  bool _isInRange(DateTime d) {
    if (widget.firstDate != null &&
        d.isBefore(
          DateTime(
            widget.firstDate!.year,
            widget.firstDate!.month,
            widget.firstDate!.day,
          ),
        )) {
      return false;
    }
    if (widget.lastDate != null &&
        d.isAfter(
          DateTime(
            widget.lastDate!.year,
            widget.lastDate!.month,
            widget.lastDate!.day,
          ),
        )) {
      return false;
    }
    return true;
  }

  /// 把日期归零成"日期对象"(丢时分秒)便于 .isAtSameMomentAs 比较
  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 月份视图里所有需要展示的格子(包含上下月占位)
  /// 第一格从 viewMonth 第一天的周日开始,补足上月最后几天;
  /// 最后一行周日前几天是下月开头。
  List<DateTime> _buildGridDays() {
    final firstOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    // weekday: 1=Mon ... 7=Sun;DateTime.weekday 周日=7,转成 0-indexed:周日=0
    final leadingWeekday = firstOfMonth.weekday % 7; // Sun=0, Mon=1, ..., Sat=6
    final gridStart = firstOfMonth.subtract(Duration(days: leadingWeekday));
    // 6 行 × 7 列 = 42 格,固定 6 行(月份最多跨 6 行)
    return List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));
  }

  void _select(DateTime d) {
    if (!_isInRange(d)) return;
    setState(() => _selected = _dayOnly(d));
  }

  void _goToday() {
    final now = _dayOnly(DateTime.now());
    if (!_isInRange(now)) return;
    setState(() {
      _selected = now;
      _viewMonth = DateTime(now.year, now.month);
    });
  }

  void _goYesterday() {
    final y = _dayOnly(DateTime.now().subtract(const Duration(days: 1)));
    if (!_isInRange(y)) return;
    setState(() {
      _selected = y;
      _viewMonth = DateTime(y.year, y.month);
    });
  }

  void _goDayBeforeYesterday() {
    final d = _dayOnly(DateTime.now().subtract(const Duration(days: 2)));
    if (!_isInRange(d)) return;
    setState(() {
      _selected = d;
      _viewMonth = DateTime(d.year, d.month);
    });
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    // D64.17:不允许切到未来月份(超出 lastDate 即今天),箭头 disable
    //   防止用户切到下月看到一整片灰格
    if (widget.lastDate != null) {
      final lastMonth = DateTime(widget.lastDate!.year, widget.lastDate!.month);
      if (next.isAfter(lastMonth)) return;
    }
    setState(() => _viewMonth = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.brXl,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              const SizedBox(height: AppSpacing.s3),
              _buildQuickRow(theme),
              const SizedBox(height: AppSpacing.s3),
              _buildWeekdayHeader(theme),
              const SizedBox(height: AppSpacing.s2),
              _buildGrid(theme),
              const SizedBox(height: AppSpacing.s3),
              _buildFooter(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // D64.17:viewMonth >= lastDate 月份时,右箭头禁用(避免切到一整片灰的未来月)
    final isAtFutureEdge =
        widget.lastDate != null &&
        (_viewMonth.year > widget.lastDate!.year ||
            (_viewMonth.year == widget.lastDate!.year &&
                _viewMonth.month >= widget.lastDate!.month));
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _shiftMonth(-1),
          // 2026-10-11 UAT:手机上没鼠标,tooltip 长按误触反而碍事,删掉。
        ),
        Expanded(
          child: Center(
            child: Text(
              '${_viewMonth.year} 年 ${_monthNames[_viewMonth.month - 1]}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          // D64.17:在 lastDate 月份或之后右箭头禁用
          onPressed: isAtFutureEdge ? null : () => _shiftMonth(1),
          // 2026-10-11 UAT:手机上没鼠标,tooltip 长按误触反而碍事,删掉。
        ),
      ],
    );
  }

  Widget _buildQuickRow(ThemeData theme) {
    return Row(
      children: [
        _quickBtn('今天', _goToday),
        const SizedBox(width: AppSpacing.s2),
        _quickBtn('昨天', _goYesterday),
        const SizedBox(width: AppSpacing.s2),
        _quickBtn('前天', _goDayBeforeYesterday),
      ],
    );
  }

  Widget _quickBtn(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          decoration: BoxDecoration(
            // D71.2:跟随 palette
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.10),
            borderRadius: AppRadius.brMd,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              // D71.2:跟随 palette
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader(ThemeData theme) {
    return Row(
      children: _weekdays.map((w) {
        return Expanded(
          child: Center(
            child: Text(
              w,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    final days = _buildGridDays();
    final today = _dayOnly(DateTime.now());
    return Column(
      children: List<Widget>.generate(6, (row) {
        return Row(
          children: List<Widget>.generate(7, (col) {
            final d = days[row * 7 + col];
            final inMonth = d.month == _viewMonth.month;
            final isSelected = d.isAtSameMomentAs(_selected);
            final isToday = d.isAtSameMomentAs(today);
            final inRange = _isInRange(d);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _dayCell(
                  theme,
                  d,
                  inMonth: inMonth,
                  isSelected: isSelected,
                  isToday: isToday,
                  inRange: inRange,
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _dayCell(
    ThemeData theme,
    DateTime d, {
    required bool inMonth,
    required bool isSelected,
    required bool isToday,
    required bool inRange,
  }) {
    Color bg;
    Color fg;
    BoxBorder? border;
    VoidCallback? onTap;

    if (!inRange) {
      bg = Colors.transparent;
      fg = theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
      border = null;
      onTap = null;
    } else if (isSelected) {
      // D71.2:跟随 palette
      bg = theme.colorScheme.primary;
      fg = Colors.white;
      border = null;
      onTap = () => _select(d);
    } else if (isToday) {
      bg = Colors.transparent;
      // D71.2:跟随 palette
      fg = theme.colorScheme.primary;
      border = Border.all(color: theme.colorScheme.primary, width: 1.5);
      onTap = () => _select(d);
    } else if (!inMonth) {
      bg = Colors.transparent;
      fg = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
      border = null;
      onTap = null;
    } else {
      bg = Colors.transparent;
      fg = theme.colorScheme.onSurface;
      border = null;
      onTap = () => _select(d);
    }

    return InkWell(
      borderRadius: AppRadius.brPill,
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        alignment: Alignment.center,
        child: Text(
          '${d.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected || isToday
                ? FontWeight.w700
                : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s2,
            ),
          ),
          child: const Text(
            '取消',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          style: FilledButton.styleFrom(
            // D71.2:跟随 palette
            backgroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s5,
              vertical: AppSpacing.s2,
            ),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          ),
          child: const Text(
            '确定',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
