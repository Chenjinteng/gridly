// lib/features/home/ui/home_page.dart
// 首页(极简版):LOGO + 产品名居中 + 月度汇总卡 + 预算卡 + 下拉刷新
// 产品名"格子记账"放在 LOGO 下方,跟 LOGO 组成品牌标识
// 已删除"最近 5 条流水"列表(避免与流水 Tab 重复,且占首屏空间)
//
// D70.3 改(2026-10-19,user 1.0.1 装机实测反馈):
//   - 历史:本地状态先后用 StateProvider(D64.51)→ widget-local(D70.3 第一稿
//     只改 MonthlySummary,导致 MonthlySummary 和 BudgetProgress "分裂":
//     点月度汇总卡眼睛按钮,预算卡不动,行为不一致)
//   - 改为把 _localVisible 提升到 HomePage 层:
//     · MonthlySummary(有按钮)+ BudgetProgress(无按钮)都从 props 拿同一个 localVisible
//     · 切 tab 走 shell AnimatedSwitcher -> 旧 HomePage 销毁,新 HomePage initState
//       把 _localVisible 重置为 true(跟 global 一致)
//     · 两张卡 hidden 公式统一为 hidden = global ^ localVisible(XOR)
//   - 删掉 homeAmountVisibilityProvider / combineAmountVisibilityProvider,
//     单一 source of truth 在这里(HomePage._HomePageState._localVisible)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/widgets/gridly_mark.dart';
import '../../ledger/ui/widgets/monthly_summary.dart';
import 'widgets/budget_progress.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // D70.3:local "显示金额" 状态 —— widget-local 在 HomePage 层
  //   - 默认 true(跟 global 默认一致)
  //   - 切 tab 走 shell AnimatedSwitcher 销毁旧 widget,新 widget initState
  //     把 _localVisible 重置为 true(session-bound,不持久化)
  //   - MonthlySummary(有按钮) 和 BudgetProgress(无按钮) 都通过 props 共享
  //     同一个 _localVisible,避免两张卡行为分裂
  bool _localVisible = true;

  void _toggleLocal() {
    setState(() => _localVisible = !_localVisible);
  }

  @override
  Widget build(BuildContext context) {
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
              // D70.3:把 _localVisible 提升到 HomePage 后,这里从 props 传入
              //   shared state;MonthlySummary 持有的眼睛按钮 onTap → onToggleLocal
              MonthlySummary(
                localVisible: _localVisible,
                onToggleLocal: _toggleLocal,
              ),
              const SizedBox(height: AppSpacing.s3), // 原 s4=16,降到 12
              // 预算进度(无预算时 SizedBox.shrink,不影响布局)
              // D70.3:传 localVisible 让两张卡共享,行为一致(同月隐藏/同月显示)
              BudgetProgress(localVisible: _localVisible),
            ],
          ),
        ),
      ),
    );
  }
}
