// lib/core/widgets/aqua_row_card.dart
// 拟物风 settings 行卡片(整行 tap 切 switch 状态)
// 2026-10-16 D64.74 抽:asset_form_page 4 个 _XxxCard 完全同款复制
//   (IncludeInTransactions / IsDefault / ActAsCashFlow / IsLender),
//   唯一差异:icon / iconColor / title / subtitle,统一抽此 widget
//
// 设计要点(沿用 asset_form_page 4 个 _XxxCard 原版):
//   - 16px 圆角 card + 1px outlineVariant + surfaceContainerLow(跟 _TypeRadioList 外层同款)
//   - clipBehavior:antiAlias,让圆角处正确裁剪 InkWell ripple
//   - 整行 tap 切换(跟 ListTile 一致);AquaSwitch 自身 GestureDetector.opaque
//     会拦截 tap 不冒泡,避免双重触发
//   - leading icon + 主标(15sp w500)+ 副标(11sp g600,按 value 切)+ trailing AquaSwitch
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'aqua_switch.dart';

class AquaRowCard extends StatelessWidget {
  const AquaRowCard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: 14,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s05),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppGray.g600,
                        ),
                      ),
                    ],
                  ),
                ),
                AquaSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
