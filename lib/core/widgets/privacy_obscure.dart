// lib/core/widgets/privacy_obscure.dart
// 整页隐私覆盖层 —— 防偷窥 / 截图分享
//
// 适用场景:流水 / 报表 等"含敏感信息(分类名/账户名/金额/备注)"的整页。
// 区别于 `amountVisibilityProvider` 单值遮蔽(只把金额换成 ••••••),
// 这里直接把整页盖住,block 所有点击(包括 AppBar filter 按钮),
// 防止 user 借 filter 入口跳到带数据的子页(高级筛选等)。
//
// 行为:
//   - amountVisible=true → child 直接透传,无覆盖
//   - amountVisible=false → 整页盖半透明深色蒙版,中央 lock icon + "金额已隐藏",
//     点蒙版任意位置 = 把 amountVisible 改回 true(快速恢复,1 次点击即可)
//
// 设计要点:
//   - 覆盖层用 Stack + Positioned.fill,跟底层 child 不耦合(只要 child 是 Widget 就可包)
//   - 蒙版默认 Colors.black87 半透明(0.85 alpha),保证即使 child 有内容也看不清
//   - 中心 lock icon + 文案提示 user "钱被藏起来了",点一下能展开
//   - 没用 Material/ShaderMask,避免在深色/浅色主题下有视觉割裂
//   - applyToScaffold 用法:把 Scaffold return 包在 PrivacyObscure 里即可,不用改 Scaffold 内部
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
        // 整页蒙版
        Positioned.fill(
          child: _PrivacyCover(
            onTap: () => ref.read(amountVisibilityProvider.notifier).set(true),
          ),
        ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 用半透明深色蒙版盖住整页(深色主题下也保证覆盖完全)
    // ignoreColors:0.85 保证即使 child 有内容也看不清
    return Material(
      // 半透明 Material 让 InkWell ripple 能在蒙版上看到
      color: Colors.black.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 锁 icon
              Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              const SizedBox(height: AppSpacing.s3),
              // 主文案
              const Text(
                '金额已隐藏',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              // 副文案(提示可点击恢复)
              Text(
                '点击显示',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
