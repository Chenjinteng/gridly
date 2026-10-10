// lib/features/home/ui/home_page.dart
// 首页(极简版):LOGO + 产品名居中 + 月度汇总卡 + 预算卡 + 下拉刷新
// 产品名"格子记账"放在 LOGO 下方,跟 LOGO 组成品牌标识
// 已删除"最近 5 条流水"列表(避免与流水 Tab 重复,且占首屏空间)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/gridly_mark.dart';
import '../../ledger/application/transactions_providers.dart';
import '../../ledger/ui/widgets/monthly_summary.dart';
import 'widgets/budget_progress.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // 不设 AppBar.title —— 产品名"格子记账"挪到 body 内 LOGO 下方
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(monthTransactionsProvider);
          ref.invalidate(allTransactionsByDayProvider);
        },
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              // 至少撑满一屏,让内容垂直居中(ConstraintLayout 模式)
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s6,
                    AppSpacing.s4,
                    AppSpacing.s8, // 留出底部 nav bar 空间
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      // LOGO + 产品名 —— 居中组成品牌标识
                      const Center(
                        child: GridlyMark(size: 96),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      const Center(
                        child: Text(
                          '格子记账',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      // 月度汇总(本月结余 + 收入/支出 + 日均支出)
                      const MonthlySummary(),
                      const SizedBox(height: AppSpacing.s4),
                      // 预算进度
                      const BudgetProgress(),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}