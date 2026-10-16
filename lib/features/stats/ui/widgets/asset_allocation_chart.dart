// lib/features/stats/ui/widgets/asset_allocation_chart.dart
// 报表"资产"视角 dashboard —— 资产配置分布环形图
//
// 2026-10-16 D64.62 加(user UAT 反馈):
//   - user 反馈"增加一个环形图,叫资产配置分布,是把所有资产账号统计起来
//     作比例,不含借入的债务,但包含借出的债务"
//
// 2026-10-16 D64.63 重写(user UAT 反馈):
//   - user 反馈"你理解错了,不是把 5 类的资产做成环形,而是把现金,银行卡,
//     微信支付,余额宝等等,这些子类来进行画环形"
//   - 数据源改"每个具体账户"(assets.where(bal > 0))做环形
//   - 图例只显示占比 % 不显示金额
//
// 2026-10-16 D64.65 加(user UAT 反馈):
//   - user 反馈两件事:
//     ① "资产配置分布的动画要注意,也是要滚动到的时候才进行加载,参考其它的环图"
//       → viewport-aware 触发(同 ExpenseAnalysis _AccountTab 套路,
//       scroll listener 检测 widget top 进入 viewport 才 forward 圆环动画)
//     ② "最好不要再圆环中间显示总资产的金额,资产报表都尽量不要出现总资产的
//       额度,总资产只有一个可以查看的地方,就是资产管理页面"
//       → 删中心"总资产"label + AnimatedCounter 数字(原 D64.62 加的)
//   - 实现:用 AnimatedPieChart(fl_chart 同款) + 自组装 Stack,而不是
//     PieChartContent(后者强制显示 centerLabel/centerValueText 两 Text,
//     传空字符串仍占 0 height 但不够干净,user 不要"总资产"我们直接删)
//
// 2026-10-16 D64.66 修:
//   - 上一版(0.1.0+13)D64.65 改写为 ConsumerStatefulWidget + PieChartContent,
//     user 上机反馈"资产报表整页空白"。根因不在 AssetAllocationChart
//     本身(它独立 work),而是同一页面 DebtDashboard 的 TabBarView
//     抛 unbounded height 异常导致整个 case build 失败。
//     详细见 debt_dashboard.dart D64.66 注释。
//   - 本次 AssetAllocationChart 还是 ConsumerStatefulWidget viewport-aware
//     (D64.65 设计保留),只是跟 DebtDashboard 重写一起提交到 D64.66 commit。
//
// 2026-10-16 D64.67 加:
//   - user 反馈"资产配置分布的圆环中间没有东西好奇怪,加个统计当前的
//     资产账号个数吧"
//   - 实现:Stack 包 AnimatedPieChart + Center Column 两行(数字 + 标签),
//     数字走 items.length(账户级 filter bal > 0 后的数量,跟 ringShown / legend
//     口径一致);不在中心显示总资产(D64.65 user 原则保留)。
//   - 入场动画:AnimatedOpacity(280ms),跟 _appeared 联动(滚动到才淡入),
//     跟 ring 动画的 play: _appeared 时机对齐。
//
// 数据源:
//   - allAssetsProvider(全部账户,逐账户独立 1 段)
//   - assetBalancesProvider(Map<assetId, currentBalance>)
//   - filter:`bal > 0`(负余额账户不计入,在 DebtDashboard 负债 tab 独立显示)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/widgets/animated_pie_chart.dart';
import '../../../../core/widgets/charts/chart_card.dart';

/// 报表"资产配置分布"环形图 dashboard
///   - 每个具体账户 1 段(不是 6 段类型,D64.63 改)
///   - 借出 receivable 计入,借入 receivable 不计入
///   - D64.65 viewport-aware 动画触发(滚动到才 forward)
///   - D64.65 圆环中心不显示总资产(直接不画 Center Column,不是传空字符串)
class AssetAllocationChart extends ConsumerStatefulWidget {
  const AssetAllocationChart({super.key});

  /// 圆环最大扇区数(>8 时圆环只显示前 8,legend 显示全部可滚动)
  static const int _ringMaxSections = 8;

  @override
  ConsumerState<AssetAllocationChart> createState() =>
      _AssetAllocationChartState();
}

class _AssetAllocationChartState
    extends ConsumerState<AssetAllocationChart> {
  /// D64.65 viewport-aware 触发入场动画(同 expense_analysis _AccountTab 套路)
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
    final theme = Theme.of(context);
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // D64.63:逐账户生成 items(账户级而非段位级)
    final items = <_AllocationItem>[];
    for (final a in assets) {
      final bal = balances[a.id] ?? 0.0;
      if (bal > 0) {
        items.add(_AllocationItem(
          name: a.name,
          value: bal,
          color: Color(a.color),
        ));
      }
    }
    items.sort((a, b) => b.value.compareTo(a.value));
    // 2026-10-16 D64.72 修:图例百分比之前每行 O(N) 重算全表 sum(整体 O(N²))
    // 提一次到 build 顶部,图例行直接除(避免账户数膨胀时 build 卡顿)
    final totalValue = items.fold<double>(0, (s, e) => s + e.value);
    final ringShown = items.take(AssetAllocationChart._ringMaxSections).toList();

    return KeyedSubtree(
      key: _chartKey,
      child: ChartCard(
        title: '资产配置分布',
        showDivider: true,
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s5),
                child: Center(
                  child: Text(
                    '当前无资产',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 左侧圆环(140×140)— D64.65 不画中心数字(总资产只显示
                    //   在资产管理页),直接 AnimatedPieChart,不再 stack
                    //   Center Column 文字。
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedPieChart(
                            sections: [
                              for (final i in ringShown)
                                PieChartSectionData(
                                  value: i.value,
                                  color: i.color,
                                  title: '',
                                  radius: 18,
                                ),
                            ],
                            play: _appeared,
                          ),
                          // 圆环中心:账户数(不显示总资产 — D64.65 user 原则)
                          // 走"X / 个账户"两行,跟 range_summary 计数类视觉对齐
                          AnimatedOpacity(
                            opacity: _appeared ? 1 : 0,
                            duration: const Duration(milliseconds: 280),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  items.length.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppGray.g900,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s05),
                                const Text(
                                  '个账户',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppGray.g400,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    // 右侧 legend — D64.63 只显示占比 % 不显示金额
                    Expanded(
                      child: SizedBox(
                        height: 168,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < items.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: AppSpacing.s1),
                                _AllocationLegendRow(
                                  name: items[i].name,
                                  color: items[i].color,
                                  percent: items[i].value / totalValue,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 单账户数据
class _AllocationItem {
  const _AllocationItem({
    required this.name,
    required this.value,
    required this.color,
  });
  final String name;
  final double value;
  final Color color;
}

/// 图例行:小色块 + 名称 + 占比 %(D64.63 删金额字段)
class _AllocationLegendRow extends StatelessWidget {
  const _AllocationLegendRow({
    required this.name,
    required this.color,
    required this.percent,
  });

  final String name;
  final Color color;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Text(
          '${(percent * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// 图例行:小色块 + 名称 + 占比 %(D64.63 删金额字段)