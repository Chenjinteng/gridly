// lib/features/stats/ui/widgets/debt_dashboard.dart
// 报表"资产"视角 —— 债务情况 tabbed 卡片(负债 | 借出)
//
// 2026-10-16 D64.64 加(user UAT 反馈):
//   - user 反馈"我感觉,负债和借出这两个卡片可以合起来用一个 tab 切换的方式,
//     卡片名就叫债务情况,两个tab,负债|借出"
//   - 之前 D64.56/D64.62 是两张独立卡片(LiabilitiesDashboard + ReceivablesDashboard),
//     信息密度 2 张卡 user 觉得冗余,合并成 1 张 tabbed 卡片更紧凑
//   - 修法:本 widget 是"债务情况"卡片容器,内部包 DefaultTabController +
//     TabBar(负债 | 借出)+ TabBarView(body 切 LiabilitiesDashboard /
//     ReceivablesDashboard 两个"纯 body"子 widget)
//   - ink 底容器(警示色,跟负债语义一致)+ 1px outline + CardShadows.dark,
//     跟原 LiabilitiesDashboard 视觉系统一致
//
// 设计要点:
//   - 卡片容器本身是 ink 底(警示色),不是 LiabilitiesDashboard 的内部
//     Container(已被改成纯 body);ReceivablesDashboard 原 surface 白底
//     改为放在 ink 底里(body 白色跟深色卡片共存,user 一眼看出"借出"跟
//     "负债"在同一卡片)
//   - 标题"债务情况"统一在卡片顶部(TabBar 在标题右侧)
//   - TabBar 风格:underline 横条 teal(跟 ConsumptionTrend 同款),不用
//     pill bg(避免"借出"显示成 pill 阴影)— 跟 assets tab 的 _CompactViewSegmented
//     同款横条滑动
//   - body 切 TabBarView(横向禁止滑动,只允许 tap 切 tab — NeverScrollableScrollPhysics),
//     避免误滑触发 + 跟 ConsumptionTrend 同款策略
//   - TabBarView 自动按 IndexedStack 风格保持子 widget 状态(切回"负债"tab 时
//     大字 AnimatedCounter 数字滚动重新触发;这跟之前单独两张卡的体验一致,
//     user 切 tab 时看到数字入场滚动反而强化"警示"反馈)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import 'liabilities_dashboard.dart';
import 'receivables_dashboard.dart';

/// 报表"债务情况" tabbed 卡片
///   - 1 张卡片(ink 底)+ 2 个 tab 切换(负债 | 借出)
///   - body 切 LiabilitiesDashboard / ReceivablesDashboard 两个纯 body
class DebtDashboard extends ConsumerWidget {
  const DebtDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DefaultTabController(
      length: 2,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        decoration: BoxDecoration(
          // ink 底警示色,跟原 LiabilitiesDashboard 一致 — user 切到"负债"
          // tab 看到警示红字数字,切到"借出" tab 看到 teal 字数字,警示色/
          // 友好色都包在同一个 ink 卡片里,user 一眼区分
          color: AppBrand.ink,
          borderRadius: AppRadius.brLg,
          // rim light border + 阴影,跟 AssetSummaryCard / 净资产卡一致
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
            width: 1.0,
          ),
          boxShadow: CardShadows.dark(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 卡片顶部 row:左侧标题"债务情况" + 右侧 TabBar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 标题"债务情况"(D64.64:user 明确卡片名)
                  const Text(
                    '债务情况',
                    style: TextStyle(
                      color: AppGray.g400,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  // TabBar(2 段,负债 | 借出)— underline 横条 teal 滑动
                  SizedBox(
                    height: 28,
                    child: TabBar(
                      isScrollable: true,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      tabs: const [
                        Tab(text: '负债'),
                        Tab(text: '借出'),
                      ],
                      labelColor: AppBrand.teal,
                      unselectedLabelColor: AppGray.g600,
                      indicatorColor: AppBrand.teal,
                      dividerHeight: 0,
                    ),
                  ),
                ],
              ),
            ),
            // body(2 个 tab 切换) — D64.64:padding 由 LiabilitiesDashboard /
            // ReceivablesDashboard body 自己控制(不外加 padding,避免双层 padding)
            const TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    0,
                    AppSpacing.s4,
                    AppSpacing.s4,
                  ),
                  child: LiabilitiesDashboard(),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    0,
                    AppSpacing.s4,
                    AppSpacing.s4,
                  ),
                  child: ReceivablesDashboard(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}