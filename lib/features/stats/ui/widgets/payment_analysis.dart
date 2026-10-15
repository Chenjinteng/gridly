// lib/features/stats/ui/widgets/payment_analysis.dart
// 报表"支付分析"模块 —— 2 个环形图合并成 1 张卡 + tab 切换。
//
// 2026-10-15 D64.11 改:把原来 2 张独立卡(支出分类 CategoryPie +
// 支付账号 ExpenseByAssetChart)合并成"支付分析"模块,用 tab 切换
// (分类 / 账户),tab 样式跟消费趋势 / top_expenses 同款(teal label +
// indicatorSize.label 0 高 indicator)。
//
// 2026-10-15 D64.12 改:tab body 直接用 `PieChartContent`(无 ChartCard
// 嵌套),避免原 `PieChartCard` 在 SizedBox(height: 220) 内套 2 层卡
// 触发 BOTTOM OVERFLOWED BY 28px + 嵌套"支出分类"标题。"共 ¥X" trailing
// 留在外层 ChartCard 的 trailing slot(替代原嵌套 title + totalLabel)。
// 2026-10-15 D64.13 改:tab body 用 IntrinsicHeight 替代 SizedBox(240)。
//   固定高度 240 在 8 项 legend 时正好,但 3 项(账户 tab)留 68dp 空白;
//   IntrinsicHeight 让 TabBarView 按 max(各 tab intrinsic)算高度,3 项
//   case 空白缩到 ~44dp。
//
// - 分类 tab:复用 CategoryPie body(expenseByCategoryProvider + 类别色 token)
// - 账户 tab:复用 ExpenseByAssetChart body(viewport-aware 圆环动画 +
//   6 色 palette by index,D64.6/D64.7 已修)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/chart_card.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../application/stats_providers.dart';

/// "支付分析"模块容器 —— 1 张 ChartCard + 2 tabs(分类 / 账户)
class PaymentAnalysis extends ConsumerWidget {
  const PaymentAnalysis({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: ChartCard(
        title: '支付分析',
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
            labelColor: AppBrand.teal,
            unselectedLabelColor: AppGray.g600,
            indicatorColor: AppBrand.teal,
            dividerHeight: 0,
          ),
        ),
        // D64.12 → D64.13:PieChartContent body(无嵌套 card)。
        // 用 IntrinsicHeight 让 TabBarView 按内容算最大高度:
        //   - 8 项 legend(分类 tab):高度 = 32 padding + max(140 ring, 184 legend) = 216dp
        //   - 3 项 legend(账户 tab):相同 216dp,但内容只 172dp,
        //     顶部对齐留下 ~44dp 空白(原 240dp 固定留 68dp)
        // 之前用 SizedBox(height: 240) 固定高度时,3 项 case 留 68dp 空白
        // user UAT 反馈"高度比之前高,有空白" → IntrinsicHeight 自适应
        child: const IntrinsicHeight(
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
  /// D64.7:viewport-aware 触发入场动画
  ///   - false:widget 还没进入 scroll viewport,圆环不 forward
  ///   - true:viewport 进入后圆环开始动 —— 一次性,不再重置
  bool _appeared = false;

  final GlobalKey _chartKey = GlobalKey();
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollPos = Scrollable.maybeOf(context)?.position;
      _scrollPos?.addListener(_checkInView);
      _checkInView();
    });
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_checkInView);
    super.dispose();
  }

  void _checkInView() {
    if (_appeared) return;
    final ctx = _chartKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final scrollableBox =
        _scrollPos?.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollableBox == null) return;
    final widgetTopInScrollable = box
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final widgetHeight = box.size.height;
    final viewportHeight = scrollableBox.size.height;
    if (widgetTopInScrollable < viewportHeight &&
        widgetTopInScrollable + widgetHeight > 0) {
      _appeared = true;
      _scrollPos?.removeListener(_checkInView);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(expenseByAssetProvider);
    return KeyedSubtree(
      key: _chartKey,
      child: assetsAsync.when(
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
            play: _appeared,
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
