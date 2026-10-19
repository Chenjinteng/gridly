// lib/features/stats/ui/widgets/expense_analysis.dart
// 报表"支出分析"模块 —— 2 个环形图合并成 1 张卡 + tab 切换。
//
// 2026-10-15 D64.11 改:把原来 2 张独立卡(支出分类 CategoryPie +
// 支付账号 ExpenseByAssetChart)合并成模块,用 tab 切换
// (分类 / 账户),tab 样式跟消费趋势 / top_expenses 同款(teal label +
// indicatorSize.label 0 高 indicator)。
// 原名"支付分析",2026-10-15 user UAT 反馈"不是支付分析,而是支出分析"
// 改名 expense_analysis / ExpenseAnalysis / 标题"支出分析"。
//
// 2026-10-15 D64.12 改:tab body 直接用 `PieChartContent`(无 ChartCard
// 嵌套),避免原 `PieChartCard` 在 SizedBox(height: 220) 内套 2 层卡
// 触发 BOTTOM OVERFLOWED BY 28px + 嵌套"支出分类"标题。"共 ¥X" trailing
// 留在外层 ChartCard 的 trailing slot(替代原嵌套 title + totalLabel)。
// 2026-10-15 D64.14 改:tab body 用 IntrinsicHeight 触发了 Flutter 布局
//   断言(IntrinsicHeight + TabBarView/PageView 的 intrinsic 计算跟
//   viewport 管理冲突),回退 SizedBox(220)。固定高度的 trade-off:
//   8 项 legend(分类 tab)= 216dp,3 项(账户 tab)= 172dp,3 项
//   case 留 48dp 空白(比 D64.12 的 240dp 少 20dp)。要彻底解决需
//   重构 legend Column 让高度恒等于 ring 140dp(如 spaceEvenly),这是
//   后续优化项,本次先回退稳。
// 2026-10-15 D64.15 改:legend 紧凑(vertical:2 + fontSize:12) + 可滚动
//   (SingleChildScrollView),>8 项 user 上滑看全部,圆环仍 take(8) 视觉清爽。
//
// - 分类 tab:复用 CategoryPie body(expenseByCategoryProvider + 类别色 token)
// - 账户 tab:复用 ExpenseByAssetChart body(viewport-aware 圆环动画 +
//   6 色 palette by index,D64.6/D64.7 已修)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../../../core/widgets/once_visible.dart';
import '../../application/stats_providers.dart';

/// "支出分析"模块容器 —— 1 张 ChartCard + 2 tabs(分类 / 账户)
class ExpenseAnalysis extends ConsumerWidget {
  const ExpenseAnalysis({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: ChartCard(
        title: '支出分析',
        showDivider: false,
        trailing: SizedBox(
          height: 36,
          child: TabBar(
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.label,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: const [
              Tab(text: '分类'),
              Tab(text: '账户'),
            ],
            // D71.5.5:tabBarTheme 接管
            dividerHeight: 0,
          ),
        ),
        // D64.15:legend 紧凑(vertical:2 + fontSize:12)后,8 项总高 ~200dp
        //   8 项(分类 tab):200dp,0 slack
        //   3 项(账户 tab):172dp,28dp slack(比 D64.14 的 48dp 少 20dp)
        child: const SizedBox(
          height: 200,
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [_CategoryTab(), _AccountTab()],
          ),
        ),
      ),
    );
  }
}

/// 分类 tab:支出分类圆环图 + 图例(沿用 CategoryPie body 逻辑)
class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    return expensesAsync.when(
      data: (data) {
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        return PieChartContent(
          items: buildPieChartItems<CategoryExpense>(
            data,
            nameOf: (e) => e.name,
            valueOf: (e) => e.amount,
            colorOf: (e) => e.color,
          ),
          total: total,
          centerLabel: '总支出',
          centerValueText: '¥${Formatters.amount(total)}',
          // 分类 tab 在 stats_page 顶部通常已在 viewport,立即播
          play: true,
        );
      },
      loading: () => const PieChartContent(
        items: [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '¥0',
        play: true,
      ),
      error: (e, _) => PieChartContent(
        items: const [],
        total: 0,
        centerLabel: '总支出',
        centerValueText: '加载失败',
        play: true,
      ),
    );
  }
}

/// 账户 tab:按支付账户聚合支出圆环图(viewport-aware 圆环入场动画,
///   跟 D64.7 一致 —— 卡片在 stats_page 末尾,user 滚动到才看到 1200ms 扫角动画)
class _AccountTab extends ConsumerStatefulWidget {
  const _AccountTab();

  /// 2026-10-15 D64.6:固定 6 色 palette,按 index 取,>6 时循环。
  /// 选色:teal / orange / blue / pink / purple / cyan 6 色相互区分。
  /// (复用 core palette AppBrand/AppStatus/AppCategory 已有色 token)
  static const _palette = <int>[
    0xFF14B8A6, // AppBrand.teal
    0xFFF59E0B, // AppStatus.warning
    0xFF3B82F6, // AppStatus.info
    0xFFEC4899, // AppCategory.shopping (pink)
    0xFF8B5CF6, // AppCategory.education (purple)
    0xFF06B6D4, // AppCategory.telecom (cyan)
  ];

  @override
  ConsumerState<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends ConsumerState<_AccountTab> {
  // 2026-10-16 D64.89 改:viewport-aware 触发走 OnceVisible wrapper
  //   - 之前 inline _appeared / _chartKey / _scrollPos / _checkInView 50+ 行 boilerplate
  //   - 跟 asset_allocation_chart / assets_radar 完全同款
  //   - 改:OnceVisible(builder: (ctx, appeared) => ...) 一行替代,3 处共用

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(expenseByAssetProvider);
    return OnceVisible(
      builder: (context, appeared) => assetsAsync.when(
        data: (data) {
          final total = data.fold<double>(0, (s, e) => s + e.amount);
          return PieChartContent(
            items: [
              for (int i = 0; i < data.length; i++)
                PieChartLegendItem(
                  name: data[i].name,
                  value: data[i].amount,
                  color: _AccountTab._palette[i % _AccountTab._palette.length],
                ),
            ],
            total: total,
            centerLabel: '总支出',
            centerValueText: '¥${Formatters.amount(total)}',
            // D64.7:viewport-aware 触发圆环动画
            play: appeared,
          );
        },
        loading: () => const PieChartContent(
          items: [],
          total: 0,
          centerLabel: '总支出',
          centerValueText: '¥0',
          play: false,
        ),
        error: (e, _) => PieChartContent(
          items: const [],
          total: 0,
          centerLabel: '总支出',
          centerValueText: '加载失败',
          play: false,
        ),
      ),
    );
  }
}
