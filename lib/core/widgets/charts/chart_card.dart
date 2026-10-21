// lib/core/widgets/charts/chart_card.dart
// 2026-10-15 D64.2 加:图表卡片通用容器
//
// 7 个报表 widget(category_pie / expense_by_asset / category_compare /
// weekday_expense / monthly_trend / savings_rate_card / top_expenses)
// 都用同款容器:surface bg + outlineVariant border + light shadow + 圆角 +
// 标题栏(标题 + 可选 trailing) + Divider + body。
//
// 抽到一处维护,后续调整卡片样式(圆角/边框/阴影)只改这一处。
//
// 用法:
//   ChartCard(
//     title: '类别对比',
//     trailing: Row(children: [legendDot1, legendDot2]),  // optional
//     child: AnimatedBarChart(...),  // body
//   )
import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/card_shadows.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.s4),
    this.showDivider = true,
  });

  /// 标题(左对齐 14sp w600)
  final String title;

  /// 标题右侧 widget(可选,例如图例 dot row / "共 ¥X" text)
  final Widget? trailing;

  /// 主体内容(padding 之外的 body,padding 在卡片内)
  final Widget child;

  /// body 内部 padding(默认 s4)
  final EdgeInsets padding;

  /// 标题栏下方是否画 0.5px hairline divider
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
        boxShadow: CardShadows.light(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
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
                // 2026-10-21 D64.90 修:标题加 Flexible(loose)
                //   窄屏(实测 ≤320 宽)标题 + trailing(TabBar)自然宽度之和 > 卡片内容宽
                //   → 标题是 Row 里的 non-flex child,拿到的是"整行"约束而不是"剩余"约束
                //   → 两边都按自然宽度摆,加起来超出 → RenderFlex 溢出(实测 320 宽溢出 39px)
                //   修:标题改 Flexible(loose) —— 够宽时按自然宽度(间距跟原来完全一样),
                //   不够时压缩 + 省略号,不再溢出
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (showDivider) const Divider(height: 1, thickness: 0.5),
          // body(padding 在内)
          if (padding == EdgeInsets.zero)
            child
          else
            Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
