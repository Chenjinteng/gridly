// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 长按 → 弹确认对话框 → 删除(防误删错记录)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/refresh_providers.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../application/transactions_providers.dart';

class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.transaction});
  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    return categoriesAsync.when(
      data: (cats) {
        Category? cat;
        for (final c in cats) {
          if (c.id == transaction.categoryId) {
            cat = c;
            break;
          }
        }
        final color = cat == null ? AppGray.g400 : Color(cat.color);
        final amountColor =
            transaction.type == 'income' ? AppBrand.gold : AppStatus.error;
        final prefix = transaction.type == 'income' ? '+' : '-';
        final theme = Theme.of(context);
        return Dismissible(
          key: ValueKey('tx-${transaction.id}'),
          direction: DismissDirection.endToStart,
          background: const SizedBox.shrink(),
          secondaryBackground: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s1,
            ),
            decoration: BoxDecoration(
              color: AppStatus.error,
              borderRadius: AppRadius.brLg,
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          onDismissed: (_) => _onSwipedDelete(context, ref),
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s1,
            ),
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.brXs,
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    CategoryIcons.map[cat?.icon ?? 'category'] ??
                        Icons.category_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat?.name ?? '未分类',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (transaction.note != null &&
                          transaction.note!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                        Text(
                          transaction.note!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '$prefix ¥${Formatters.amount(transaction.amount)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: amountColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 70),
      error: (e, _) => Container(
        margin: const EdgeInsets.all(AppSpacing.s4),
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error)),
      ),
    );
  }

  /// 左滑删除触发:删 + 广谱 invalidate + 轻量 SnackBar 提示
  /// (不再弹确认对话框 —— 用户嫌弹窗太多)
  Future<void> _onSwipedDelete(BuildContext context, WidgetRef ref) async {
    await ref.read(transactionRepositoryProvider).delete(transaction.id);
    refreshAllData(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已删除'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}