// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 滑动交互:左滑露出 [编辑][删除] 两个按钮(各 76px),分别跳转编辑页 / 触发删除
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
import 'edit_transaction_sheet.dart';
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
          onEdit: () => _onEditRequested(context),
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

  /// 点击编辑按钮触发:在当前 tab 弹出 sheet 编辑(预填 + 保存 update),
/// 关闭 sheet 不跳路由,保留流水列表可见 / 不丢上下文
  Future<void> _onEditRequested(BuildContext context) async {
    await showEditTransactionSheet(context, transaction);
  }
}

/// 手势滑动展开操作按钮 —— 类似 iOS Mail.app 的滑动效果
///
/// 行为:
///   - 左滑超过阈值 → snap 露出 [编辑][删除] 两个操作按钮(不执行)
///   - 编辑按钮可点 → 触发 onEdit
///   - 删除按钮可点 → 触发 onDelete
///   - 点 tile 其他位置 → 自动弹回关闭
class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    required this.onEdit,
  });

  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete>
    with SingleTickerProviderStateMixin {
  /// 划开的固定宽度(px)—— 露出 [编辑 76 + 删除 76 = 152]px 的按钮区域
  static const double _kOpenOffset = 152;

  /// snap 阈值:划到这个距离就锁住,否则弹回
  static const double _kSnapThreshold = 40;

  /// fling 速度阈值(向左 px/s),即使没划够阈值,快速左滑也直接 snap 打开
  static const double _kFlingVelocity = -300;

  late final AnimationController _ctrl;
  double _offset = 0;

  /// 当前吸附动画的起点和终点(每次 _animateTo 用 _offset 当前实际值覆盖)
  /// 关键:必须是"当前实际位置",动画中断后从断点续动才不会出现视觉跳跃。
  double _animStart = 0;
  double _animEnd = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),  // 略延长给曲线留余地
    );
    // 关键:listener 只在生命周期内注册一次,不再每次 _animateTo 都 addListener
    // 旧实现多次 _animateTo 会累积 listener,每次 controller tick 触发多次 setState
    _ctrl.addListener(_handleAnimTick);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleAnimTick);
    _ctrl.dispose();
    super.dispose();
  }

  /// 动画 tick:用 easeOutCubic 把 _ctrl.value (0..1) 映射到偏移
  void _handleAnimTick() {
    if (!mounted) return;  // 防御:widget 卸载后最后一帧可能仍触发
    final progress = Curves.easeOutCubic.transform(_ctrl.value);
    setState(() {
      _offset = _animStart + (_animEnd - _animStart) * progress;
    });
  }

  /// 平滑动到 target。
  /// 关键:用当前 _offset 作为新动画起点(支持中断后从实际位置继续),
  /// 而不是用上次 _animateTo 调用的 _offset(可能是动画中间值,导致跳跃)。
  void _animateTo(double target) {
    if (_offset == target) return;
    _ctrl.stop();  // 停止可能正在进行的动画
    _animStart = _offset;  // 当前实际位置作为新动画起点
    _animEnd = target;
    _ctrl.forward(from: 0);
  }

  /// 用户开始拖动:立即停止正在进行的吸附动画,防止 drag 与 animation 并发修改 _offset
  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 只响应向左滑(delta < 0)。右滑在已开状态被忽略(本批次不擅改删除语义)
    if (d.primaryDelta! > 0) return;
    setState(() {
      _offset = (_offset + d.primaryDelta!).clamp(-_kOpenOffset, 0.0);
    });
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
    final theme = Theme.of(context);
    return Stack(
      children: [
        // 底层:操作按钮条 — [编辑 76px][删除 76px] 紧挨,各圆角与 tile 圆角对齐(brLg)
        // 左按钮(编辑)用主题色 primary 标识"次要/编辑"语义,
        // 右按钮(删除)用 error 红标识"危险"语义 —— iOS 标准 destructive 在右,gridly 跟齐。
        // 关键:每个按钮圆角 == tile 圆角(brLg=16),避免 tile 右边缘漏色。
        // 外层 surface Container(color: surface) 占据整个 Stack 范围挡住按钮漏色。
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s1,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _kOpenOffset / 2,
                    child: Material(
                      color: theme.colorScheme.primary,
                      borderRadius: AppRadius.brLg,
                      child: InkWell(
                        borderRadius: AppRadius.brLg,
                        onTap: widget.onEdit,
                        child: const Center(
                          child: Icon(
                            Icons.edit_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _kOpenOffset / 2,
                    child: Material(
                      color: AppStatus.error,
                      borderRadius: AppRadius.brLg,
                      child: InkWell(
                        borderRadius: AppRadius.brLg,
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
                ],
              ),
            ),
          ),
        ),
        // 上层:卡片本身(随 _offset 水平平移)
        // 外层 Container(color: surface) 占据整个 Stack 范围,把底层按钮色彻底挡住
        // —— widget.child BoxDecoration 圆角外空白 + Padding 收缩外的 margin 区
        // 都会被这个外层 surface 色填上,按钮不会再漏出。
        // onHorizontalDragStart 用来在用户开始拖动时立即停止吸附动画,
        // 避免 drag 与 animation 并发修改 _offset 导致跳跃。
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: _close,
            child: Container(
              color: theme.colorScheme.surface,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}