// lib/features/settings/ui/widgets/asset_tile.dart
// 我的页"资产"section 列表 tile —— 单个资产展示
//
// 2026-10-12 P2 commit 加:
//   - 跟 category_management_page 的 _CategoryTile 同款风格(Container 卡片 + ListTile)
//   - leading:icon chip(账户色块)
//   - title:name
//   - subtitle:type chip + 余额(余额从 assetBalanceProvider 取)
//   - trailing:[编辑][删除] IconButton(同 CategoryTile)
//   - 点 tile 整体也可触发编辑,跟 CategoryTile onEdit 一致
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';

/// 资产列表 tile
///   - name / type / icon / color / currentBalance(实时算)
///   - onEdit / onDelete:用户操作回调
class AssetTile extends ConsumerWidget {
  const AssetTile({
    super.key,
    required this.asset,
    required this.onEdit,
    required this.onDelete,
  });
  final Asset asset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// icon 名 → IconData 映射(2026-10-12 P2):
  ///   8 个常用资产 icon,跟 asset_form_sheet 的图标池保持一致
  static const Map<String, IconData> icons = {
    'account_balance_wallet': Icons.account_balance_wallet_rounded,
    'credit_card': Icons.credit_card_rounded,
    'savings': Icons.savings_rounded,
    'payments': Icons.payments_rounded,
    'account_balance': Icons.account_balance_rounded,
    'home': Icons.home_rounded,
    'directions_car': Icons.directions_car_rounded,
    'swap_horiz': Icons.swap_horiz_rounded,
  };

  /// type 名 → 中文标签(2026-10-13 P6:4 段 → 6 段,加投资/福利/债权)
  static const Map<String, String> typeLabels = {
    'cash_flow': '现金流',
    'investment': '投资',
    'benefit': '福利',
    'receivable': '债权/借出',
    'fixed_asset': '不动产',
    'other': '其它',
  };

  /// type 名 → 配色(跟 asset_summary_card 同源,2026-10-13 P6 加 3 类)
  static Color colorFor(String type) {
    switch (type) {
      case 'cash_flow':
        return AppBrand.teal;
      case 'investment':
        return AppBrand.gold;
      case 'benefit':
        return AppStatus.success;
      case 'receivable':
        return AppStatus.warning;
      case 'fixed_asset':
        return AppStatus.info;
      default:
        return AppGray.g600;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(asset.color);
    final typeColor = colorFor(asset.type);
    // 余额走 family provider 单查(避免 watch 整张 balances map)
    final balanceAsync = ref.watch(assetBalanceProvider(asset.id));
    final balance = balanceAsync.valueOrNull ?? 0.0;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: ListTile(
        onTap: onEdit,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.brXs,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Icon(
            icons[asset.icon] ?? Icons.account_balance_wallet_rounded,
            color: color,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                asset.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 2026-10-13 P6 加:includeInTransactions=false 时,标题右侧加
            //   小 archive icon 提示(替代之前挤一行的"不计入流水" chip,
            //   解决 30px overflow 问题)
            if (!asset.includeInTransactions) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: '不计入流水',
                child: Icon(
                  Icons.archive_outlined,
                  size: 14,
                  color: AppGray.g600,
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              // type 小标签(同款胶囊,type 配色)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  typeLabels[asset.type] ?? asset.type,
                  style: TextStyle(
                    fontSize: 10,
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '¥${Formatters.amount(balance)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppSemantic.balanceFor(balance),
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppStatus.error,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
