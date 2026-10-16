// lib/core/widgets/rows/asset_metric_row.dart
// 资产/账户"行"通用展示:icon chip + name(限宽) + 横向条 + 占比% + 金额
//
// 2026-10-16 D64.76 抽:liabilities_dashboard._DebtRow + receivables_dashboard
//   ._LendRow 几乎完全同款(28x28 icon + name 60px + bar + 80px 占比/金额),
//   receivables 还多一个 _LendHorizontalBar 重复文件;
//   统一抽此 widget,3 处复用,改一处生效
//
// 设计要点(沿用原 _DebtRow / _LendRow 标准):
//   - icon chip 28x28 + color.withValues(alpha:0.18) 底 + color icon
//   - name 60px 限宽 + ellipsis(行场景都是账户名,2-4 字短)
//   - bar 高度 8 + 圆角 4,fill 按 percent 比例(由 caller 传 totalForPercent 算)
//   - 占比% + 金额 Column 右对齐 80px,行间 1px gap
//   - amount / name 颜色 caller 决定(error 红 / teal / segment / 等)
import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/settings/ui/widgets/asset_tile.dart';

class AssetMetricRow extends StatelessWidget {
  const AssetMetricRow({
    super.key,
    required this.iconKey,
    required this.name,
    required this.color,
    required this.amount,
    required this.amountColor,
    required this.totalForPercent,
    this.nameColor,
    this.showBar = true,
    this.nameTextStyle,
  });

  /// 资产 icon 名(走 AssetTile.icons 集中表 lookup,见 D64.73)
  final String iconKey;

  /// 账户名(2-4 字短名,60px 限宽 ellipsis)
  final String name;

  /// icon chip 主色(28x28 底色 alpha 0.18 + icon 自身色)
  final Color color;

  /// 金额数值(由 caller 决定符号 / 单位,本 widget 走 `Formatters.amount`)
  final double amount;

  /// 金额文字色(黑 / 红 / teal / segment color 等)
  final Color amountColor;

  /// 用于算 percent = amount / totalForPercent(分母为 0 时 percent 0)
  final double totalForPercent;

  /// 名字颜色(默认 onSurfaceVariant,liabilities 调成 g400 是因为在 ink 底)
  final Color? nameColor;

  /// 是否画中间横向条(_TypeRow 等无 bar 场景关掉)
  final bool showBar;

  /// 自定义名字 text 样式(覆盖默认 13sp + nameColor)
  final TextStyle? nameTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = totalForPercent > 0 ? amount / totalForPercent : 0.0;
    final nameFg = nameColor ?? theme.colorScheme.onSurfaceVariant;
    final nameStyle = nameTextStyle ??
        TextStyle(color: nameFg, fontSize: 13);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // icon chip 28x28
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: AppRadius.brXs,
          ),
          child: Icon(
            AssetTile.icons[iconKey] ?? Icons.account_balance_wallet_rounded,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        // name 60px 限宽
        SizedBox(
          width: 60,
          child: Text(
            name,
            style: nameStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        // 横向条(caller 决定是否画)
        if (showBar) ...[
          Expanded(
            child: _MetricBar(
              percent: percent,
              color: color,
              trackColor: theme.colorScheme.surfaceContainerHigh,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
        ] else ...[
          const Spacer(),
        ],
        // 占比% + 金额 80px Column 右对齐
        SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBar)
                Text(
                  '${(percent * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              if (showBar) const SizedBox(height: 1),
              Text(
                '¥${Formatters.amount(amount)}',
                style: TextStyle(
                  color: amountColor,
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

/// 横向条 widget —— 1px outline 浅色 track + 内嵌彩色 fill
///   - 高度 8,圆角 4
///   - 限幅 percent [0, 1] 防止越界
class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.percent,
    required this.color,
    required this.trackColor,
  });

  final double percent;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0.0, 1.0);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: trackColor,
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
