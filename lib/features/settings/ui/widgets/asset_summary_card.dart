// lib/features/settings/ui/widgets/asset_summary_card.dart
// 我的页"资产"section 顶部 — 净资产 + 6 大类汇总卡片
//
// 2026-10-12 P2 commit 加(P2 · 我的页资产 section):
//   - 跟 settings_page "关于"卡片 / range_summary 同款黑底(ink)风格,大数居中
//   - 2026-10-13 P6:总资产 = 6 大类余额总和(累加,不抵消)
//   - 6 行 type chip:icon + type 中文名 + 余额(color 按 type 配色)
//     顺序:流动资金 / 投资 / 福利 / 债权 / 不动产 / 其它(D64.40 cash_flow 改"流动资金")
//   - 进场:跟 range_summary 一样 fade-in,300ms aquaIn
//   - 空态:只显示总资产 0,6 行 type chip 都显示 0
//
// 2026-10-16 D64.46 改(user UAT 反馈 v2):
//   - user 反馈"资产这个卡片并没有与之前的报表保持一致,
//     净资产呢?债务单独划分呢,这些都需要"
//   - 之前 D64.32/D64.36 报表里 AssetsOverviewChart 已经定义完整口径
//     (净资产大字 + 5 真资产 + 白色横线 + 债务 + 总资产小字),
//     D64.45 我把报表卡删了(避免冗余)但资产页 AssetSummaryCard 没 backport
//     净资产口径,仍是 P2 时代的"总资产 + 6 段全加",所以 user 现在看不到
//     净资产 + 债务单独划分
//   - 修法:backport D64.36 净资产口径到 AssetSummaryCard
//     ① 标题"总资产" → "净资产"
//     ② 大字公式 `totalAll`(6 段全加) → `netAssets`(5 真资产 - 负债)
//     ③ 段显示顺序:6 段全加 + receivable 中间
//        → 5 真资产(cash_flow/investment/benefit/fixed_asset/other)
//          + 白色横线(alpha 0.15)
//          + 1 段 receivable 末尾
//     ④ 末尾追加"总资产 ¥XXX"小字(11sp onSurfaceVariant,右对齐,
//        跟 D64.36 末尾小字同款)
//   - 数据源不变(assetRepositoryProvider + assetBalancesProvider,不走
//     assetTotalsProvider,因为这个 widget 本身有自己累加 byType 的逻辑,
//     跟 AssetsOverviewChart 用 provider 不同,保留以免引入额外依赖)
//   - 底色仍是 `AppBrand.ink`(D64.46 没改底色,D64.43.5 navy 是单条
//     asset tile 底色,跟这张汇总卡无关;navy 卡在资产列表每条 tile 顶部
//     的样式已经独立)
//
// 数据源:
//   - assetRepositoryProvider (List<Asset>)
//   - assetBalancesProvider (Map<assetId, currentBalance>)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/theme/gridly_palette.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';

class AssetSummaryCard extends ConsumerWidget {
  const AssetSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    // 2026-10-16 D64.75 改:6 段 sum 改用 assetTotalsProvider 共享计算
    //   - 之前就地 byType O(N) 累加,跟 LiabilitiesDashboard / 其它 dashboard
    //     5 处同款重复;现在 1 次 watch,1 处定义
    //   - 由"自己累加以避免引入额外依赖"(原 D64.46 注释)改为统一走 provider,
    //     全 app 5+ 处累加逻辑只 1 份(SQL 聚合在 provider,O(1) 读)
    //   - assets 列表仍 watch(每行 _TypeRow 需要 segmentOrder 渲染),
    //     balances 不再 watch(provider 已依赖,自动刷新)
    final totalsAsync = ref.watch(assetTotalsProvider);
    final totals = totalsAsync.valueOrNull;
    final byType = <String, double>{
      'cash_flow': totals?.totalCashFlow ?? 0.0,
      'investment': totals?.totalInvestment ?? 0.0,
      'benefit': totals?.totalBenefit ?? 0.0,
      'receivable': totals?.totalReceivable ?? 0.0,
      'fixed_asset': totals?.totalFixedAsset ?? 0.0,
      'other': totals?.totalOther ?? 0.0,
    };

    // D64.46:净资产口径(跟 D64.36 报表净资产卡公式一致)
    //   - 总资产 = 5 段真资产 sum(**不含 receivable**,user "总资产不算负债"口径)
    //   - 负债 = max(0, -receivable)(只算净欠款,正 receivable 不算负债)
    //   - 净资产 = 总资产 - 负债,作为大字显示
    final totalCashFlow = byType['cash_flow']!;
    final totalInvestment = byType['investment']!;
    final totalBenefit = byType['benefit']!;
    final totalFixedAsset = byType['fixed_asset']!;
    final totalOther = byType['other']!;
    final totalReceivable = byType['receivable']!;
    final totalAssets =
        totalCashFlow +
        totalInvestment +
        totalBenefit +
        totalFixedAsset +
        totalOther;
    final debt = totalReceivable < 0 ? -totalReceivable : 0.0;
    final netAssets = totalAssets - debt;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        // D71.3:永远走 inkPalette.inkSurface(深色模式不变 cream)
        color: theme.extension<GridlyPalette>()!.inkSurface,
        borderRadius: AppRadius.brLg,
        // rim light border + 阴影,跟其他黑底卡(月度汇总 / 关于卡)保持一致
        border: Border.all(
          color: theme.extension<GridlyPalette>()!.onInkSurface.withValues(
            alpha: isDark ? 0.08 : 0.15,
          ),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // D64.46:标题"总资产" → "净资产",跟 D64.36 口径一致
          // D71.3:次级文字用 onInkSurface 60% alpha(在任何 ink 底上都 OK)
          Text(
            '净资产',
            style: TextStyle(
              color: theme
                  .extension<GridlyPalette>()!
                  .onInkSurface
                  .withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          // D64.46:大数 totalAll(6 段全加) → netAssets(5 真资产 - 负债)
          // D71.3:永远走 onInkSurface(cream)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${Formatters.amount(netAssets)}',
              style: TextStyle(
                color: theme.extension<GridlyPalette>()!.onInkSurface,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          const Divider(height: 1, color: AppGray.g600),
          const SizedBox(height: AppSpacing.s3),
          // 2026-10-14 P18 D47:6 大类汇总统一走 AppSegment 集中数据源
          // 2026-10-16 D64.46:5 真资产 + 白线 + 1 段 receivable
          //   - _segmentOrder 跟 D64.36 报表净资产卡一致
          //   - receivable 段在末尾 + 之前一道白线隔开(避免"5 真资产 +
          //     末尾 debt" 跟末尾"总资产"小字 视觉混淆)
          for (int i = 0; i < _segmentOrder.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s2),
            // D64.46:5 真资产(cash_flow..other)跟 1 段 receivable 中间
            //   插白色横线 —— 跟前 AssetsOverviewChart 同款,alpha 0.15 white
            if (_segmentOrder[i] == 'receivable')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            _TypeRow(
              type: _segmentOrder[i],
              amount: byType[_segmentOrder[i]] ?? 0,
            ),
          ],
          // D64.46:末尾"总资产"小字 —— 跟 D64.36 报表净资产卡末尾
          //   备注同款(11sp onSurfaceVariant,右对齐)
          //   完整 layout:5 真资产 —— 白线 —— receivable —— 末白线 —— 总资产小字
          //   形成"净资产(大字)= 总资产(小字) - 负债(receivable 净欠)"公式链
          const SizedBox(height: AppSpacing.s2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '总资产 ¥${Formatters.amount(totalAssets)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.amount});

  /// 2026-10-14 P18 D47:type 字符串,内部 icon / label / color 全走 AppSegment
  ///   - 跨页一致:总览卡 / 资产页 / 新增账户 都从 AppSegment.iconFor / labelFor / colorFor 拿
  ///   - 删硬编码 icon / label 参数,避免一处改名多处漏改
  final String type;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final color = AppSegment.colorFor(type);
    final icon = AppSegment.iconFor(type);
    final label = AppSegment.labelFor(type);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brXs,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Text(
            label,
            // D71.3:次级文字用 onInkSurface 60% alpha
            style: TextStyle(
              color: Theme.of(context)
                  .extension<GridlyPalette>()!
                  .onInkSurface
                  .withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
        Text(
          '¥${Formatters.amount(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 2026-10-16 D64.46:6 大类展示顺序,跟 D64.36 报表净资产卡 _segmentOrder 一致
///   - 5 段真资产在前(cash_flow / investment / benefit / fixed_asset / other)
///   - receivable(债务)挪到末尾,白线切开
///   - 跟末尾"总资产"小字形成"净资产 → 负债 → 总资产"公式语义链
const List<String> _segmentOrder = [
  'cash_flow',
  'investment',
  'benefit',
  'fixed_asset',
  'other',
  'receivable',
];
