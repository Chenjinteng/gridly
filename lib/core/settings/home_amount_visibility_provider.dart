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
//
// 2026-10-19 D70 改(1.0.0 release UAT 反馈 user 体验 bug):
//   - D64.51 设计公式 hidden = !global || !local(任一为隐藏都隐藏,全局优先)
//     导致:"我的"页全局关 → 无论首页按钮怎么 toggle 都没用,user 反映
//     "点显示金额按钮无效,逻辑有问题"
//   - 重新拍板:改成 hidden = !global && !local(任一为可见都可见,local
//     能临时 override 全局)。理由:user 截图分享/给朋友看时,临时点开
//     应该是能 work 的,不需要先去"我的"页开全局再回来点
//   - 行为对比:
//     · 全局开 + local 开 = 显示(同 D64.51)
//     · 全局开 + local 关 = 隐藏(local 临时遮蔽,同 D64.51)
//     · 全局关 + local 开 = 显示(D70:local 临时突破全局,D64.51 是 hidden)
//     · 全局关 + local 关 = 隐藏(同 D64.51,user 明确全要藏)
//   - 注意:settings_page.dart 自己读 global (line 30),不受 combine 公式影响
//
// 用 `StateProvider<bool>` 简化 API,值是 reactive 但不需要持久化(用户明确说
// "临时性",重启 / 切 tab 后回到 true)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'amount_visibility_provider.dart';

/// 首页 local "显示金额" toggle —— 仅首页用
///   - 默认 true(显示金额,跟全局默认一致)
///   - 临时性(不写 SharedPreferences),重启 / 切 tab 后回到 true
///   - 跟 `amountVisibilityProvider`(全局)正交
final homeAmountVisibilityProvider = StateProvider<bool>((ref) => true);

/// 组合判断:global + home 任一为 visible 都整体显示
///   - 公式: hidden = !global && !local
///   - 即 visible = global || local(local 能临时 override 全局)
///
/// 用法:业务侧 widget 调
/// ```dart
/// final hidden = ref.watch(combineAmountVisibilityProvider);
/// ```
final combineAmountVisibilityProvider = Provider<bool>((ref) {
  final globalVisible = ref.watch(amountVisibilityProvider);
  final homeVisible = ref.watch(homeAmountVisibilityProvider);
  return !globalVisible && !homeVisible;
});
