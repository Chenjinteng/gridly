// lib/features/settings/ui/widgets/asset_tile.dart
// 我的页"资产"section 列表 tile —— 单个资产展示
//
// 2026-10-12 P2 commit 加:
//   - 跟 category_management_page 的 _CategoryTile 同款风格(Container 卡片 + ListTile)
//   - leading:icon chip(账户色块)
//   - title:name
//   - subtitle:type chip + 余额(余额从 assetBalanceProvider 取)
//   - trailing:[编辑][删除] IconButton(同 CategoryTile)
//   - 点 tile 整体也可触发编辑,跟 CategoryTile onEdit 一致
//
// 2026-10-13 P6 第 2 次改(UAT 反馈):
//   - subtitle 拆 2 行:
//     - 第一行:type chip + 计入/不计入 chip(用户明确要"像现金流 chip 一样显示")
//     - 第二行:金额独立一行(用户说金额长时给更多空间)
//   - 计入流水 chip = 主题黄(AppBrand.gold);不计入 = 灰色(AppGray.g600)
//   - 金额 0.00 用主题灰(AppGray.g400),"无数据"状态更明显
//   - 删 title 末尾的 archive icon(include chip 在 subtitle 已经有更明显显示)
// 2026-10-13 P7 第 3 次改(UAT 反馈):加"默认"chip
//   - 仅 cash_flow 段且 isDefault=true 时,在 subtitle 第一行插入"默认" chip
//   - 位置:type chip 之后(语义高亮,"默认账户"是比"是否计入"更突出的状态)
//   - 配色:AppBrand.gold(跟 _IsDefaultCard + 计入 chip 同款,视觉语言统一)
//   - 配合 Assets.isDefault 字段(3309b23),user 在资产 form 开启默认后,资产列表一眼能看到"哪条是默认"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';

/// 资产列表 tile
///   - name / type / icon / color / currentBalance(实时算)
///   - onEdit / onDelete:用户操作回调
class AssetTile extends ConsumerWidget {
  const AssetTile({
    super.key,
    required this.asset,
    required this.onEdit,
    required this.onDelete,
  });
  final Asset asset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// icon 名 → IconData 映射(2026-10-12 P2):
  /// 2026-10-13 P6 UAT 扩:资产 icon 池(覆盖通用钱包/支付/保险/股票/债券等)
  ///   - 之前 8 个 icon 不够:用户要"保险/股票/债券/钱包/微信/支付宝/银联"
  ///   - Material Icons 没品牌 icon(微信/支付宝/银联),需要 brand assets;
  ///     这次先扩通用池,品牌 icon 等 user 后续提供素材再加
  ///   - Flutter Material Icons 内置 + 通用钱包/支付类
  static const Map<String, IconData> icons = {
    // 钱包 / 支付 / 现金
    'account_balance_wallet': Icons.account_balance_wallet_rounded, // 钱包通用
    'wallet': Icons.wallet_rounded, // 钱包
    'payments': Icons.payments_rounded, // 支付
    'credit_card': Icons.credit_card_rounded, // 信用卡
    'savings': Icons.savings_rounded, // 储蓄
    'account_balance': Icons.account_balance_rounded, // 银行
    'currency_yen': Icons.currency_yen_rounded, // 现金(¥)
    'attach_money': Icons.attach_money_rounded, // 现金($)
    'monetization_on': Icons.monetization_on_rounded, // 现金
    // 资产类型
    'home': Icons.home_rounded, // 不动产
    'directions_car': Icons.directions_car_rounded, // 车
    'landscape': Icons.landscape_rounded, // 土地
    'apartment': Icons.apartment_rounded, // 公寓
    // 投资 / 股票 / 债券
    'trending_up': Icons.trending_up_rounded, // 涨跌
    'candlestick_chart': Icons.candlestick_chart_rounded, // K 线
    'show_chart': Icons.show_chart_rounded, // 曲线
    'receipt_long': Icons.receipt_long_rounded, // 债券
    'assessment': Icons.assessment_rounded, // 报表
    // 保险 / 保障
    'health_and_safety': Icons.health_and_safety_rounded, // 保险
    'shield': Icons.shield_rounded, // 盾牌
    'security': Icons.security_rounded, // 安全
    'verified': Icons.verified_rounded, // 已验证
    // 福利 / 借出 / 其它
    'favorite': Icons.favorite_rounded, // 福利
    'handshake': Icons.handshake_rounded, // 借出
    'swap_horiz': Icons.swap_horiz_rounded, // 调拨
    'category': Icons.category_rounded, // 其它
  };

  /// type 名 → 中文标签(2026-10-13 P6:4 段 → 6 段,加投资/福利/债权)
  /// 2026-10-14 改:跟所有"期权/负债"统一用"负债"称呼
  ///   receivable label "债权/借出" → "负债"
  ///   DB key 仍是 'receivable'(API enum 内部不变)
  static const Map<String, String> typeLabels = {
    'cash_flow': '现金流',
    'investment': '投资',
    'benefit': '福利',
    'receivable': '负债',
    'fixed_asset': '不动产',
    'other': '其它',
  };

  /// 2026-10-14 P18:type 名 → 段色统一走 AppSegment(集中管理)
  static Color colorFor(String type) => AppSegment.colorFor(type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(asset.color);
    final typeColor = colorFor(asset.type);
    // 余额走 family provider 单查(避免 watch 整张 balances map)
    final balanceAsync = ref.watch(assetBalanceProvider(asset.id));
    final balance = balanceAsync.valueOrNull ?? 0.0;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: ListTile(
        onTap: onEdit,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.brXs,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Icon(
            icons[asset.icon] ?? Icons.account_balance_wallet_rounded,
            color: color,
            size: 18,
          ),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        // 2026-10-13 P6 第 2 次改:subtitle 拆 2 行
        // - 第一行:type chip + 计入/不计入 chip
        // - 第二行:金额独立(整行,长金额有更多空间)
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行:chips
              Row(
                children: [
                  // type chip(同款胶囊,type 配色)
                  _TileChip(
                    label: typeLabels[asset.type] ?? asset.type,
                    color: typeColor,
                  ),
                  // 2026-10-13 P7 第 3 次改:仅 cash_flow + isDefault=true 显示"默认" chip
                  // - 位置:type chip 紧贴后(语义高亮,比"是否计入"更突出)
                  // - 配色:AppBrand.gold(跟 _IsDefaultCard + 计入 chip 同款)
                  // - "默认" 是记一笔的优先账户,user 在资产列表一眼能看到"哪条是默认"
                  if (asset.isDefault && asset.type == 'cash_flow') ...[
                    const SizedBox(width: 6),
                    const _TileChip(label: '默认', color: AppBrand.gold),
                  ],
                  const SizedBox(width: 6),
                  // 2026-10-13 P6 第 2 次改:includeInTransactions chip
                  //   计入 = 主题黄(AppBrand.gold)
                  //   不计入 = 灰色(AppGray.g600)
                  //   跟 type chip 同款胶囊,色块 + 文字,一眼能看到状态
                  _TileChip(
                    label: asset.includeInTransactions ? '计入流水' : '不计入流水',
                    color: asset.includeInTransactions
                        ? AppBrand.gold
                        : AppGray.g600,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 第二行:金额独立(2026-10-13 P6 第 2 次改)
              //   0.00 用主题灰(AppGray.g400),"无数据"状态更明显
              //   > 0 teal;< 0 error
              Text(
                '¥${Formatters.amount(balance)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: balance == 0
                      ? AppGray.g400
                      : AppSemantic.balanceFor(balance),
                ),
              ),
            ],
          ),
        ),
        // 2026-10-13 P6 UAT 改:IconButton 占用 40x40,2 个 = 80px,挤
        //   "债权/借出" + "不计入流水" 两个 5 字符 chip 时 1.3px overflow
        //   改用 InkWell + 自定义 Padding(all:6),size = 30x30,省 20px
        //   - 失去 IconButton 自带的 tooltip / splash 半径等 Material 特性
        //   - 但 splash 用 InkWell 自带(通过 borderRadius 限定形状)
        //   - 视觉上 IconButton 默认 ripple 几乎一样,只是 hit area 小 4px
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onEdit,
              borderRadius: AppRadius.brSm,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.edit_outlined, size: 18),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onDelete,
              borderRadius: AppRadius.brSm,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppStatus.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 资产 tile 小 chip(2026-10-13 P6 第 2 次改)
/// - 圆角 4px 胶囊
/// - color.withValues(alpha:0.12) 底色 + color 文字
/// - 10sp w600(跟之前 type chip 风格一致)
/// - 复用 type chip + 计入/不计入 chip 两种语义
class _TileChip extends StatelessWidget {
  const _TileChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
