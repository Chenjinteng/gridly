// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 删除交互:左滑露出红色垃圾桶按钮(不立刻删),点击按钮才真正删除
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
        return _SwipeToDelete(
          key: ValueKey('tx-${transaction.id}'),
          onDelete: () => _onDeleteRequested(context, ref),
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

  /// 点击删除按钮触发:删 + 广谱 invalidate + SnackBar 提示
  Future<void> _onDeleteRequested(BuildContext context, WidgetRef ref) async {
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

/// 手势滑动展开操作按钮 —— 类似 iOS Mail.app 的滑动效果
///
/// 行为:
///   - 左滑超过阈值 → snap 露出操作按钮(不执行)
///   - 操作按钮可点 → 触发 onDelete
///   - 点 tile 其他位置 → 自动弹回关闭
class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onDelete;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete>
    with SingleTickerProviderStateMixin {
  /// 划开的固定宽度(px)—— 露出 76px 宽的删除按钮区域
  static const double _kOpenOffset = 76;

  /// snap 阈值:划到这个距离就锁住,否则弹回
  static const double _kSnapThreshold = 40;

  /// fling 速度阈值(向左 px/s),即使没划够阈值,快速左滑也直接 snap 打开
  static const double _kFlingVelocity = -300;

  late AnimationController _ctrl;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),  // 略延长给曲线留余地
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final start = _offset;
    final delta = target - start;
    if (delta == 0) return;
    _ctrl
      ..reset()
      ..addListener(() {
        // easeOutCubic: 快入慢出,snap 时有"惯性"自然收尾,比线性 180ms 丝滑很多
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        setState(() => _offset = start + delta * t);
      })
      ..forward();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 只响应向左滑(delta < 0)
    if (d.primaryDelta! > 0) return;
    setState(() => _offset = (_offset + d.primaryDelta!).clamp(-_kOpenOffset, 0.0));
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // 划得够远 OR 左滑速度够快 → 锁在 open 状态;否则弹回关闭
    if (_offset.abs() > _kSnapThreshold || velocity < _kFlingVelocity) {
      _animateTo(-_kOpenOffset);
    } else {
      _animateTo(0);
    }
  }

  void _close() {
    if (_offset != 0) _animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 底层:红色删除按钮(只在 tile 右侧 76px,不试图铺满同 tile 形状)
        // iOS Mail / 微信的滑动删除按钮设计 —— 胶囊/圆角矩形 + 跟 tile 圆角"面对面"对接,
        // 比"假装是 tile 的红色版"更柔和(后者完全打开时露出的 76px 区域
        // 是 Material 的中间矩形,没有左圆角,跟 tile 右圆角硬接)
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s1,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _kOpenOffset,
                child: Material(
                  color: AppStatus.error,
                  borderRadius: AppRadius.brMd,
                  child: InkWell(
                    borderRadius: AppRadius.brMd,
                    onTap: widget.onDelete,
                    child: const Center(
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 上层:卡片本身(随 _offset 水平平移)
        // 直接用 widget.child —— 它自己带 margin + brLg + 边框 + surfaceContainerLow 背景
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: _close,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}