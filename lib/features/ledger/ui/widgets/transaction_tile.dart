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
        return Material(
          // InkWell 涟漪需要 Material 祖先
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.brLg,
            onLongPress: () => _confirmDelete(context, ref, cat),
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

  /// 长按触发:弹确认对话框 → 确认后删 + 广谱 invalidate 所有依赖 provider
  /// 删一笔会影响首页月度汇总 / 流水列表 / 报表饼图 + Top 10 + 月度趋势
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category? cat,
  ) async {
    final amountStr =
        '${transaction.type == 'income' ? '+' : '-'} ¥${Formatters.amount(transaction.amount)}';
    final label = cat?.name ?? '未分类';
    final noteStr = (transaction.note != null && transaction.note!.isNotEmpty)
        ? '\n${transaction.note}'
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条流水?'),
        content: Text('$label  $amountStr$noteStr'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppStatus.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(transactionRepositoryProvider).delete(transaction.id);
    // 广谱刷新 —— 流水 / 首页 / 报表 / 分类页都同步更新
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