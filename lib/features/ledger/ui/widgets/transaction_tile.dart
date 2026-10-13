// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 滑动交互:左滑露出 [编辑][删除] 两个按钮(各 76px),分别跳转编辑页 / 触发删除
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/gridly_banner.dart';
import '../../../../core/utils/refresh_providers.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../application/transactions_providers.dart';

/// 2026-10-11 UAT:tile 的外边距跟按钮层的内边距必须严格一致(都是 16/4),
/// 否则视觉上"tile 跟按钮不在同一条对齐线上"。改任一处只改这两个常量,不会飘。
const double _kRowHorizontalInset = AppSpacing.s4; // 16
const double _kRowVerticalInset = AppSpacing.s1; // 4

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
        // 2026-10-14 P18:流水金额色 = accountId 对应资产段色
        //   - 跟 _AccountBadge icon 色统一(都按 asset.type 段色)
        //   - 跨页视觉一致:流水页 + 资产页 6 段色用同一 token
        //   - prefix 仍按 transaction.type 分(+/-/空)区分收入/支出/调拨
        //   - user 反馈:'流水颜色保持一致,不然不够好看'
        // 2026-10-14:asset.type 走 AppSegment,asset 找不到时 fallback 用 transaction.type 段
        final txAssetAsync = ref.watch(
          assetByIdProvider(transaction.accountId),
        );
        final txAsset = txAssetAsync.valueOrNull;
        final accountType =
            txAsset?.type ?? _fallbackAccountType(transaction.type);
        final amountColor = AppSegment.colorFor(accountType);
        // 2026-10-14 P18:不计入流水判断
        //   - 投资 record(cat.type='investment')→ 永远不计入(投资本质资产内部流转)
        //   - source asset.includeInTransactions=false → 不计入(user 在资产页关了开关)
        //   - monthSummary / _DaySection 跟这个标志同步,确保汇总排除
        final isInvestmentRecord = cat?.type == 'investment';
        final isExcludeFromTotals =
            isInvestmentRecord || (txAsset?.includeInTransactions == false);
        // 2026-10-12 P3 commit:balance 流水不显示 ± prefix
        //   (调拨可正可负,跟"支出=负 / 收入=正"的语义不同)
        final showPrefix = transaction.type != 'balance';
        final prefix = switch (transaction.type) {
          'income' => '+',
          'expense' => '-',
          _ => '',
        };
        final theme = Theme.of(context);
        return _SwipeToDelete(
          key: ValueKey('tx-${transaction.id}'),
          transactionId: transaction.id,
          onDelete: () => _onDeleteRequested(context, ref, cat),
          onEdit: () => _onEditRequested(context),
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: _kRowHorizontalInset,
              vertical: _kRowVerticalInset,
            ),
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1.0, // 全卡片统一:0.5 → 1.0
              ),
              boxShadow: CardShadows.light(context),
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
                      // 2026-10-14 P18 改:2×2 矩阵布局(分类名+金额 / 备注+资产账号)
                      //   第 1 行:分类名(15sp w500 onSurface,左)+ 金额(16sp w600,右)
                      //     主体信息,字号大,信息最关键
                      //   第 2 行:备注(12sp onSurfaceVariant,左,小一号)+ 资产账号(11sp 角标,右)
                      //     辅助信息,字号小,即便 2 行也不显挤
                      //   高度:始终 2 行(无备注时第 2 行只显账号,空白 slot 在左侧)
                      //   user 反馈:比 inline 方案视觉层级更清晰,主/辅分明
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              cat?.name ?? '未分类',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 2026-10-14 P18:不计入流水灰色 chip
                          //   - 投资 record(cat.type='investment')或 source.includeInTransactions=false
                          //   - 跟 monthSummary / _DaySection 同步排除规则
                          //   - 灰色胶囊,10sp,AppGray 配色,跟 tile 视觉不抢戏
                          if (isExcludeFromTotals) ...[
                            const SizedBox(width: AppSpacing.s2),
                            const _ExcludeFromTotalsChip(),
                          ],
                          const SizedBox(width: AppSpacing.s2),
                          Text(
                            // 2026-10-12 P3:balance 流水不显示 ± prefix(正负自定)
                            showPrefix
                                ? '$prefix ¥${Formatters.amount(transaction.amount)}'
                                : '¥${Formatters.amount(transaction.amount)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 备注(占第 2 行左半,无时空白占位)
                          Expanded(
                            child: Text(
                              transaction.note ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 2026-10-12 P3 commit:流水 tile 第 2 行右侧资产账号 chip
                          //   小尺寸 11px,onSurfaceVariant 色
                          //   让 user 在流水列表一眼看到"哪笔进哪个账户"
                          // 2026-10-14 P18:投资 record 投入/调拨传 destinationAccountId
                          //   显示 source → dest 双账户 chip,跟 record 的资产流向对应
                          const SizedBox(width: AppSpacing.s2),
                          _AccountBadge(
                            accountId: transaction.accountId,
                            destinationAccountId:
                                transaction.destinationAccountId,
                          ),
                        ],
                      ),
                    ],
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

  /// 点击删除按钮触发:先弹中央确认 dialog,user 真正点"确认删除"才删。
  ///
  /// 2026-10-12 加(commit 67):user 反馈"数据是最重要的",加确认屏障防误删。
  /// 流程:
  ///   1. 弹 _DeleteConfirmDialog(modal,barrier 可 dismiss = 等价取消)
  ///   2. user 选"取消"或 barrier dismiss → 直接 return,**不删**
  ///   3. user 选"确认删除" → 真正调 repository.delete + invalidate 缓存 + SnackBar
  ///   4. AppHaptics:取消 tap(轻),确认 delete warning(中量 — destructive action 信号)
  /// 5. SnackBar 保留:告知"已删除",跟主流程一致
  /// (没加 undo SnackBar 的 reason:确认 dialog 已经给了 user 显式机会,
  /// undo 是"删完了还能反悔",跟 user 当前诉求"先确认再删"是不同范式)
  Future<void> _onDeleteRequested(
    BuildContext context,
    WidgetRef ref,
    Category? cat,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true, // 点 dialog 外面 = 取消
      builder: (ctx) =>
          _DeleteConfirmDialog(transaction: transaction, cat: cat),
    );
    if (confirmed != true) return;

    // 真正删除 + 广谱 invalidate + SnackBar
    await ref.read(transactionRepositoryProvider).delete(transaction.id);
    refreshAllData(ref);
    if (context.mounted) {
      showGridlyBanner(context, '已删除', kind: GridlyBannerKind.success);
    }
  }

  /// 点击编辑按钮触发:在当前 tab 弹出 sheet 编辑(预填 + 保存 update),
  /// 关闭 sheet 不跳路由,保留流水列表可见 / 不丢上下文
  /// 点击编辑按钮触发:push 全屏编辑路由(/edit/:id)。
  /// 2026-10-11 改:之前用 showEditTransactionSheet(modal sheet),
  /// sheet 内部 AnimatedPadding 把 Numpad 推上去不被键盘覆盖。
  /// 改成全屏跟 AddTransactionPage 一致,Numpad 真被键盘盖住。
  /// 代价:流水列表暂时被盖掉(失去"在当前 tab 编辑"上下文)。
  void _onEditRequested(BuildContext context) {
    context.push('/edit/${transaction.id}');
  }

  /// 2026-10-14 P18:asset 还没加载或找不到时,根据 transaction.type 推断 fallback 段
  ///   - expense/income/balance 多数是 cash_flow(日常流水/工资/调拨)
  ///   - 投资 record 走 type='income'/'balance',但 fallback 仍是 cash_flow(暂态)
  ///     asset loaded 后会变正确段色
  static String _fallbackAccountType(String txType) {
    return 'cash_flow'; // 多数流水属 cash_flow 段
  }
}

/// 2026-10-12 P3 commit 加:流水 tile 下的资产角标(单行 11px 小字 + icon)
///   - assetByIdProvider 取账户对象(找不到 → 显示 'unknown 账户')
///   - 用 AssetTile.icons 风格的小 icon(14px,asset 配色)
///   - 不显示余额(余额已在 SummaryCard 显示,避免重复)
/// 2026-10-14 P18 扩展:投资 record 投入/调拨需要显示 source → dest 双账户
///   - destinationAccountId != null → 显示 [source chip] → [dest chip]
///   - destinationAccountId == null → 维持单账户 chip
class _AccountBadge extends ConsumerWidget {
  const _AccountBadge({required this.accountId, this.destinationAccountId});
  final int accountId;

  /// 投资 record 投入/调拨的目标账户,nullable
  ///   - 非空 → 显示 source → dest 双账户 chip
  ///   - 空(现金流水 / 投资收益)→ 只显示 source 单账户
  final int? destinationAccountId;

  IconData _iconFor(String iconKey) {
    switch (iconKey) {
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      case 'swap_horiz':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 2026-10-14 P18:投资 record(投入/调拨)显示 source → dest 双账户
    //   - destinationAccountId != null → 嵌套 _SingleChip × 2,中间 → 符号
    //   - 现金 / 投资收益(单账户)→ 单 _SingleChip
    if (destinationAccountId != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SingleChip(accountId: accountId, iconFor: _iconFor, maxWidth: 60),
          // 中间 → 符号(中性灰,10sp)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 11,
              color: AppGray.g400,
            ),
          ),
          _SingleChip(
            accountId: destinationAccountId!,
            iconFor: _iconFor,
            maxWidth: 60,
          ),
        ],
      );
    }
    // 单账户原逻辑
    return _SingleChip(accountId: accountId, iconFor: _iconFor, maxWidth: 100);
  }
}

/// 2026-10-14 P18 抽:单账户 chip,投资 record 双账户时复用 2 次
class _SingleChip extends ConsumerWidget {
  const _SingleChip({
    required this.accountId,
    required this.iconFor,
    required this.maxWidth,
  });
  final int accountId;
  final IconData Function(String) iconFor;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetByIdProvider(accountId));
    final asset = assetAsync.valueOrNull;
    final theme = Theme.of(context);
    if (asset == null) {
      return Text(
        'unknown',
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    // 2026-10-14 P18:icon 色从账户自选 asset.color 改资产段色(asset.type 走 AppSegment)
    //   跟流水金额色统一,跨页视觉一致
    final color = AppSegment.colorFor(asset.type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconFor(asset.icon), size: 12, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(
            asset.name,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 手势滑动展开操作按钮 —— 类似 iOS Mail.app 的滑动效果
///   - 左滑超过阈值 → snap 露出 [编辑][删除] 两个操作按钮(不执行)
///   - 编辑按钮可点 → 触发 onEdit
///   - 删除按钮可点 → 触发 onDelete
///   - 点 tile 其他位置 → 自动弹回关闭
class _SwipeToDelete extends ConsumerStatefulWidget {
  const _SwipeToDelete({
    super.key,
    required this.transactionId,
    required this.child,
    required this.onDelete,
    required this.onEdit,
  });

  /// 流水 id,2026-10-11 UAT:加进来是为了注册到 openSwipeTileIdProvider,
  /// 让 LedgerPage 的全局 tap handler 能找到要收回的 tile。
  final int transactionId;
  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  ConsumerState<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends ConsumerState<_SwipeToDelete>
    with SingleTickerProviderStateMixin {
  /// 划开的固定宽度(px)—— 露出 [编辑 76 + 4 gap + 删除 76 = 156]px 的按钮区域
  /// (中间留 4px surface 色 gap 让两个按钮视觉独立,不粘成一条)
  // 2026-10-11:b80a636 删 outer Container 后,从 156 → 140(去掉 16 outer Container 错位):
  //   widget.child margin s4 在 buttons 区域往左推 16,加上 8px 视觉间隙 = 132 + 8 = 140
  static const double _kOpenOffset = 140;

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
    _ctrl.animateWith(SpringSimulation(_kSpring, _offset, target, velocity));
  }

  /// 用 friction 让 _offset 自然减速 —— 模拟 fling 释放后的惯性滑动
  /// 衰减到 0 后由 _handleAnimTick 切到 spring snap
  void _flingWith(double velocity) {
    _ctrl.stop();
    _isFlinging = true;
    _ctrl.animateWith(FrictionSimulation(_kDrag, _offset, velocity));
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
    final shouldOpen =
        _offset.abs() > _kSnapThreshold || velocity < _kFlingVelocity;

    if (shouldOpen) {
      // 2026-10-11 UAT:注册自己到 openSwipeTileIdProvider,
      // 让 LedgerPage 的全局 tap handler 能找到要关掉的 tile,
      // 实现"点屏幕任何地方,正在开的 tile 自动收回"。
      ref.read(openSwipeTileIdProvider.notifier).state = widget.transactionId;
    }

    if (velocity.abs() > _kFastFlingThreshold) {
      // 快速 fling:friction continuation + 完成后 spring snap 到最近端点
      _flingWith(velocity);
    } else {
      // 慢速:直接 spring snap(传部分 velocity 模拟惯性)
      _springTo(shouldOpen ? -_kOpenOffset : 0.0, velocity: velocity * 0.5);
    }
  }

  void _close() {
    if (_offset != 0) _springTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 2026-10-11 UAT:监听 openSwipeTileIdProvider。
    //   - 如果 provider 变成 null 或别人的 id(说明外面被点了),而且我自己正开着,
    //     就 spring 回 0 收回。
    ref.listen<int?>(openSwipeTileIdProvider, (prev, next) {
      if (next != widget.transactionId && _offset < 0) {
        _springTo(0);
      }
    });
    // 按钮"显现进度":_offset.abs() / 156。tile 滑得越多,按钮越显现,
    // 用 opacity 0→1 + Transform.translate(+12px → 0)双重过渡让按钮
    // "从 tile 背后挤出来"的感觉,而不是突然显示。
    final reveal = (_offset.abs() / _kOpenOffset).clamp(0.0, 1.0);
    final slideInOffset = (1 - reveal) * _kButtonSlideIn;

    return Stack(
      children: [
        // 底层:操作按钮条 — [编辑 76px][4px gap][删除 76px],brLg 圆角矩形 + elevation 2
        // 2026-10-11 UAT 反馈:胶囊"丑且太大",退回圆角矩形,加 elevation 落影
        // 按钮跟随 _offset 渐显(opacity + translate),不再"突然出现"。
        // 左按钮(编辑)用主题色 primary,右按钮(删除)用 error 红 —— iOS 标准。
        // 外层 surface Container(color: surface) 占据整个 Stack 范围挡住按钮漏色。
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kRowHorizontalInset,
              vertical: _kRowVerticalInset,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 左按钮(编辑)—— teal 太鲜艳,加 elevation=4 + shadowColor=black38 让它"压下去"一点
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 64,
                        child: Material(
                          color: theme.colorScheme.primary,
                          borderRadius: AppRadius.brLg,
                          elevation: 4,
                          shadowColor: Colors.black38,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onEdit,
                            child: const Center(
                              child: Text(
                                '\ue3c9', // Material Icons Round "edit"
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialIconsRound',
                                  fontSize: 32,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(color: Colors.white, blurRadius: 2),
                                  ],
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
                  // 右按钮(删除)—— 同款 Round + 红色 destructive 语义,跟编辑按钮同款 elevation
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 64,
                        child: Material(
                          color: AppStatus.error,
                          // 跟编辑按钮一致:brLg 圆角矩形 + elevation=4 落影
                          borderRadius: AppRadius.brLg,
                          elevation: 4,
                          shadowColor: Colors.black38,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onDelete,
                            child: const Center(
                              child: Text(
                                '\ue872', // Material Icons Round "delete"
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialIconsRound',
                                  fontSize: 32,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(color: Colors.white, blurRadius: 2),
                                  ],
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
        // 2026-10-11 UAT:b80a636 试过保留 outer Container(用户觉得拥挤),
        // 现在删掉 outer Container,接受 tile 圆角处可能漏一点点按钮色。
        // _kOpenOffset 从 156 → 140(去掉 outer Container 多算的 16)。
        // 用 key 标识,便于 widget 测试定位(其他 Transform 是按钮的 slide-in 偏移)
        Transform.translate(
          key: const ValueKey('tx-tile-transform'),
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: () {
              // 2026-10-11 UAT:tile 收回不能只靠 LedgerPage body 的全局
              // GestureDetector(translucent),因为子 tile 自己的 opaque
              // GestureDetector 会"吃掉"点击事件,body.onTap 根本收不到。
              // 改成 tile 自身 onTap 时主动清 openSwipeTileIdProvider:
              //   - 点开着的 tile 自己 → provider 清成 null,ref.listen 触发
              //     二次 _springTo(0)(无害二次 snap)
              //   - 点另一个 closed tile → provider 清成 null,开着的 tile
              //     通过 ref.listen(next=null != myId && _offset<0)自己收回
              //   - 点编辑/删除按钮 → InkWell 消耗 tap,tile.onTap 不触发,
              //     provider 不动(预期:点按钮不动 tile 状态)
              ref.read(openSwipeTileIdProvider.notifier).state = null;
              _close();
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// 删除确认 modal dialog(commit 67,user 强调"数据是最重要的")
///
/// 设计要点:
///   - 中央 modal 比底部 sheet 更"严肃":destructive action 必须强制 user
///     停下当前手势、看明白要删什么、再决定。底部 sheet 容易被忽略。
///   - barrierDismissible=true(主 widget 设置):点 dialog 外面 = 取消,等于
///     显式"反悔",不删。
///   - 内容布局:头部 destructive icon + 标题 → 流水预览(分类图 + 名称 + 日期
///     + 备注 + 金额)→ 警示文案"数据本地存储,删除后无法恢复" → 两个按钮
///     [取消](outline)/ [确认删除](error 实心红)
///   - 触觉:打开 dialog 不加(让动画自己呈现 destructive 视觉);取消 tap;
///     确认删除 warning(中量,跟 destructive 语义对齐)
///   - 不用 Material 自带 AlertDialog 是因为它的 contentPadding / insetPadding
///     在视觉上太"系统默认",跟 gridly 卡片化的调性不贴。自绘 dialog 跟
///     现有 CardShadows.brLg 卡片风格一致。
class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.transaction, required this.cat});

  final Transaction transaction;
  final Category? cat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // cat 是 _DeleteConfirmDialog 的 final field,Dart 不在三元 else 分支提升
    // (cat.color 报 unchecked_use_of_nullable_value)。先 hoist 到 local var,
    // local final 可提升 → ternary 内部 catColor.cat 拿到 Category 类型。
    final Category? catOrNull = cat;
    final catColor = catOrNull == null ? AppGray.g400 : Color(catOrNull.color);
    final isIncome = transaction.type == 'income';
    final amountColor = isIncome ? AppBrand.gold : AppStatus.error;
    final amountPrefix = isIncome ? '+' : '-';

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      // 去掉 Material default 的蓝色 tint overlay(避免 surface 跟卡片调性冲突)
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部:destructive icon + 标题
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppStatus.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppStatus.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Text(
                      '删除这笔流水?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              // 流水预览卡片(让 user 看清要删什么 — 防误删最关键的一步)
              Container(
                padding: const EdgeInsets.all(AppSpacing.s3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.12),
                        borderRadius: AppRadius.brXs,
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.map[cat?.icon ?? 'category'] ??
                            Icons.category_rounded,
                        color: catColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat?.name ?? '未分类',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Formatters.shortDate(transaction.occurredAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
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
                      '$amountPrefix ¥${Formatters.amount(transaction.amount)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              // 警示文案
              Text(
                '数据本地存储,删除后无法恢复',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              // 按钮:[取消](outline)/ [确认删除](error 红实心)
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.brMd,
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                            width: 1.0,
                          ),
                        ),
                      ),
                      onPressed: () {
                        AppHaptics.tap();
                        Navigator.of(context).pop(false);
                      },
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppStatus.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.brMd,
                        ),
                      ),
                      onPressed: () {
                        AppHaptics.warning();
                        Navigator.of(context).pop(true);
                      },
                      child: const Text(
                        '确认删除',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2026-10-14 P18:不计入流水 chip
///   - 标记:投资 record 或 source asset.includeInTransactions=false 的流水
///   - 视觉:跟 gridly 现有 chip 一致(参考 _TileChip)
///     AppGray.g600 alpha 0.12 浅色填充 + 同色文字,无边框(去边框避免割裂)
///   - 圆角 6px(更柔和,接近 ColorOS tag 风格)
///   - 跟 monthSummary / _DaySection 同步排除规则
class _ExcludeFromTotalsChip extends StatelessWidget {
  const _ExcludeFromTotalsChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppGray.g600.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '不计入流水',
        style: TextStyle(
          fontSize: 10,
          color: AppGray.g600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
