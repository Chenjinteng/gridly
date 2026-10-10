// lib/features/ledger/ui/widgets/monthly_summary.dart
// 月度汇总 —— 设计成"Excel 工作表"风格,呼应"格子"主题:
//   - 顶部 sheet title(深色底 + 金色 1.5px 下边 + LOGO + 月份)
//   - 主数字区(深色底):本月结余大字
//   - 日均支出(深色底,大数字下方一行小字)
//   - 收入 / 支出两个 cell,中间 1px 分隔线(深色画在亮一点的颜色上)
//   - v0.2.0 起,支出 cell 内追加"日均 ¥xxx"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final now = DateTime.now();
    final sheetTitle = '${now.year}年${now.month}月';
    final theme = Theme.of(context);
    // 日均支出 = 当月支出 / 当日已过天数(月初时 = 当日)
    final dailyAvg =
        now.day > 0 ? summary.expense / now.day : summary.expense;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
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
                  const Text(
                    '本月结余',
                    style: TextStyle(color: AppGray.g400, fontSize: 11),
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
                  '¥${Formatters.amount(summary.balance)}',
                  style: const TextStyle(
                    color: AppSecondary.cream,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // 收入 / 支出 两列 cell
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Cell(
                      label: '收入',
                      amount: summary.income,
                      color: AppBrand.gold,
                      showDivider: true,
                    ),
                  ),
                  Expanded(
                    child: _Cell(
                      label: '支出',
                      amount: summary.expense,
                      color: AppBrand.teal,
                      showDivider: false,
                      dailyAverage: dailyAvg,
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
    this.dailyAverage,
  });
  final String label;
  final double amount;
  final Color color;
  final bool showDivider;
  final double? dailyAverage;

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
            color: AppBrand.charcoal,
            width: 0.5,
          ),
          left: showDivider
              ? const BorderSide(
                  color: AppBrand.charcoal,
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
            '¥${Formatters.amount(amount)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (dailyAverage != null) ...[
            const SizedBox(height: 4),
            Text(
              '日均 ¥${Formatters.amount(dailyAverage!)}',
              style: const TextStyle(
                color: AppGray.g400,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}