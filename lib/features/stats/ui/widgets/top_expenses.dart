// lib/features/stats/ui/widgets/top_expenses.dart
// 报表页 Top 10 区域 —— 单笔 / 分类 两个 Tab 切换。
// 单笔:每行 = 分类图标 + 名字 + 日期 + 金额(降序前 10)
// 分类:复用 expenseByCategoryProvider,截取前 10,每行 = 图标 + 名字 + 金额 + 占比
//
// 2026-10-15 D64.3 改:容器改用 `ChartCard`,TabBar 放 trailing,showDivider=false
// 2026-10-21 D64.90 改:第一个 tab 随 range 变(年视角不再用"单笔")
//   - 本月:单笔 / 分类 —— 一个月里房租就是一条,单笔榜信息密度正常,保留
//   - 本年:笔数 / 分类 —— 年视角下固定开销按月重复(12 个月房租),
//     "单笔"排序键(单笔金额)被固定开销占满 → top10 霸屏,信息密度归零
//     (user 2026-10-21 原话:"TOP10 的单笔支出就基本是每个月的房租,
//       12 个月的话 top10 被它霸屏了,有用的就只有 top10 分类")
//   - 换成"笔数"维度:揭示钱是被一笔笔小额磨掉的
//     (例:全年 392 笔正餐、均价 ¥43 —— 按金额排的分类榜 / 单笔榜都看不到这一层)
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
    // D64.90:年视角第一个 tab 换口径(笔数),月视角保持单笔
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
              Tab(text: isYear ? '笔数' : '单笔'),
              const Tab(text: '分类'),
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
                ? const [_TopByCount(), _TopByCategory()]
                : const [_TopList(), _TopByCategory()],
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

/// 2026-10-21 D64.90 加:年视角「笔数 / 均价」tab
///
/// 每行 = 分类图标 + 分类名 + 「均价 ¥X · 合计 ¥Y」+ 右侧大号「N 笔」
/// 排序:笔数降序(笔数相同按合计金额降序,再按名称稳定)
/// 为什么大号数字是笔数而不是金额:这张榜就是按笔数排的,大号数字 = 排序键,
/// 均价/合计作为副信息放在标题下面(合计是背景信息,均价才是这张榜的新洞察)。
class _TopByCount extends ConsumerWidget {
  const _TopByCount();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(expenseByCategoryCountProvider);
    final cats =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return statsAsync.when(
      data: (data) {
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
                    '均价 ¥${_avgLabel(top[i].avg)} · 合计 ¥${Formatters.amount(top[i].amount, trimTrailingZeros: true)}',
                trailing: '${top[i].count} 笔',
                trailingColor: Color(top[i].color),
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

/// 均价显示:≥1 元取整(「一顿正餐 43 块」比「43.35 块」好读),<1 元保留小数
String _avgLabel(double avg) {
  if (avg >= 1) {
    return Formatters.amount(avg.roundToDouble(), trimTrailingZeros: true);
  }
  return Formatters.amount(avg, trimTrailingZeros: true);
}

class _TopByCategory extends ConsumerWidget {
  const _TopByCategory();

  static const int _slotCount = 10;
  static const double _rowHeight = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    final cats =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return expensesAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
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
                    '${(top[i].amount / total * 100).toStringAsFixed(0)}%',
                trailing: '¥${Formatters.amount(top[i].amount)}',
                trailingColor: Color(top[i].color),
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
                    Text(
                      secondary!,
                      style: const TextStyle(fontSize: 11, color: AppGray.g600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  Text(
                    trailingSub!,
                    style: const TextStyle(fontSize: 10, color: AppGray.g600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
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
