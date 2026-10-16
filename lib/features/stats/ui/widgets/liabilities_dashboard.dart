// lib/features/stats/ui/widgets/liabilities_dashboard.dart
// 报表"资产"视角 dashboard —— 负债情况
//
// 2026-10-16 D64.61 加(user UAT 反馈):
//   - user 反馈"报表中的负债情况,需要显示负数,这样才能让用户有警示"
//   - 之前总负债大字 + 列表金额都用 Formatters.amount(totalDebt) 显示正数
//     (¥3,000),警示感不强;改成显示原始 balance(负数,¥-3,000)+ error 红,
//     user 一眼看出"我欠的款 = 负数"双重警示(色 + 负号)
//   - 改法:
//     ① `_DebtItem` 加 `balance` 字段(double,负数),`debt` = balance.abs()
//       (供横向条比例计算保持兼容)
//     ② 总负债大字:改 `totalLiab = ∑ balance`(负数累加,不是 ∑ debt 正数)
//     ③ 大字颜色:`AppSecondary.cream` → `AppStatus.error`(警示红)
//     ④ 列表金额:`Formatters.amount(item.debt)` → `Formatters.amount(item.balance)`,
//       颜色 `item.color` → `AppStatus.error`(跟大字一致警示)
//     ⑤ 负债率分子:`totalLiab.abs()`(数值同原 totalDebt,只是包了 abs,
//       防止负百分比 0% 显示)
//
// 2026-10-16 D64.56 加(user UAT 反馈):
//   - user 反馈"资产报表里面,我需要增加一个新的 dashboard,关于负债的,
//     大概是这样的形式:
//     卡片名称是负债情况
//     总负债:xxxxxx
//     然后列出每项目负债情况,如
//     - 花呗(20%)
//     - 信用卡(xxx)
//     再加上横向的条形图"
//   - 报表资产视角原本 D64.45 删了 AssetsOverviewChart 后只留 AssetsRadar,
//     但 radar 5 维只反映 5 段真资产占比,没专门展示"我欠多少"细节
//   - 修法:新增本 widget,放进 stats_page 资产 tab 顶部(雷达图上方)
//
// 2026-10-16 D64.57 加(user UAT 反馈):
//   - user 反馈"然后我再调整一下负债情况,增加负债率"
//   - 公式:负债率 = (总负债 / 总资产) × 100%
//     - 分子 = ∑ max(0, -balance) over all receivable accounts(同大字口径)
//     - 分母 = 5 真资产累加(cash_flow / investment / benefit / fixed_asset / other,
//       **不含 receivable**,跟 D64.36 总资产口径一致)
//     - 防除 0:totalAssets = 0 且 totalDebt = 0 → 0%(无负债无资产,合规)
//     - 兜底:totalAssets = 0 且 totalDebt > 0 → 0%(逻辑上"我没资产但有负债"
//       罕见情况,避免 NaN/Infinity 显示)
//   - 显示位置:大字下面独立一行(13sp w500 onSurfaceVariant 副标题),
//     empty state 不显示负债率(✓ "当前无负债"已隐含 0%,避免冗余)
//
// 设计要点(跟 AssetSummaryCard 镜像):
//   - ink 底 / AppRadius.brLg / 1px outline / CardShadows.dark
//     跟"我的 -> 资产"顶部 AssetSummaryCard 视觉系统统一
//   - 标题"负债情况" 11sp AppGray.g400(跟 AssetSummaryCard "净资产" 同款)
//   - 大字 = 总负债(∑ max(0, -balance) over all receivable accounts),
//     fontSize 28 w700 cream
//   - 负债率 = 总负债 / 总资产 × 100%(D64.57),紧跟大字下面,13sp w500 灰
//   - 列表(每个 receivable 账户 1 行,按 debt 降序):
//     [icon chip 28x28]  [name Expanded]  [bar 60% flex 0..1]  [12% 8sp]  [¥X 12sp w600]
//     bar 是横向 Container,宽度按 debt/totalDebt 比例,跟其它 segment 色同款
//   - 排序:debt > 0 降序;debt = 0 的 receivable 不显示(净额 0 或正,
//     不算"我欠的")
//   - empty state:无任何 receivable 净欠时,显示"当前无负债" + ✓ 图标
//     (跟 AssetSummaryCard 净资产全 0 的 empty 风格不同 — 净资产 0 也
//     算"我 0 资产",但负债 0 是好消息,值得庆祝一下)
//
// 数据源:
//   - allAssetsProvider(receivable 段账户列表)
//   - assetBalancesProvider(Map<assetId, currentBalance>)
//   - 算 debt = max(0, -balance),跟 D64.36 净资产口径公式一致
//   - D64.57 算 5 真资产累加 = totalAssets(不含 receivable),byType 累加模式
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../settings/ui/widgets/asset_tile.dart' show AssetTile;

/// 报表"负债情况" dashboard
///   - 总负债大字(∑ debt over all receivable accounts)
///   - 列表(按 debt 降序)+ 每行横向条
class LiabilitiesDashboard extends ConsumerWidget {
  const LiabilitiesDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // 按 type 累加 balance(跟 AssetSummaryCard 同款,后续可抽公共 provider —
    // D64.58+ 复盘若 AssetSummaryCard 跟 LiabilitiesDashboard 两边重复累加
    // 逻辑要 drift 时,提 netAssetsBreakdownProvider 共享;当前 5 真资产 +
    // receivable 总累加就地实现)
    final byType = <String, double>{
      'cash_flow': 0.0,
      'investment': 0.0,
      'benefit': 0.0,
      'receivable': 0.0,
      'fixed_asset': 0.0,
      'other': 0.0,
    };
    for (final a in assets) {
      final bal = balances[a.id] ?? 0.0;
      byType[a.type] = (byType[a.type] ?? 0.0) + bal;
    }

    // 提取 receivable 段账户,算每账户的 debt = max(0, -balance)
    //   - 跟 D64.36 净资产口径公式一致:负债 = max(0, -receivable),
    //     正 receivable(净应收)不算负债
    //   - 同样不计入 receivable 累加 balance(避免正负抵消),只看 净欠
    // D64.61:同时存 balance(原始负数,显示用)+ debt(abs,横向条比例用)
    final receivableItems = <_DebtItem>[];
    for (final a in assets.where((a) => a.type == 'receivable')) {
      final bal = balances[a.id] ?? 0.0;
      final debt = bal < 0 ? -bal : 0.0;
      if (debt > 0) {
        receivableItems.add(_DebtItem(
          id: a.id,
          name: a.name,
          color: Color(a.color),
          balance: bal, // D64.61:负数原始值,显示时 Formatters.amount 自动加 "-"
          debt: debt, // 横向条比例用 abs
        ));
      }
    }
    // 按 debt 降序,最大的在前面
    receivableItems.sort((a, b) => b.debt.compareTo(a.debt));
    // D64.61:总负债累加改成累加 balance(负数),display 自动 "-X,XXX.XX"
    final totalLiab = receivableItems.fold<double>(0, (s, e) => s + e.balance);
    // 兼容老公式:负债率分子用 abs(数值同 totalDebt,但语义对应 ∑ debt 公式)
    final totalDebt = -totalLiab;

    // D64.57:总资产 = 5 真资产累加(**不含 receivable**,跟 D64.36 总资产口径一致)
    //   - receivable 是借贷账户(余额可正可负,正=净应收 / 负=净应付),
    //     不进"我有什么"累加(资产页 AssetSummaryCard 末尾小字"总资产"口径)
    //   - 5 段真资产 = cash_flow / investment / benefit / fixed_asset / other
    final totalAssets =
        (byType['cash_flow'] ?? 0) +
            (byType['investment'] ?? 0) +
            (byType['benefit'] ?? 0) +
            (byType['fixed_asset'] ?? 0) +
            (byType['other'] ?? 0);
    // D64.57:负债率 = (总负债 / 总资产) × 100%
    //   - 防除 0:totalAssets = 0 且 totalDebt = 0 → 0%(无负债无资产,合规)
    //   - 兜底:totalAssets = 0 且 totalDebt > 0 → 0%(逻辑上"我没资产但有负债"
    //     罕见情况,避免 NaN/Infinity 显示)
    // D64.61:分子用 totalDebt(= -totalLiab),内部算正数,display "负债率 X%"
    //   数值仍是正百分比,user 视觉看到"比例"不会混淆正负
    final ratio = totalAssets > 0 ? (totalDebt / totalAssets) : 0.0;
    final debtRatio = (ratio * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          const Text(
            '负债情况',
            style: TextStyle(
              color: AppGray.g400,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          // 总负债大字(D64.61:负数警示)
          //   - 显示 `∑ balance`(负数累加),Formatters.amount 自动 "-X,XXX.XX"
          //   - 颜色 error 红警示(替代原 cream 中性色)
          //   - empty 时 totalLiab = 0,显示 "¥0"(不变,empty state 路径走下方
          //     "当前无负债 ✓" 不显示大字本行 — 不,大字照常显示 0,跟之前一样)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${Formatters.amount(totalLiab)}',
              style: TextStyle(
                color: AppStatus.error,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          // D64.57:负债率(大字下面副标题,13sp w500 onSurfaceVariant)
          //   - 有数据时显示,empty state 不显示(避免冗余 — ✓ "当前无负债"
          //     已隐含 0%)
          //   - 颜色 onSurfaceVariant 跟 AssetSummaryCard 末尾"总资产"小字
          //     同款灰,跨页一致
          if (receivableItems.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(
              '负债率 $debtRatio%',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          // empty state 跟有数据分两路(empty 不画 Divider,只画提示)
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
                    '当前无负债',
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
            const Divider(height: 1, color: AppGray.g600),
            const SizedBox(height: AppSpacing.s3),
            // 列表(每行)
            for (int i = 0; i < receivableItems.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s2),
              _DebtRow(item: receivableItems[i], totalDebt: totalDebt),
            ],
          ],
          // 末尾小字备注(总负债公式说明,跟 D64.36 净资产卡末尾同款)
          //   - 跟净资产卡不同:负债卡没"5 段资产 + 白线 + 1 段 receivable + 总资产小字"
          //     那种"分项累加"结构,负资产卡只列 6 段中的 receivable 一段,
          //     已是"全量 = 总负债" 不需要"小字备注总资产"
          //   - 故末尾不画小字,保持简洁
        ],
      ),
    );
  }
}

/// 单个 receivable 账户的 debt 信息
///   - D64.61:`balance`(原始值,可负)+ `debt`(abs)双存
///     - balance:用于 UI 显示"¥-X,XXX.XX"警示
///     - debt:用于横向条比例计算(item.debt / totalDebt)
class _DebtItem {
  const _DebtItem({
    required this.id,
    required this.name,
    required this.color,
    required this.balance,
    required this.debt,
  });
  final int id;
  final String name;
  final Color color;
  final double balance;
  final double debt;
}

/// 单行展示:icon chip + name + 横向条 + 占比 + 金额
class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.item, required this.totalDebt});

  final _DebtItem item;
  final double totalDebt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = totalDebt > 0 ? item.debt / totalDebt : 0.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // icon chip(跟 AssetSummaryCard _TypeRow 同款 28x28 + alpha 0.18)
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brXs,
          ),
          child: Icon(
            AssetTile.icons[item.name] ??
                Icons.account_balance_wallet_rounded,
            color: item.color,
            size: 16,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        // 名称(限宽,可省略)
        SizedBox(
          width: 60,
          child: Text(
            item.name,
            style: const TextStyle(color: AppGray.g400, fontSize: 13),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        // 横向条(占中间剩余空间,按 percent 比例)
        Expanded(
          child: _HorizontalBar(
            percent: percent,
            color: item.color,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 占比 + 金额(右对齐,固定宽度)
        SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 1),
              // D64.61:列表金额显示原始 balance(负数),Formatters.amount 自动
              // 加负号前缀,颜色 error 红警示(跟大字一致)
              Text(
                '¥${Formatters.amount(item.balance)}',
                style: TextStyle(
                  color: AppStatus.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 横向条形图 —— 1px outline 浅色 track + 内嵌彩色 fill(按 percent)
///   - 高度 8,圆角 4,跟 CardShadows.light 卡片有"subtle depth"风格统一
///   - 颜色用 item.color(6 段主色,跟 AssetSummaryCard segment chip 同色)
class _HorizontalBar extends StatelessWidget {
  const _HorizontalBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 限幅 [0, 1]
    final p = percent.clamp(0.0, 1.0);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: p,
            heightFactor: 1,
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}
