// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 滑动交互:左滑露出 [编辑][删除] 两个按钮(各 76px),分别跳转编辑页 / 触发删除
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
  /// 划开的固定宽度(px)—— 露出 [编辑 76 + 4 gap + 删除 76 = 156]px 的按钮区域
  /// (中间留 4px surface 色 gap 让两个按钮视觉独立,不粘成一条)
  static const double _kOpenOffset = 156;

  /// snap 阈值:划到这个距离就锁住,否则弹回
  static const double _kSnapThreshold = 40;

  /// fling 速度阈值(向左 px/s),即使没划够阈值,快速左滑也直接 snap 打开
  static const double _kFlingVelocity = -500;

  /// 超过这个速度认为是"快速 fling"—— 用 friction continuation(模拟惯性)
  /// 然后 spring snap 到最近端点。比慢速 spring 更有"原生"感。
  static const double _kFastFlingThreshold = 800;

  /// 按钮"从右滑入"距离(opacity 0 时偏移 +12px,opacity 1 时偏移 0)
  static const double _kButtonSlideIn = 12;

  /// Spring 物理参数 —— 接近 iOS 9+ UIKit swipe action 弹性。
  /// critical damping = 2*sqrt(stiffness*mass) ≈ 39;damping=38 几乎临界,
  /// 几乎无过冲,响应快速,视觉"丝滑不拖泥带水"。
  static const SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 38.0,
  );

  /// Friction 系数 —— iOS 默认 ~0.135,模拟大阻力快速收敛。
  static const double _kDrag = 0.135;

  late final AnimationController _ctrl;
  double _offset = 0;

  /// fling continuation 中标志 —— 监听 fling 完成后切到 spring snap
  bool _isFlinging = false;

  @override
  void initState() {
    super.initState();
    // unbounded:_ctrl.value 直接是 position(spring/friction simulation 输出),
    // 不限定在 [0, 1]。_offset 在 _handleAnimTick 中 clamp 到 [-_kOpenOffset, 0]。
    _ctrl = AnimationController.unbounded(vsync: this, value: 0);
    _ctrl.addListener(_handleAnimTick);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleAnimTick);
    _ctrl.dispose();
    super.dispose();
  }

  /// 动画 tick —— 直接用 _ctrl.value 作为 offset(spring/friction simulation)
  /// fling continuation 完成后切到 spring snap
  void _handleAnimTick() {
    if (!mounted) return;
    final wasAnimating = _ctrl.isAnimating;
    final raw = _ctrl.value;
    final clamped = raw.clamp(-_kOpenOffset, 0.0);
    setState(() {
      _offset = clamped;
    });
    // fling 撞墙 / 衰减完成后,根据当前位置 spring snap 到最近端点
    if (_isFlinging && !wasAnimating) {
      _isFlinging = false;
      final target = _offset.abs() > _kOpenOffset / 2 ? -_kOpenOffset : 0.0;
      _springTo(target);
    }
  }

  /// 用 spring 把 _offset 平滑带到 target —— iOS 风格弹性收敛
  /// velocity 传 fling 末速度,让 spring "惯性" 自然
  void _springTo(double target, {double velocity = 0}) {
    if ((_offset - target).abs() < 0.5) return;
    _ctrl.stop();
    // SpringSimulation 签名: (spring, start, end, velocity)
    // 之前我写成 (spring, start, velocity, end) → end=0 / velocity=target,导致动画方向错
    _ctrl.animateWith(
      SpringSimulation(_kSpring, _offset, target, velocity),
    );
  }

  /// 用 friction 让 _offset 自然减速 —— 模拟 fling 释放后的惯性滑动
  /// 衰减到 0 后由 _handleAnimTick 切到 spring snap
  void _flingWith(double velocity) {
    _ctrl.stop();
    _isFlinging = true;
    _ctrl.animateWith(
      FrictionSimulation(_kDrag, _offset, velocity),
    );
  }

  /// 用户开始拖动:立即停止正在进行的吸附动画,防止 drag 与 animation 并发修改 _offset
  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    _isFlinging = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final delta = d.primaryDelta!;
    // closed(_offset == 0)时右滑忽略(没什么可关闭);
    // 已开(_offset < 0)时右滑允许(用于关闭方向的手势,原生 iOS 标准)
    if (delta > 0 && _offset == 0) return;
    setState(() {
      _offset = (_offset + delta).clamp(-_kOpenOffset, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // 决定目标:
    //   - 划得够远 → open(不管速度,慢拖过阈值也应该锁开)
    //   - 快速左 fling → open(没划够也锁开)
    //   - 快速右 fling → close(强反向)
    //   - 其它 → close
    final shouldOpen = _offset.abs() > _kSnapThreshold ||
        velocity < _kFlingVelocity;

    if (velocity.abs() > _kFastFlingThreshold) {
      // 快速 fling:friction continuation + 完成后 spring snap 到最近端点
      _flingWith(velocity);
    } else {
      // 慢速:直接 spring snap(传部分 velocity 模拟惯性)
      _springTo(
        shouldOpen ? -_kOpenOffset : 0.0,
        velocity: velocity * 0.5,
      );
    }
  }

  void _close() {
    if (_offset != 0) _springTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 按钮"显现进度":_offset.abs() / 156。tile 滑得越多,按钮越显现,
    // 用 opacity 0→1 + Transform.translate(+12px → 0)双重过渡让按钮
    // "从 tile 背后挤出来"的感觉,而不是突然显示。
    final reveal = (_offset.abs() / _kOpenOffset).clamp(0.0, 1.0);
    final slideInOffset = (1 - reveal) * _kButtonSlideIn;

    return Stack(
      children: [
        // 底层:操作按钮条 — [编辑 76px][4px gap][删除 76px],圆角 brLg 跟 tile 对齐
        // 按钮跟随 _offset 渐显(opacity + translate),不再"突然出现"。
        // 左按钮(编辑)用主题色 primary,右按钮(删除)用 error 红 —— iOS 标准。
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
                  // 左按钮(编辑)—— Material Symbols Filled(variable font + FILL=1 via Text)
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 76,
                        child: Material(
                          color: theme.colorScheme.primary,
                          borderRadius: AppRadius.brLg,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onEdit,
                            child: const Center(
                              child: Text(
                                '\uf097',  // Material Symbols "edit" primary codepoint (支持 FILL axis)
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialSymbols',
                                  fontSize: 26,
                                  color: Colors.white,
                                  fontVariations: [FontVariation('FILL', 1)],
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 中间 4px surface 色 gap
                  const SizedBox(width: 4),
                  // 右按钮(删除)—— 同款 Filled + 红色 destructive 语义
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 76,
                        child: Material(
                          color: AppStatus.error,
                          borderRadius: AppRadius.brLg,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onDelete,
                            child: const Center(
                              child: Text(
                                '\ue92e',  // Material Symbols "delete"
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialSymbols',
                                  fontSize: 26,
                                  color: Colors.white,
                                  fontVariations: [FontVariation('FILL', 1)],
                                  height: 1.0,
                                ),
                              ),
                            ),
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
        // 上层:tile(随 _offset 水平平移)—— drag 1:1 跟随,松手才 snap
        // 外层 surface Container 占据整个 Stack 范围,挡住按钮漏色。
        // 用 key 标识,便于 widget 测试定位(其他 Transform 是按钮的 slide-in 偏移)
        Transform.translate(
          key: const ValueKey('tx-tile-transform'),
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