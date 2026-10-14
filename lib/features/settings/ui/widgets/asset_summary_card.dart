// lib/features/settings/ui/widgets/asset_summary_card.dart
// 我的页"资产"section 顶部 — 总资产 + 6 大类汇总卡片
//
// 2026-10-12 P2 commit 加(P2 · 我的页资产 section):
//   - 跟 settings_page "关于"卡片 / range_summary 同款黑底(ink)风格,大数居中
//   - 2026-10-13 P6:总资产 = 6 大类余额总和(累加,不抵消)
//   - 6 行 type chip:icon + type 中文名 + 余额(color 按 type 配色)
//     顺序:现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
//   - 进场:跟 range_summary 一样 fade-in,300ms aquaIn
//   - 空态:只显示总资产 0,6 行 type chip 都显示 0
//
// 数据源:
//   - assetRepositoryProvider (List<Asset>)
//   - assetBalancesProvider (Map<assetId, currentBalance>)
//   - assetTotalsProvider (AssetTotals — 6 大类,P6 扩)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';

class AssetSummaryCard extends ConsumerWidget {
  const AssetSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 监听 assets + balances 组合,这里只用 balances 简单触发刷新
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assetsAsync = ref.watch(allAssetsProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // 按 type 汇总 currentBalance(2026-10-13 P6:4 段 → 6 段)
    final byType = <String, double>{
      'cash_flow': 0.0,
      'investment': 0.0,
      'benefit': 0.0,
      'receivable': 0.0,
      'fixed_asset': 0.0,
      'other': 0.0,
    };
    for (final a in assets) {
      final bal = balances[a.id] ?? 0.0;
      byType[a.type] = (byType[a.type] ?? 0.0) + bal;
    }

    // 总资产:6 类之和(全部相加,不做正负抵消)
    final totalAll = byType.values.fold<double>(0.0, (s, v) => s + v);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brLg,
        // rim light border + 阴影,跟其他黑底卡(月度汇总 / 关于卡)保持一致
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
          width: 1.0,
        ),
        boxShadow: CardShadows.dark(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 总资产(大数)
          const Text(
            '总资产',
            style: TextStyle(
              color: AppGray.g400,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${Formatters.amount(totalAll)}',
              style: const TextStyle(
                color: AppSecondary.cream,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          const Divider(height: 1, color: AppGray.g600),
          const SizedBox(height: AppSpacing.s3),
          // 2026-10-13 P6:6 大类汇总(顺序按日常查看频度)
          _TypeRow(
            type: 'cash_flow',
            icon: Icons.account_balance_wallet_rounded,
            label: '现金流',
            amount: byType['cash_flow'] ?? 0,
          ),
          const SizedBox(height: AppSpacing.s2),
          _TypeRow(
            type: 'investment',
            icon: Icons.trending_up_rounded,
            label: '投资',
            amount: byType['investment'] ?? 0,
          ),
          const SizedBox(height: AppSpacing.s2),
          _TypeRow(
            type: 'benefit',
            icon: Icons.favorite_rounded,
            label: '福利',
            amount: byType['benefit'] ?? 0,
          ),
          const SizedBox(height: AppSpacing.s2),
          _TypeRow(
            type: 'receivable',
            icon: Icons.handshake_rounded,
            // 2026-10-14 改:跟所有"期权/负债"统一用"负债"称呼
            // 跟 asset_form / Speed Dial 同步;icon / color 已经一致(都走
            // AppSegment + handshake_rounded + 橙)
            label: '负债',
            amount: byType['receivable'] ?? 0,
          ),
          const SizedBox(height: AppSpacing.s2),
          _TypeRow(
            type: 'fixed_asset',
            icon: Icons.home_rounded,
            label: '不动产',
            amount: byType['fixed_asset'] ?? 0,
          ),
          const SizedBox(height: AppSpacing.s2),
          _TypeRow(
            type: 'other',
            icon: Icons.category_rounded,
            label: '其它',
            amount: byType['other'] ?? 0,
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.icon,
    required this.label,
    required this.amount,
  });
  final String type;
  final IconData icon;
  final String label;
  final double amount;

  /// 2026-10-14 P18:6 段配色统一走 AppSegment(集中管理,跨页一致)
  Color _colorFor(String t) => AppSegment.colorFor(t);

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(type);
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
            style: const TextStyle(color: AppGray.g400, fontSize: 13),
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
