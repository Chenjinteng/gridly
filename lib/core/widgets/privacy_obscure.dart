// lib/core/widgets/privacy_obscure.dart
// 整页隐私覆盖层 —— 防偷窥 / 截图分享
//
// 适用场景:流水 / 报表 等"含敏感信息(分类名/账户名/金额/备注)"的整页。
// 区别于 `amountVisibilityProvider` 单值遮蔽(只把金额换成 ••••••),
// 这里直接把整页盖住,block 所有点击(包括 AppBar filter 按钮),
// 防止 user 借 filter 入口跳到带数据的子页(高级筛选等)。
//
// 行为(2026-10-14 D60.1 UAT 改):
//   - amountVisible=true → child 直接透传,无覆盖
//   - amountVisible=false → 整页盖主题色蒙版(深色主题→深色蒙版,浅色主题→浅色蒙版),
//     完全不透明(alpha=1.0),保证底层内容 0 泄露
//   - 蒙版中央 lock icon + "已隐藏" 文案
//   - 蒙版不响应点击(切换 visibility 的入口统一在"我的"页的开关),
//     用 AbsorbPointer 拦截所有 pointer 事件防止穿透到 child
//
// 设计要点:
//   - 用 Stack + Positioned.fill,跟底层 child 不耦合
//   - 蒙版用 Theme.of(context).colorScheme.surface,跟当前主题一致
//     (深色主题→dark surface,浅色主题→light surface)
//   - icon / 文案用 onSurface 系色,在 surface 上读得清
//   - 没用 InkWell / GestureDetector,改用 AbsorbPointer 纯拦截
//   - 切回 visible=true 时 child 已经 build 过在 tree 里(Stack 保留),
//     toggle 后无闪烁
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/amount_visibility_provider.dart';
import '../theme/app_spacing.dart';

class PrivacyObscure extends ConsumerWidget {
  const PrivacyObscure({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = !ref.watch(amountVisibilityProvider);
    if (!hidden) return child;

    return Stack(
      children: [
        // 底层原内容(虽然会被覆盖盖住,但保留 tree 状态,
        // 这样 toggle 回 visible 时不需要重新 build,直接展示,无闪烁)
        child,
        // 整页蒙版:不透明 + 主题色 + 不响应点击
        // AbsorbPointer 拦截所有 pointer,防止穿透到底层 child
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: _PrivacyCover(),
          ),
        ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 用主题 surface 色(深色→深色蒙版,浅色→浅色蒙版),
    // 完全不透明,保证底层内容 0 泄露
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 锁 icon(onSurface 系,跟 surface 反差,看清)
            Icon(
              Icons.lock_outline_rounded,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.s3),
            // 主文案("已隐藏",按 user UAT 反馈简化,去掉"金额"前缀)
            Text(
              '已隐藏',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
