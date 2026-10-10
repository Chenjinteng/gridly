// lib/features/ledger/ui/widgets/monthly_summary.dart
// 月度汇总 —— 设计成"Excel 工作表"风格,呼应"格子"主题:
//   - 顶部 sheet title(深色底 + 金色 1.5px 下边 + LOGO + 月份)
//   - 主数字区(深色底):本月结余大字
//   - 收入 / 支出两个 cell(等高,IntrinsicHeight 强制),中间 1px 分隔线
//   - 日均支出行(底部独立小行),防止 cell 内容不对称导致底不齐
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/settings/amount_visibility_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/gridly_mark.dart';
import '../../application/transactions_providers.dart';

class MonthlySummary extends ConsumerWidget {
  const MonthlySummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider);
    // hidden = 关闭了金额可见性(防偷窥)
    final hidden = !ref.watch(amountVisibilityProvider);
    final now = DateTime.now();
    final sheetTitle = '${now.year}年${now.month}月';
    // 日均支出 = 当月支出 / 当日已过天数(月初时 = 当日)
    final dailyAvg =
        now.day > 0 ? summary.expense / now.day : summary.expense;

    // 金额文本:隐藏时显示「¥ •••••」占位(位数感保留),不暴露具体数字
    String amountText(double v) => hidden ? '••••••' : '¥${Formatters.amount(v)}';

    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: AppBrand.gold, // 格子主题 · 改用品牌金(原 outlineVariant 太浅)
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部 sheet title(浅色底)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              decoration: const BoxDecoration(
                color: AppBrand.ink,
                border: Border(
                  bottom: BorderSide(color: AppBrand.gold, width: 1.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // LOGO 三色方块 mark(深色底上,Ink → cream)
                      const GridlyMark(size: 26, onDark: true),
                      const SizedBox(width: AppSpacing.s2),
                      Text(
                        sheetTitle,
                        style: const TextStyle(
                          color: AppSecondary.cream,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  // 眼睛按钮 —— 切换金额显示/隐藏
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        ref.read(amountVisibilityProvider.notifier).toggle(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            hidden ? '显示金额' : '本月结余',
                            style: TextStyle(
                              color: hidden
                                  ? AppSecondary.cream
                                  : AppGray.g400,
                              fontSize: 11,
                              fontWeight:
                                  hidden ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 14,
                            color: hidden
                                ? AppSecondary.cream
                                : AppGray.g400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 主体:大数字区
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              color: AppBrand.ink,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  amountText(summary.balance),
                  style: TextStyle(
                    color: hidden ? AppGray.g400 : AppSecondary.cream,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // 收入 / 支出 两列 cell(等高,内容对称)
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Cell(
                      label: '收入',
                      amount: hidden ? null : summary.income,
                      color: AppBrand.gold,
                      showDivider: true,
                    ),
                  ),
                  Expanded(
                    child: _Cell(
                      label: '支出',
                      amount: hidden ? null : summary.expense,
                      color: AppStatus.error,
                      showDivider: false,
                    ),
                  ),
                ],
              ),
            ),
            // 日均支出行(独立底部,避免两 cell 内容不对齐)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              decoration: const BoxDecoration(
                color: AppBrand.ink,
                border: Border(
                  top: BorderSide(color: AppBrand.gold, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '日均支出',
                    style: TextStyle(color: AppGray.g400, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    hidden ? '••••••' : '¥${Formatters.amount(dailyAvg)}',
                    style: TextStyle(
                      color: hidden ? AppGray.g400 : AppStatus.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.amount,
    required this.color,
    required this.showDivider,
  });
  final String label;

  /// null = 隐藏(显示 ••••••)
  final double? amount;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: AppBrand.ink,
        border: Border(
          top: const BorderSide(
            color: AppBrand.gold, // 格子主题 · 改用品牌金
            width: 0.5,
          ),
          left: showDivider
              ? const BorderSide(
                  color: AppBrand.gold, // 格子主题 · 改用品牌金
                  width: 0.5,
                )
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppGray.g400, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            amount == null ? '••••••' : '¥${Formatters.amount(amount!)}',
            style: TextStyle(
              color: amount == null ? AppGray.g400 : color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}