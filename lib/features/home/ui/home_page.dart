// lib/features/home/ui/home_page.dart
// 首页(极简版):LOGO + 产品名居中 + 月度汇总卡 + 预算卡 + 下拉刷新
// 产品名"格子记账"放在 LOGO 下方,跟 LOGO 组成品牌标识
// 已删除"最近 5 条流水"列表(避免与流水 Tab 重复,且占首屏空间)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/widgets/gridly_mark.dart';
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
        onRefresh: () async => refreshAllData(ref),
        child: SingleChildScrollView(
          // AlwaysScrollableScrollPhysics 让 RefreshIndicator 在内容未溢出时也能下拉刷新
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4, // horizontal
            AppSpacing.s4, // top —— 原 s6=32,降到 16 让 splash 区紧凑
            AppSpacing.s4,
            AppSpacing.s6, // bottom —— 原 s8=48,降到 32 够 nav bar 留位
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.s6), // splash 顶部呼吸区
              // LOGO + 产品名 —— 紧凑居中组成品牌标识
              // 深色模式下 ink 块自动变 cream(GridlyMark.onDark),避免和 Ink 背景融掉
              Center(
                child: GridlyMark(
                  size: 80,
                  onDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ), // 原 96
              const SizedBox(height: AppSpacing.s2), // 原 s3=12,降到 8
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
              const SizedBox(height: AppSpacing.s3), // 原 s5=24,降到 12
              // 月度汇总(本月结余 + 收入/支出 + 日均支出)
              const MonthlySummary(),
              const SizedBox(height: AppSpacing.s3), // 原 s4=16,降到 12
              // 预算进度(无预算时 SizedBox.shrink,不影响布局)
              const BudgetProgress(),
            ],
          ),
        ),
      ),
    );
  }
}