// lib/features/stats/ui/widgets/range_tabs.dart
// 时间范围选择 —— 2 段自定义 tab(本月 / 本年)+ 末尾清除按钮
// 整段 = tap target:每段点哪都弹对应 sheet,选过的具体月份/年份直接显示在 label 上
//
// 2026-10-11 redesign:去 "全部" 段。理由:
//   - "全部" 是个隐式默认状态(没筛选条件时就是全部),显式放在 tab 里冗余
//   - 删了之后 2 个 Expanded 自然变宽,长 label 不再触发 scaleDown
//   - 复位行为用末尾的"清除"图标按钮表达:custom 不为空且不等于当前时启用,
//     点击同时清 month/year 筛选并把 range 拉回 thisMonth
//
// 2026-10-12 pill 滑动动画 (commit 62):
//   - 之前每个 segment 自己 AnimatedContainer 背景各自 fade,切 tab 时两边的
//     bg 同时淡入/淡出,过渡"破碎"
//   - 改成 Stack + AnimatedPositioned 单 pill:选中态是同 1 个 pill,切 tab 时
//     pill left 在两 segment 之间水平滑动 + bg color 不变(pill 已经在那了)
//   - pill 走 AppMotion.fast(240ms aquaIn),Sweep 风格前快后慢
//
// 整段 tap 行为(本月/本年 mirror):
//   - 已在该段 → 弹对应 picker sheet(改月/年 / 回本月/本年)
//   - 在另一段 → 只切到该段视图,不弹 picker(避免"我只是想看本年"被强塞 picker)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/haptics/app_haptics.dart';
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
    final customYear = ref.watch(statsCustomYearProvider);
    final isThisMonth = range == StatsRange.thisMonth;
    final isThisYear = range == StatsRange.thisYear;
    final now = DateTime.now();

    // 本月段 label:
    //   custom == null                          → "本月"
    //   custom 跟当前月(年/月)一致                → "本月"(避免"回到本月" 后还
    //                                              显示成 "2026 年 10 月"的诡异感)
    //   custom 是其他月                          → "X 年 X 月"
    final monthLabel = isThisMonth
        ? (custom == null ||
                  (custom.year == now.year && custom.month == now.month)
              ? '本月'
              : '${custom.year} 年 ${custom.month} 月')
        : '本月';

    // 本年段 label:同 monthLabel 对称归一化
    //   customYear == null         → "本年"
    //   customYear == 当前年        → "本年"
    //   customYear 是其他年         → "X 年"
    final yearLabel = isThisYear
        ? (customYear == null || customYear == now.year
              ? '本年'
              : '$customYear 年')
        : '本年';

    // 清除按钮启用条件:custom 存在且 ≠ 当前(月份或年份维度任一为非当前都算)
    final hasMonthFilter =
        custom != null &&
        (custom.year != now.year || custom.month != now.month);
    final hasYearFilter = customYear != null && customYear != now.year;
    final filterActive = hasMonthFilter || hasYearFilter;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
        ),
        child: Row(
          children: [
            // ── commit 64 ── 共享 pill 滑动 (重写)
            //   v62 用 LayoutBuilder.c.maxWidth/2 算 segWidth 喂 AnimatedPositioned,
            //   user 截图反馈"左右都有 2-3px 留白 + 看起来不在居中",Stack + AnimatedPositioned
            //   跟内部 Row 的 render box 在 sub-pixel rounding 上对不齐。
            //   改 Positioned.fill + AnimatedAlign(widthFactor:0.5, heightFactor:1.0):
            //   pill 直接表达"Stack 半宽 × 全高",跟内部 Row 2 个 Expanded 用同一个 flex
            //   模型,几何 100% 一致,不存在亚像素 gap。AnimatedAlign 在 Alignment.centerLeft/
            //   centerRight 间 240ms aquaIn 插值,pill 滑动;切到任一 tab,pill 圆角跟
            //   container brLg 圆角完全重合(pill = Stack 满宽 × 满高)。
            Expanded(
              child: Stack(
                children: [
                  // 滑动 pill —— 在 InkWell 之下,ripple press 时 pill 短时被遮,抬起可见
                  //   widthFactor:0.5 → pill 始终是 Stack 宽度的 1/2(跟内部
                  //   Row 2 个 Expanded 的几何模型完全一致)
                  //   heightFactor:1.0 → pill 始终是 Stack 全高(跟 segment 等高,
                  //   圆角跟 container 的 brLg 在 Stack 边框完美重合)
                  Positioned.fill(
                    child: AnimatedAlign(
                      duration: AppMotion.fast,
                      curve: AppMotion.aquaIn,
                      alignment: isThisMonth
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      widthFactor: 0.5,
                      heightFactor: 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: AppRadius.brLg,
                        ),
                      ),
                    ),
                  ),
                  // 2 个 segment 本体(text + chevron,无背景,只是文字和 ripple)
                  Row(
                    children: [
                      Expanded(
                        child: _RangeSegment(
                          label: monthLabel,
                          selected: isThisMonth,
                          onTap: () {
                            if (range == StatsRange.thisMonth) {
                              // 已在该段 → 弹月份 picker,tap 反馈
                              AppHaptics.tap();
                              _pickMonth(context, ref, custom);
                            } else {
                              // 切到该段 → select 反馈
                              AppHaptics.select();
                              ref.read(statsRangeProvider.notifier).state =
                                  StatsRange.thisMonth;
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: _RangeSegment(
                          label: yearLabel,
                          selected: isThisYear,
                          onTap: () {
                            if (range == StatsRange.thisYear) {
                              AppHaptics.tap();
                              _pickYear(context, ref, customYear);
                            } else {
                              AppHaptics.select();
                              ref.read(statsRangeProvider.notifier).state =
                                  StatsRange.thisYear;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 清除按钮:filterActive 时启用,清 month + 清 year + 回到 thisMonth
            // 跟 2 个 segment 在同一 Row 同一 Container 内,视觉一体
            _ClearFilterButton(
              active: filterActive,
              onPressed: filterActive
                  ? () {
                      // 清筛选是个"重置"动作,success(中量)反馈
                      AppHaptics.success();
                      ref.read(statsCustomMonthProvider.notifier).state = null;
                      ref.read(statsCustomYearProvider.notifier).state = null;
                      ref.read(statsRangeProvider.notifier).state =
                          StatsRange.thisMonth;
                    }
                  : null,
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

  Future<void> _pickYear(
    BuildContext context,
    WidgetRef ref,
    int? currentYear,
  ) async {
    final now = DateTime.now();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => _YearPickerSheet(
        currentYear: currentYear ?? now.year,
        anchorYear: now.year,
      ),
    );
    if (picked != null) {
      ref.read(statsCustomYearProvider.notifier).state = picked;
    }
  }
}

/// 单段 tab —— 只是文字 + chevron,选中态背景由父级 Stack 的共享 pill 提供。
/// 2026-10-12 commit 62 重构:
///   - 之前自带 AnimatedContainer bg,跟当前共享 pill 重复(且会盖住 pill)
///   - 现在只剩 text + chevron,选区动画完全交给 Stack 上的 AnimatedPositioned
///   - 文字色:AnimatedDefaultTextStyle 240ms aquaIn
///   - 整段 scale 撤掉(选了 pill 滑动的视觉变化,不需要再额外 scale)
class _RangeSegment extends StatelessWidget {
  const _RangeSegment({
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
    // 整段 = tap target:InkWell.borderRadius 跟选区 pill 圆角保持一致
    // (都是 AppRadius.brLg),ripple 看起来自然地像 pill 内部的高光
    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Flexible(fit:loose) 给 Row 知道"这里能容纳的宽度",FittedBox 在
            // 该约束内做 scaleDown,长 label "2026 年 10 月" 自动缩到不溢出
            Flexible(
              fit: FlexFit.loose,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.fast,
                  curve: AppMotion.aquaIn,
                  style: TextStyle(
                    fontSize: 13,
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
            // chevron 提示"点了会下拉",跟 segment 行为一致
            // (切月/切年 / 切视角 chevron 视觉一致)
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: fg),
          ],
        ),
      ),
    );
  }
}

/// 末尾"清除筛选"图标按钮
///   - filterActive=true 时 onPressed 非 null,点击 reset month + year + range
///   - filterActive=false 时 disabled(灰色),存在但不响应
///   - always visible:不参与 Row 的 flex 分配,固定宽度,不随状态切换造成跳动
class _ClearFilterButton extends StatelessWidget {
  const _ClearFilterButton({required this.active, this.onPressed});

  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s1),
      child: SizedBox(
        width: 36,
        child: IconButton(
          // 2026-10-11 UAT:手机上没鼠标,tooltip 长按误触反而碍事,删掉。
          onPressed: onPressed,
          // visualDensity compact 缩掉默认 48x48 给 padding 让图标贴近 segment 圆角
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.close_rounded,
            size: 18,
            color: active
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outlineVariant,
          ),
        ),
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
                      onPressed: () => Navigator.pop(context, (
                        year: widget.anchorYear,
                        month: widget.anchorMonth,
                      )),
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
                  final isSelected =
                      _year == widget.currentYear && m == widget.currentMonth;
                  final disabled = _isFuture(_year, m);
                  return InkWell(
                    borderRadius: AppRadius.brMd,
                    onTap: disabled
                        ? null
                        : () => Navigator.pop(context, (year: _year, month: m)),
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

/// 年份选择 sheet —— 锚年 -5 到锚年的 6 年 grid + "回到本年"按钮
/// 比月份 picker 简单:没有"年 + 月"双维度,只显示 6 年(够普通人覆盖),
/// cellAspectRatio 比月份更宽(2.4 vs 1.6),因为年份只是 4 位数文字,占空更少
class _YearPickerSheet extends StatefulWidget {
  const _YearPickerSheet({required this.currentYear, required this.anchorYear});
  final int currentYear;
  final int anchorYear;

  @override
  State<_YearPickerSheet> createState() => _YearPickerSheetState();
}

class _YearPickerSheetState extends State<_YearPickerSheet> {
  // 显示最近 6 年:anchorYear-5 ~ anchorYear
  late List<int> _years;

  @override
  void initState() {
    super.initState();
    _years = List.generate(6, (i) => widget.anchorYear - 5 + i);
  }

  bool get _isOnAnchorYear => widget.currentYear == widget.anchorYear;

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
                    '选择年份',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  // 选过具体非本年时才显示"回到本年",按钮直观
                  if (!_isOnAnchorYear)
                    TextButton.icon(
                      icon: const Icon(Icons.today_rounded, size: 16),
                      label: const Text('回到本年'),
                      onPressed: () =>
                          Navigator.pop(context, widget.anchorYear),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            // 6 年 grid:横 3 列(anchorYear - 5 / -4 / -3 一行,anchorYear - 2 / -1 / anchorYear 一行)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                ),
                itemCount: _years.length,
                itemBuilder: (_, i) {
                  final y = _years[i];
                  final isSelected = y == widget.currentYear;
                  return InkWell(
                    borderRadius: AppRadius.brMd,
                    onTap: () => Navigator.pop(context, y),
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
                        '$y 年',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
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
