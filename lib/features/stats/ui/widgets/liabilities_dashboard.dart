// lib/features/stats/ui/widgets/liabilities_dashboard.dart
// 报表"资产"视角 dashboard —— 负债情况
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
// 设计要点(跟 AssetSummaryCard 镜像):
//   - ink 底 / AppRadius.brLg / 1px outline / CardShadows.dark
//     跟"我的 -> 资产"顶部 AssetSummaryCard 视觉系统统一
//   - 标题"负债情况" 11sp AppGray.g400(跟 AssetSummaryCard "净资产" 同款)
//   - 大字 = 总负债(∑ max(0, -balance) over all receivable accounts),
//     fontSize 28 w700 cream
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
    final assetsAsync = ref.watch(allAssetsProvider);
    final balancesAsync = ref.watch(assetBalancesProvider);
    final assets = assetsAsync.valueOrNull ?? const <Asset>[];
    final balances = balancesAsync.valueOrNull ?? const <int, double>{};

    // 提取 receivable 段账户,算每账户的 debt = max(0, -balance)
    //   - 跟 D64.36 净资产口径公式一致:负债 = max(0, -receivable),
    //     正 receivable(净应收)不算负债
    //   - 同样不计入 receivable 累加 balance(避免正负抵消),只看 净欠
    final receivableItems = <_DebtItem>[];
    for (final a in assets.where((a) => a.type == 'receivable')) {
      final bal = balances[a.id] ?? 0.0;
      final debt = bal < 0 ? -bal : 0.0;
      if (debt > 0) {
        receivableItems.add(_DebtItem(
          id: a.id,
          name: a.name,
          color: Color(a.color),
          debt: debt,
        ));
      }
    }
    // 按 debt 降序,最大的在前面
    receivableItems.sort((a, b) => b.debt.compareTo(a.debt));
    final totalDebt = receivableItems.fold<double>(0, (s, e) => s + e.debt);

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
          // 总负债大字(empty 时也显示 0,跟净资产口径一致)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${Formatters.amount(totalDebt)}',
              style: const TextStyle(
                color: AppSecondary.cream,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
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
class _DebtItem {
  const _DebtItem({
    required this.id,
    required this.name,
    required this.color,
    required this.debt,
  });
  final int id;
  final String name;
  final Color color;
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
              Text(
                '¥${Formatters.amount(item.debt)}',
                style: TextStyle(
                  color: item.color,
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
