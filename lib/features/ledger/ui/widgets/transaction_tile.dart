// lib/features/ledger/ui/widgets/transaction_tile.dart
// 单条流水卡片:左分类色块 + 中描述 + 右金额
// 滑动交互:左滑露出 [编辑][删除] 两个按钮(各 76px),分别跳转编辑页 / 触发删除
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/theme/tx_display_style.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/gridly_banner.dart';
import '../../../../core/utils/excluded_from_totals.dart';
import '../../../../core/utils/refresh_providers.dart';
import '../../../../core/widgets/swipe_to_actions.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../settings/ui/widgets/asset_tile.dart';
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
        // 2026-10-20 D64.76 改:流水金额色 = 收支语义色(绿正 / 红负),不再按资产段色
        //   - user 反馈:"大问题的都是流动资金,就会有大面积的亮蓝色,有点不是很好分辨"
        //     cash_flow 段色 #0EA5E9 亮蓝铺满整屏,收入/支出只能读 +/- 符号区分
        //   - 选方案 1:金额走 TxDisplayStyle 集中表
        //     支出红 / 收入绿 / 调拨浅金(中性) / 借出橙 / 借入红
        //     跟"记一笔"大数字(AmountDisplay)同一张表 → 记与看完全一致
        //   - 资产段色**没丢**:退到账户 chip 的 icon 上(_SingleChip 仍走 AppSegment),
        //     "这笔属于哪个段"的信息还在,只是不再由金额承担
        //   - D51 决策保留:债务段用借出/借入语义色,不套用普通收支绿红
        // 2026-10-16 D64.77:prefix / label 也走 TxDisplayStyle 集中表
        final style = TxDisplayStyle.forType(transaction.type);
        final amountColor = style.color;
        // 2026-10-14 P18:不计入流水判断
        //   - 投资 record(cat.type='investment')→ 永远不计入(投资本质资产内部流转)
        //   - source asset.includeInTransactions=false → 不计入(user 在资产页关了开关)
        //   - monthSummary / _DaySection 跟这个标志同步,确保汇总排除
        // 2026-10-16 D64.78 改:走 core/utils/excluded_from_totals.dart 纯函数
        //   - 之前 inline isInvestmentRecord + txAsset.includeInTransactions
        //     跟 monthSummary / _DaySection 3 处同款重复
        final isExcludeFromTotals = isExcludedFromTotals(
          transaction,
          ref.watch(excludedFromTotalsIdsProvider),
        );
        // 2026-10-12 P3 commit:balance 流水不显示 ± prefix
        //   (调拨可正可负,跟"支出=负 / 收入=正"的语义不同)
        // 2026-10-14 D51 v2 改:lend_out / borrow_in 显示 ± prefix
        //   - 借出 lend_out = -"(我失去的钱,钱包出)
        //   - 借入 borrow_in = +"(我借到的可支配钱,钱包入)
        //   - balance 仍不显示 prefix(调拨,语义中性)
        //   - 这跟资产记录里"借出 += amount / 借入 -= amount"是相反的
        //     (ledger 走"现金流向"语义,asset 走"债务方向"语义,双视角)
        // 2026-10-16 D64.77 改:prefix 走 TxDisplayStyle 集中表(原本 4 case switch)
        final showPrefix = transaction.type != 'balance';
        final prefix = style.prefix;
        final theme = Theme.of(context);
        return SwipeToActions(
          key: ValueKey('tx-${transaction.id}'),
          tileId: transaction.id,
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
                            // 2026-10-14 D51 v2 改:借出/借入 record 显示 transaction.type 标签
                            //   而不是 cat.name("债务")
                            //   - cat.name 全是"债务"(同 cat.type='liability' 1 cat),
                            //     user 一眼看不出是哪类动作
                            //   - 改显示 transaction.type 标签,让"借出 / 借入 / 调拨"清晰
                            //   - 普通 record 仍走 cat.name(分类语义,如"餐饮"/"交通")
                            //   - 投资 record(investment cat)cat.name 区分"投资投入"/"投资收益",
                            //     也可走 cat.name;为了一致非 receivable 走 cat.name
                            child: Text(
                              _displayLabelFor(transaction.type, cat?.name),
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
                      const SizedBox(height: AppSpacing.s05),
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

  /// 2026-10-14 D51 v2 加:流水 tile 类型 label 优先走 transaction.type
  ///   - 借出 / 借入:cat 全是"债务"(同 1 cat),不显示 cat.name,改显示 transaction.type
  ///     (user:"类型应该就是 借入 和 借出")
  ///   - 其它 record:仍走 cat.name(分类语义)
  ///   - 调拨:balance type + destinationAccountId,显示 cat.name
  ///     (调拨是"从 A 到 B"的中性动作,显示 cat.name 如"投资"等)
  /// 2026-10-16 D64.77 改:label 走 TxDisplayStyle 集中表(原本 2 case switch)
  static String _displayLabelFor(String txType, String? catName) {
    // 借出 / 借入 显示 transaction.type label(因为同 cat 都 '债务',看不出动作)
    // 其它 record 走 cat.name(分类语义 / 投资 record 走"投资投入"/"投资收益")
    if (txType == 'lend_out' || txType == 'borrow_in') {
      return TxDisplayStyle.forType(txType).label;
    }
    return catName ?? '未分类';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 2026-10-14 P18:投资 record(投入/调拨)显示 source → dest 双账户
    //   - destinationAccountId != null → 嵌套 _SingleChip × 2,中间 → 符号
    //   - 现金 / 投资收益(单账户)→ 单 _SingleChip
    if (destinationAccountId != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SingleChip(accountId: accountId, maxWidth: 60),
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
            maxWidth: 60,
          ),
        ],
      );
    }
    // 单账户原逻辑
    return _SingleChip(accountId: accountId, maxWidth: 100);
  }
}

/// 2026-10-14 P18 抽:单账户 chip,投资 record 双账户时复用 2 次
class _SingleChip extends ConsumerWidget {
  const _SingleChip({
    required this.accountId,
    required this.maxWidth,
  });
  final int accountId;
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
    // 2026-10-16 D64.73 改:不再传 iconFor callback,直接走 AssetTile.icons
    //   集中表,新加 icon key 一处改完全部生效
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          AssetTile.icons[asset.icon] ?? Icons.account_balance_wallet_rounded,
          size: 12,
          color: color,
        ),
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

// ============================================================
// 滑动操作 wrapper:2026-10-16 D64.42 抽到 lib/core/widgets/swipe_to_actions.dart
//   (原 `_SwipeToDelete` 是 private,只在 transaction_tile 用,跟资产 / 未来分类
//   tile 风格不统一;抽成 public `SwipeToActions` 后流水 / 资产共用同一套交互)
// ============================================================

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
    final amountColor = isIncome
        // D64.75:小结/预览正负恒定绿/红(不跟 palette 走)
        ? AppSemantic.income
        : AppSemantic.expense;
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
                          const SizedBox(height: AppSpacing.s05),
                          Text(
                            Formatters.shortDate(transaction.occurredAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (transaction.note != null &&
                              transaction.note!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.s05),
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
