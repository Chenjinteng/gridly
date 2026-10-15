// lib/features/stats/ui/widgets/expense_by_asset.dart
// 报表第 8 张卡:按支付账户/资产支出分布(类似 category_pie 但按账户)
//   - user 多账户场景:看现金账户 / 各信用卡 / 花呗 各花了多少
//   - 口径跟 statsSummaryProvider / _periodSummary 一致:真支出 + 还款
//   - 还款(现金→债务调拨)accountId 是 source 现金账户,归到现金账户
//
// 2026-10-15 D63 加
// 2026-10-15 D63.1 加 viewport-aware 圆环入场动画
// 2026-10-15 D64.2 改:用 `ChartCard` + `PieChartCard`,移除重复的卡片容器 / 圆环 + 图例实现
// 2026-10-15 D64.6 改:颜色用固定 6 色 palette 按 index 取,不读 asset.color。
//   原读 asset.color 时 3 个账户可能同色(用户创建时未刻意区分),圆环 + 图例
//   全绿看不出区别。固定 palette 保证视觉区分(user 反馈"随机颜色也行")。
// 2026-10-15 D64.7 改:把 D63.1 的 viewport-aware 逻辑重新接回来(D64.2 抽
//   PieChartCard 时丢了),参考 `BudgetOverviewChart` 模式:_appeared flag
//   + Scrollable.maybeOf + GlobalKey 监听 viewport 进入,进入前 play=false
//   不 forward,进入后 play=true 触发 didUpdateWidget → 圆环动画。user UAT
//   反馈"支付账号的动画不是滚动到了才加载的",跟本月预算对齐。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/charts/pie_chart_card.dart';
import '../../application/stats_providers.dart';

class ExpenseByAssetChart extends ConsumerStatefulWidget {
  const ExpenseByAssetChart({super.key});

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
  ConsumerState<ExpenseByAssetChart> createState() =>
      _ExpenseByAssetChartState();
}

class _ExpenseByAssetChartState extends ConsumerState<ExpenseByAssetChart> {
  /// 2026-10-15 D64.7:viewport-aware 触发入场动画
  ///   - false:widget 还没进入 scroll viewport,圆环动画不启动
  ///   - true:viewport 进入后,圆环才开始动 —— 一次性,不再重置
  /// 参考 BudgetOverviewChart._appeared + monthly_trend BarChart 同模式
  bool _appeared = false;

  /// 用来拿 widget 在 scroll viewport 中的位置
  final GlobalKey _chartKey = GlobalKey();

  /// 监听 Scrollable 滚动,每次滚动时检查 widget 是否进入 viewport
  ScrollPosition? _scrollPos;

  @override
  void initState() {
    super.initState();
    // 跟 BudgetOverviewChart.initState 同模式:监听 Scrollable.position,
    // 任何子 widget 在 scrollable 坐标系中"任意部分进入 viewport"都触发
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

  /// 检测 widget 是否在 scroll viewport 内
  ///   - 拿 chart RenderBox,scrollable RenderBox
  ///   - box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy
  ///     是 widget 顶在 scrollable 坐标系中的 y
  ///   - 如果 widget 顶 < viewport 高 && widget 底 > 0 → 任意部分可见 → 触发
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
    // 2026-10-15 D64.7:KeyedSubtree 给 _checkInView 用此 key 拿 widget 在
    //   scrollable 坐标系中的位置,任意部分进入 viewport 时 setState(_appeared)
    //   → 圆环动画开始
    return KeyedSubtree(
      key: _chartKey,
      child: assetsAsync.when(
        data: (data) {
          final total = data.fold<double>(0, (s, e) => s + e.amount);
          return PieChartCard(
            title: '支付账户',
            // 2026-10-15 D64.6:不走 buildPieChartItems(其 colorOf 没有 index 参数),
            // 直接 map:按 index 取 palette 色,保证 N 个账户视觉区分。
            items: [
              for (int i = 0; i < data.length; i++)
                PieChartLegendItem(
                  name: data[i].name,
                  value: data[i].amount,
                  color: ExpenseByAssetChart
                      ._palette[i % ExpenseByAssetChart._palette.length],
                ),
            ],
            total: total,
            centerLabel: '总支出',
            centerValueText: '¥${Formatters.amount(total)}',
            totalLabel: data.isEmpty ? null : '共 ¥${Formatters.amount(total)}',
            // 2026-10-15 D64.7:viewport-aware 触发圆环动画
            //   - _appeared=false:圆环不 forward,直接显示最终形态(空)
            //   - _appeared=true:didUpdateWidget 触发 forward → 1200ms 扫角动画
            play: _appeared,
          );
        },
        loading: () => const PieChartCard(
          title: '支付账户',
          items: [],
          total: 0,
          centerLabel: '总支出',
          centerValueText: '¥0',
          totalLabel: null,
          play: false,
        ),
        error: (e, _) => PieChartCard(
          title: '支付账户',
          items: const [],
          total: 0,
          centerLabel: '总支出',
          centerValueText: '加载失败',
          totalLabel: null,
          play: false,
        ),
      ),
    );
  }
}
