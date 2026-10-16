// lib/features/stats/ui/widgets/receivables_dashboard.dart
// 报表"资产"视角 dashboard —— 借出情况(纯 body,D64.64 改)
//
// 2026-10-16 D64.64 改(user UAT 反馈):
//   - user 反馈"负债和借出这两个卡片可以合起来用一个 tab 切换的方式,
//     卡片名就叫债务情况,两个tab,负债|借出"
//   - 修法:本 widget 改成"纯 body"(无 Container + 无标题),由
//     DebtDashboard(新建)统一包 ink 底卡片 + 顶部 tab 切换器 +
//     body 切本 widget / LiabilitiesDashboard
//   - 删:外层 Container + 标题"借出情况" Text + 顶部 SizedBox(s1)
//   - 保留:大字 + empty state + Divider + 列表
//
// 2026-10-16 D64.62 加(user UAT 反馈):
//   - user 反馈"现在资产那边已经增加了借入借出的情况,所以在报表中可以
//     增加一个白色底的卡片,标记是借出的金额"
//   - 镜像 LiabilitiesDashboard 但反语义:
//     ① 白底(scheme.surface,对比 ink 底警示色)— 借出是"我的钱",不是"我欠的钱"
//     ② 大字正数(∑ balance over isLender=true receivable,我应收的钱)
//     ③ 颜色 onSurface 主色 / AppBrand.teal(友好色,跟 receivable 段色区分)
//     ④ empty state "当前无借出" teal ✓(友好,跟"当前无负债 ✓" 镜像)
//   - 列表每个 isLender=true 的 receivable 账户 1 行,按 balance 降序
//   - 横向条比例:item.balance / totalLend(正数累加)
//
// D64.62 衍生(D64.62 一次 3 件套):数字跳动动画
//   - 大字用 AnimatedCounter(同 LiabilitiesDashboard),首次从 0 滚到目标,
//     切月份/视角时从旧值滚到新值
//
// 跟 LiabilitiesDashboard 的镜像对照表:
//   - 底色:ink → scheme.surface
//   - 标题:"负债情况" → "借出情况"
//   - 大字颜色:cream / error 红 → onSurface / AppBrand.teal
//   - 列表金额颜色:item.color / error 红 → onSurface / AppBrand.teal
//   - empty state:teal "当前无负债" → teal "当前无借出"
//   - shadow:CardShadows.dark → CardShadows.light(白底用轻阴影)
//
// 数据源:
//   - allAssetsProvider(receivable 段 isLender=true 账户列表)
//   - assetBalancesProvider(Map<assetId, currentBalance>)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/animated_counter.dart';
import '../../../../core/widgets/rows/asset_metric_row.dart';

/// 报表"借出情况" dashboard
///   - 总借出大字(∑ balance over isLender=true receivable)
///   - 列表(按 balance 降序)+ 每行横向条
///   - 白底 + teal 主色,镜像 LiabilitiesDashboard
class ReceivablesDashboard extends ConsumerWidget {
  const ReceivablesDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context); // D64.64:删 isDark(原 Container border alpha 用)
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    // 2026-10-16 D65.5 加:借出占比分母需要 cash_flow 段余额
    final totalsAsync = ref.watch(assetTotalsProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};
    final totals = totalsAsync.valueOrNull;

    // 提取 isLender=true 的 receivable 段账户,累加 balance(全是正数,我是债权人)
    final receivableItems = <_LendItem>[];
    for (final a in assets.where(
      (a) => a.type == 'receivable' && a.isLender,
    )) {
      final bal = balances[a.id] ?? 0.0;
      if (bal > 0) {
        receivableItems.add(_LendItem(
          id: a.id,
          name: a.name,
          iconKey: a.icon, // D64.76:从 Asset.icon 字段取
          color: Color(a.color),
          balance: bal,
        ));
      }
    }
    // 按 balance 降序,最大的在前面
    receivableItems.sort((a, b) => b.balance.compareTo(a.balance));
    final totalLend = receivableItems.fold<double>(0, (s, e) => s + e.balance);

    // 2026-10-16 D65.5 加:借出占比 = 借出总额 / 流动资产(cash_flow 段余额)
    //   - 跟 负债率(分子 = 负债 / 分母 = 总资产)镜像,但:
    //     - 分子:借出总额(正数,我是债权人)
    //     - 分母:**流动资产**(cash_flow 段余额累加),非"总资产"
    //   - user 反馈"借出去多少了,有没有影响我的流动资金" — 用 cash_flow 段最贴
    //     个人财务语义:流动资金 ≈ "我能立刻动用的现金"(现金/银行卡/微信支付等)
    //   - 投资账户(余额宝/基金账户)不算流动资金:lock 期内不能即时取
    //   - 房产/汽车/公积金/其它 也不算
    //   - 防除 0:totalCashFlow = 0 → 0%(我没流动资金,显示 0% 避免 NaN)
    //   - 跟 负债率 算法 1:1 镜像(分子/分母/防除 0 模式一致),不 clamp 上限 100%
    //     (借出 > 流动资金 时正确显示 100%+,跟 负债率 行为对齐)
    final totalCashFlow = totals?.totalCashFlow ?? 0.0;
    final lendRatio = totalCashFlow > 0 ? (totalLend / totalCashFlow) : 0.0;
    final lendRatioStr = (lendRatio * 100).toStringAsFixed(0);

    // D64.64:纯 body 返回,无 Container 包装 + 无标题(由 DebtDashboard 提供)
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (D64.64:删"借出情况"标题 Text + SizedBox(s1) 顶部间距,DebtDashboard 提供)
          // 总借出大字(D64.62 数字跳动动画)
          //   - 颜色 AppBrand.teal(债权/收入侧,跟 receivable 段 type chip 同款)
          //   - 白底上 teal 文字对比度好(黑底用的是 cream,白底改成 teal 更跳)
          //   - FittedBox scale-down + maxLines=1 跟 LiabilitiesDashboard 一致
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedCounter(
              value: totalLend,
              prefix: '¥',
              formatter: (v) => Formatters.amount(v),
              duration: const Duration(milliseconds: 480),
              style: const TextStyle(
                color: AppBrand.teal,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
          // 2026-10-16 D65.5 加:借出占比(大字下面副标题,镜像 负债率)
          //   - 公式:借出总额 / 流动资产(cash_flow 段)
          //   - 视觉跟 负债率 完全一致(13sp w500 onSurfaceVariant)
          //   - 加在 SizedBox(s3) 前面,跟 负债率 占据同样的垂直空间
          //   - 有数据时显示;empty state 不显示(✓ "当前无借出" 已隐含 0%)
          //   - 加完后:借出 tab 跟 负债 tab 大字下面结构完全镜像,卡片高度一致
          if (receivableItems.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(
              '借出占比 $lendRatioStr%',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          // empty state 跟有数据分两路
          if (receivableItems.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: AppBrand.teal.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    '当前无借出',
                    style: TextStyle(
                      color: AppBrand.teal.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // outlineVariant hairline(浅底上用 outlineVariant 区分边线,比 ink 上的
            // AppGray.g600 在白底上更合适)
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.s3),
            // 列表(每行)
            for (int i = 0; i < receivableItems.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s2),
              _LendRow(item: receivableItems[i], totalLend: totalLend),
            ],
          ],
        ],
    );
  }
}

/// 单个 isLender=true receivable 账户的 lend 信息
class _LendItem {
  const _LendItem({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.balance,
  });
  final int id;
  final String name;
  // 2026-10-16 D64.76 加:从 Asset.icon 字段取
  final String iconKey;
  final Color color;
  final double balance;
}

/// 单行展示:icon chip + name + 横向条 + 占比 + 金额
/// 2026-10-16 D64.76 改:跟 _DebtRow 一并用 AssetMetricRow 共享 widget,
///   跟 LiabilitiesDashboard _HorizontalBar 重复文件一并清理
class _LendRow extends StatelessWidget {
  const _LendRow({required this.item, required this.totalLend});

  final _LendItem item;
  final double totalLend;

  @override
  Widget build(BuildContext context) {
    return AssetMetricRow(
      iconKey: item.iconKey,
      name: item.name,
      color: item.color,
      amount: item.balance,
      // 借出金额:正数 teal(跟大字一致)
      amountColor: AppBrand.teal,
      totalForPercent: totalLend,
      // 白底卡片用 onSurfaceVariant(默认)
    );
  }
}