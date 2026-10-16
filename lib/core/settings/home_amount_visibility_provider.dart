// lib/core/settings/home_amount_visibility_provider.dart
// 首页"显示金额"按钮的 local state —— 仅首页用,临时性,不影响全局
//
// 2026-10-16 D64.51 改(user UAT 反馈 bug):
//   - user 反馈"首页这个显示金额如果点击打开了的话,等同于我的页面中的
//     '显示金额',这不是我想要的,我这个显示金额只是临时性的,并且
//     只针对首页这个生效,而我的那个是全局的,可以影响到首页这里的
//     显示与否,懂不?"
//   - 之前 monthly_summary.dart 的眼睛按钮直接 toggle `amountVisibilityProvider`
//     (全局) → user 点首页按钮会同时关掉"我的"页那个全局开关(因为共用 provider),
//     截图分享/公开场合下 user 想临时遮蔽首页金额但不希望全局关掉
//   - 修法:加一个 local provider,首页眼睛按钮 toggle 它,不影响全局
//   - 优先级:全局 = false 时,首页也得隐藏(全局优先级高,因为"我的"页
//     显式关 = user 想全面隐藏);全局 = true 时,首页由 local 决定
//   - 用 `Provider<bool>`(不是 StateNotifier)简化 API,值是 reactive 但
//     不需要持久化(用户明确说"临时性")
//   - 实现为 `ref.watch(provider.notifier)` toggle 写法跟 StateProvider 等价,
//     但更轻量
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'amount_visibility_provider.dart';

/// 首页 local "显示金额" toggle —— 仅首页用
///   - 默认 true(显示金额,跟全局默认一致)
///   - 临时性(不写 SharedPreferences),重启 / 切 tab 后回到 true
///   - 跟 `amountVisibilityProvider`(全局)正交,优先级:
///     hidden = !globalVisible || !homeVisible
final homeAmountVisibilityProvider = StateProvider<bool>((ref) => true);

/// 组合判断:global + home 任一为 hidden → 整体隐藏
///
/// 用法:业务侧 widget 调
/// ```dart
/// final hidden = ref.watch(combineAmountVisibilityProvider);
/// ```
final combineAmountVisibilityProvider = Provider<bool>((ref) {
  final globalVisible = ref.watch(amountVisibilityProvider);
  final homeVisible = ref.watch(homeAmountVisibilityProvider);
  return !globalVisible || !homeVisible;
});
