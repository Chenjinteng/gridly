// lib/features/stats/ui/widgets/top_expenses.dart
// 报表页 Top 10 区域 —— 2 个 Tab 切换,tab 结构随时间窗变。
//
// 单笔:每行 = 分类图标 + 名字 + 日期 + 金额(降序前 10)
// 金额:每行 = 分类图标 + 名字 + 「均价 ¥X · 占比%」+ 右侧大号「¥合计」+ 其下小号「N 笔」
// 笔数:每行 = 分类图标 + 名字 + 「均价 ¥X · 占比%」+ 右侧大号「N 笔」+ 其下小号「¥合计」
//
// 2026-10-15 D64.3 改:容器改用 `ChartCard`,TabBar 放 trailing,showDivider=false
//
// 2026-10-21 D64.90 / D64.92 改:tab 结构 + 行布局重做
//   D64.90 —— 年视角第一个 tab 从「单笔」换成「笔数」
//     动机(user UAT):"切换到全年视角的话,TOP10 的单笔支出就基本是每个月的房租,
//       12 个月的话 top10 被它霸屏了,有用的就只有 top10 分类"
//     → 年视角下"单笔"排序键(单笔金额)被固定开销占满,信息密度归零
//   D64.92 —— 拆成「金额」「笔数」两个 tab,行信息完全一致,只是排序键不同
//     动机(user UAT):"居然这个一排序之后,房租的不在 top10 了"
//     → 房租是"少而大"(39 笔占 20.8% 的钱),正餐是"多而小"(392 笔占 9.4%)
//       两个维度都是真相,只按一个排就会丢掉另一半 → 两个 tab 都给,切 tab = 换排序
//
//   最终 tab 结构:
//     本月:单笔 / 金额(「单笔」保留 —— 一个月里房租就一条,信息密度正常)
//     本年:金额 / 笔数(「单笔」在年视角被固定开销霸屏,去掉)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';
import '../../application/stats_providers.dart';

class TopExpenses extends ConsumerWidget {
  const TopExpenses({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // D64.90/D64.92:年视角 = 金额 / 笔数;月视角 = 单笔 / 金额
    final isYear = ref.watch(statsRangeProvider) == StatsRange.thisYear;
    // 2026-10-15 D64.4 修:DefaultTabController 必须包整个 widget,
    // 这样 trailing 里的 TabBar 跟 child 里的 TabBarView 都在
    // DefaultTabController 子树里,共享同一个 controller。
    // 之前 D64.3 改成 ChartCard 之后,DefaultTabController 放在 child 里,
    // 但 trailing 的 TabBar 在外面,Flutter 报:
    //   "No TabController for TabBar"
    return DefaultTabController(
      length: 2,
      child: ChartCard(
        title: 'Top 10 支出',
        showDivider: false,
        trailing: SizedBox(
          height: 36,
          child: TabBar(
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.label,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              Tab(text: isYear ? '金额' : '单笔'),
              Tab(text: isYear ? '笔数' : '金额'),
            ],
            // D71.5.5:labelColor / indicatorColor / unselectedLabelColor
            //  都去掉,完全由 app_theme.dart 的 tabBarTheme 接管
            //   (palette.accent / scheme.onSurfaceVariant),跟随 palette
            dividerHeight: 0,
          ),
        ),
        child: SizedBox(
          height: 520,
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: isYear
                ? const [_TopByAmount(), _TopByCount()]
                : const [_TopList(), _TopByAmount()],
          ),
        ),
      ),
    );
  }
}

class _TopList extends ConsumerWidget {
  const _TopList();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(topExpensesProvider);
    final cats =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return topAsync.when(
      data: (txs) {
        if (txs.isEmpty) {
          return Column(
            children: List.generate(
              _slotCount,
              (i) => _EmptyRow(height: _rowHeight, slot: i + 1),
            ),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < txs.length && i < _slotCount; i++)
              _DataRow(
                rank: i + 1,
                height: _rowHeight,
                color: _colorForCategory(txs[i].categoryId, cats),
                iconKey: _iconKeyForCategory(txs[i].categoryId, cats),
                primary: _categoryNameForCategory(txs[i].categoryId, cats),
                secondary: txs[i].note,
                trailing: '¥${Formatters.amount(txs[i].amount)}',
                trailingSub: DateFormat('M月d日').format(txs[i].occurredAt),
                trailingColor: AppStatus.error,
              ),
            // 不足 10 条,补空行 —— 浅灰显示 "#N" 占位序号
            for (int i = txs.length; i < _slotCount; i++)
              _EmptyRow(height: _rowHeight, slot: i + 1),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// 2026-10-21 D64.90 加 / D64.92 重做:「笔数」tab
///
/// 每行 = 分类图标 + 分类名 + 「均价 ¥X · 占比%」+ 右侧大号「N 笔」+ 其下小号「¥合计」
/// 排序:笔数降序(笔数相同按合计金额降序,再按名称稳定)
///
/// **为什么均价/合计分开放(user 担心副标题太长显示不全)**:
///   副标题如果写成「均价 ¥43 · 合计 ¥16,992.33」,窄屏(实测 320/360/390 全部)
///   会被 ellipsis 截断 —— 截掉的正好是金额,信息失真。
///   拆开后:副标题放「均价 ¥X · 占比%」,合计挪到右侧大号「N 笔」下面的小字位
///   —— 那里本来就是放小字的(跟「单笔」tab 的日期同一个位置)。
///   金额类文字再用 FittedBox(scaleDown) 兜底:放不下就缩小,永不截断。
class _TopByCount extends ConsumerWidget {
  const _TopByCount();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(expenseCategoryStatsProvider);
    final cats =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return statsAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        final top = sortStatsByCount(data).take(_slotCount).toList();
        if (top.isEmpty) {
          return Column(
            children: List.generate(
              _slotCount,
              (i) => _EmptyRow(height: _rowHeight, slot: i + 1),
            ),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < top.length && i < _slotCount; i++)
              _DataRow(
                rank: i + 1,
                height: _rowHeight,
                color: Color(top[i].color),
                iconKey: _iconKeyForCategory(top[i].categoryId, cats),
                primary: top[i].name,
                secondary:
                    '均价 ¥${_yuanLabel(top[i].avg)} · ${_pct(top[i].amount, total)}',
                trailing: '${top[i].count} 笔',
                trailingSub:
                    '¥${_yuanLabel(top[i].amount)}',
                trailingColor: Color(top[i].color),
                scaleDownTexts: true,
              ),
            // 不足 10 条,补空行 —— 浅灰显示 "#N" 占位序号
            for (int i = top.length; i < _slotCount; i++)
              _EmptyRow(height: _rowHeight, slot: i + 1),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

/// 金额显示:≥1 元取整(「一顿正餐 43 块」比「43.35 块」好读),
/// <1 元保留小数(取整会把 0.5 元显示成 1 元)
/// 均价和合计共用 —— 一行里两个数字精度一致,看着才不别扭
String _yuanLabel(double v) {
  if (v >= 1) {
    return Formatters.amount(v.roundToDouble(), trimTrailingZeros: true);
  }
  return Formatters.amount(v, trimTrailingZeros: true);
}

/// 占比(整数 %)
String _pct(double amount, double total) {
  if (total <= 0) return '0%';
  return '${(amount / total * 100).toStringAsFixed(0)}%';
}

/// 2026-10-21 D64.92:「金额」tab(按合计金额降序)
///
/// 每行 = 分类图标 + 分类名 + 「均价 ¥X · 占比%」+ 右侧大号「¥合计」+ 其下小号「N 笔」
/// 跟「笔数」tab **行信息完全一致**,只是排序键不同(切 tab = 换排序)。
/// 动机(user UAT):"居然这个一排序之后,房租的不在 top10 了"
///   → 房租是"少而大"(39 笔占 20.8% 的钱),正餐是"多而小"(392 笔占 9.4%)
///   → 金额 tab 让房租回到第 1,笔数 tab 让正餐第 1,两个真相都在
class _TopByAmount extends ConsumerWidget {
  const _TopByAmount();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(expenseCategoryStatsProvider);
    final cats =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return statsAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        // provider 已按金额降序排好
        final top = data.take(_slotCount).toList();
        if (top.isEmpty) {
          return Column(
            children: List.generate(
              _slotCount,
              (i) => _EmptyRow(height: _rowHeight, slot: i + 1),
            ),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < top.length && i < _slotCount; i++)
              _DataRow(
                rank: i + 1,
                height: _rowHeight,
                color: Color(top[i].color),
                iconKey: _iconKeyForCategory(top[i].categoryId, cats),
                primary: top[i].name,
                secondary:
                    '均价 ¥${_yuanLabel(top[i].avg)} · ${_pct(top[i].amount, total)}',
                trailing:
                    '¥${_yuanLabel(top[i].amount)}',
                trailingSub: '${top[i].count} 笔',
                trailingColor: Color(top[i].color),
                scaleDownTexts: true,
              ),
            // 不足 10 条,补空行 —— 浅灰显示 "#N" 占位序号
            for (int i = top.length; i < _slotCount; i++)
              _EmptyRow(height: _rowHeight, slot: i + 1),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }
}

// 固定高度的数据行(单笔 / 分类共用)
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.rank,
    required this.height,
    required this.color,
    required this.iconKey,
    required this.primary,
    this.secondary,
    required this.trailing,
    this.trailingSub,
    required this.trailingColor,
    this.scaleDownTexts = false,
  });
  // 1-based slot 序号(#1 #2 ... #10)
  // 跟 _EmptyRow 渲染同样的 "#N" 文案,数据行 + 占位空行视觉上前后行
  // 序号竖列对齐,UI 一致性
  final int rank;
  final double height;
  final Color color;
  final String iconKey;
  final String primary;
  final String? secondary;
  final String trailing;
  final String? trailingSub;
  final Color trailingColor;

  /// 副标题 + 右侧小字:放不下时自动缩小而不是截断(见 _fit)
  final bool scaleDownTexts;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppGray.g100, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        child: Row(
          children: [
            // 序号列:跟 _EmptyRow 的 slot 同字面+同色,数据/占位过渡时列对齐
            SizedBox(
              width: 26,
              child: Text(
                '#$rank',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppGray.g400,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.brXs,
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Icon(
                CategoryIcons.map[iconKey] ?? Icons.category_rounded,
                color: color,
                size: 14,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primary,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary != null && secondary!.isNotEmpty)
                    _fit(
                      scaleDownTexts,
                      Alignment.centerLeft,
                      Text(
                        secondary!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppGray.g600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: trailingColor,
                  ),
                ),
                if (trailingSub != null && trailingSub!.isNotEmpty)
                  _fit(
                    scaleDownTexts,
                    Alignment.centerRight,
                    Text(
                      trailingSub!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppGray.g600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 放不下时**自动缩小**而不是截断
  ///
  /// 2026-10-21 D64.90:user 担心"均价/合计太长,金额显示不全"。
  /// 金额被 ellipsis 截掉是信息失真(用户看到 "合计 ¥16,9…" 会误判),
  /// 所以金额类文字改成放不下就等比缩小 —— 永远完整显示。
  /// 只给「笔数」tab 用(它的副标题 + 右侧小字都是金额/数字);
  /// 「单笔」tab 的备注是自由文本,截断成省略号更合适,保持原样。
  static Widget _fit(bool scaleDown, Alignment alignment, Widget child) {
    if (!scaleDown) return child;
    return FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
  }
}

// 空行(占位,浅灰 "#N" 序号 + 顶部 0.5px 分隔线)
// 用途:数据不足 10 条时,补足行高,让卡片高度恒定,避免底部"留白"
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.height, required this.slot});
  final double height;
  final int slot; // 1-based
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppGray.g100, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '#$slot',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppGray.g400, // 浅灰,与数据行视觉区分
            ),
          ),
        ),
      ),
    );
  }
}

// 分类查找辅助(根据 categoryId 找 cat,fallback 默认)
Color _colorForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return Color(c.color);
  }
  return AppGray.g400;
}

String _iconKeyForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return c.icon;
  }
  return 'category';
}

String _categoryNameForCategory(int id, List<Category> cats) {
  for (final c in cats) {
    if (c.id == id) return c.name;
  }
  return '未分类';
}
