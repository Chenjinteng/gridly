// lib/features/stats/ui/widgets/assets_overview_chart.dart
// stats 资产视角总览卡 —— 总资产 + 6 大类汇总
//
// 2026-10-12 P4 commit 加(P4 · 资产分布 + 雷达图):
//   - 跟 budget_overview_chart 同款 viewport-aware 触发入场
//     (GlobalKey + Scrollable.position 监听,任意部分进入 viewport 才触发)
//   - 顶部"总资产" + 大数字 0→total 滚动(1200ms aquaIn)
//   - 6 行 type chip:icon + 类型名 + 余额(纯展示,点击无效果)
//     顺序:现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
//   - 黑底卡片(ink 风格,跟 settings_page "关于"卡 / range_summary 一致)
//
// 2026-10-13 P6 改 4 段 → 6 段(跟 asset_form 6 段同步,删"负债"加投资/福利/债权)
//
// 数据源:assetTotalsProvider
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';

class AssetsOverviewChart extends ConsumerStatefulWidget {
  const AssetsOverviewChart({super.key});

  @override
  ConsumerState<AssetsOverviewChart> createState() =>
      _AssetsOverviewChartState();
}

class _AssetsOverviewChartState extends ConsumerState<AssetsOverviewChart> {
  /// viewport-aware 触发(跟 budget_overview_chart 同款,commit 102):
  ///   - false:widget 还没进入 scroll viewport,数字显示 0
  ///   - true:viewport 进入后,数字从 0 滚动到目标值 —— 一次性,不再重置
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
    if (box == null) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalsAsync = ref.watch(assetTotalsProvider);
    final theme = Theme.of(context);
    return Container(
      key: _chartKey,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
        // rim light border + 黑底阴影,跟其他黑底卡保持一致
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: totalsAsync.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Text(
            '加载资产失败:$e',
            style: const TextStyle(color: AppStatus.error),
          ),
        ),
        data: (totals) {
          // 总资产 = 6 类之和(简单累加,P4 文档明确"按大类 currentBalance 总和")
          final totalAll =
              totals.totalCashFlow +
              totals.totalInvestment +
              totals.totalBenefit +
              totals.totalReceivable +
              totals.totalFixedAsset +
              totals.totalOther;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '总资产',
                    style: TextStyle(
                      color: AppGray.g400,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    '6 大类',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s1),
              // 大数字(进入 viewport 后从 0 滚动到 total)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedCounter(
                  prefix: '¥',
                  value: _appeared ? totalAll : 0,
                  // 2026-10-13 UAT fix:总资产跟 6 段明细用同一单位
                  //   - 6 段明细(尤其"不动产 ¥100.00万")都用 withUnit: true 带"万"
                  //   - 总资产 ≥ 100 万时也得带"万",否则 ¥172.89 跟 ¥100.00万
                  //     看起来不像是 1 个量级的(用户问"为什么是 172.89")
                  //   - 实际 1,728,990 / 10000 = 172.899 → 172.89万 才跟 6 段对得上
                  formatter: (v) => Formatters.amount(v, withUnit: true),
                  duration: const Duration(milliseconds: 1200),
                  curve: AppMotion.aquaIn,
                  style: const TextStyle(
                    color: AppSecondary.cream,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              const Divider(height: 1, color: AppGray.g600),
              const SizedBox(height: AppSpacing.s3),
              // 2026-10-14 改(D47):6 大类汇总改走 AppSegment 集中数据源
              //   - 之前硬编码 icon / color / label,跟资产页不一致:
              //     - 现金流:teal(老) vs cashFlow 亮蓝(AppSegment)
              //     - 投资:gold(老) vs investment 紫
              //     - 福利:success(老) vs benefit 粉
              //     - 不动产:info(老) vs fixedAsset 青
              //     - 其它:g600(老) vs other 灰
              //   - user 反馈:'这里的颜色图标要与新增账户里面的保持一致'
              //   - 修:6 段全改 AppSegment.iconFor / colorFor / labelFor
              //     跨 widget 一致
              for (int i = 0; i < _segmentOrder.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s2),
                _TypeRow(
                  type: _segmentOrder[i],
                  amount: _appeared
                      ? _amountForType(_segmentOrder[i], totals)
                      : 0,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 6 大类单行(跟 AssetSummaryCard._TypeRow 同款,这里独立避免跨文件依赖)
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.amount});

  /// asset.type 字符串,内部走 AppSegment.iconFor / colorFor / labelFor
  final String type;
  final double amount;

  IconData get _icon => AppSegment.iconFor(type);
  Color get _color => AppSegment.colorFor(type);
  String get _label => AppSegment.labelFor(type);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brXs,
          ),
          child: Icon(_icon, color: _color, size: 16),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Text(
            _label,
            style: const TextStyle(color: AppGray.g400, fontSize: 13),
          ),
        ),
        Text(
          '¥${Formatters.amount(amount)}',
          style: TextStyle(
            color: _color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 6 大类展示顺序(跟 asset_form_page 段位顺序一致)
///   - 顺序固定,跟资产页 / 新增账户页 6 段 chip 顺序对齐,避免视觉错位
const List<String> _segmentOrder = [
  'cash_flow',
  'investment',
  'benefit',
  'receivable',
  'fixed_asset',
  'other',
];

/// 6 大类金额查询(从 AssetTotals 提取对应字段)
///   - 不知道 type 时兜底 0(对应 empty segment,UI 不显示但 row 仍在)
double _amountForType(String type, AssetTotals totals) {
  switch (type) {
    case 'cash_flow':
      return totals.totalCashFlow;
    case 'investment':
      return totals.totalInvestment;
    case 'benefit':
      return totals.totalBenefit;
    case 'receivable':
      return totals.totalReceivable;
    case 'fixed_asset':
      return totals.totalFixedAsset;
    case 'other':
      return totals.totalOther;
    default:
      return 0;
  }
}
