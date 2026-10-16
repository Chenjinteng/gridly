// lib/core/widgets/show_app_modal_sheet.dart
// 应用级 modal bottom sheet 包装 —— 修 go_router + ShellRoute 下系统返回键退 app。
//
// 2026-10-17 D66 加:
//   修 user UAT 报"几个 popup 弹,系统返回操作会退出整个 app,不会只关闭 popup"。
//   这是历史反复 bug,三次尝试(D64.18 / D64.19 / D64.20)都只修一类 call site 漏一类。
//
//   根因(深挖,D64.20 注释 + 自己实测推断):
//   - MaterialApp.router + GoRouter 在 root NavigatorState 上挂 RootBackButtonDispatcher
//     (GoRouter.delegate 实现 popRoute 兜底)。
//   - showModalBottomSheet 推到 shell sub-navigator(stack:[shell > sheet])。
//   - Android back 触发 → Flutter handlePopRoute → RootBackButtonDispatcher
//     → GoRouterDelegate.popRoute → 走 matches 找当前 navigator。
//   - matches 只包含 go_router 自己 push 的路由(/home 等 tab + /add push 的),
//     **不包含 Flutter Navigator 自己 push 的 modal route**
//     (因为 showModalBottomSheet 是 raw Navigator.push,不走 GoRouter 注册)。
//   - delegate 找不到能 canPop 的 match → popRoute 返 false →
//     RootBackButtonDispatcher 系统级 fallback → SystemNavigator.pop() → app 退。
//
//   根因以前所有 patch 失败的原因:
//   - D64.18 加 PopScope 套 raw pushed page,D64.18 的 onPopInvokedWithResult
//     调用 Navigator.pop() 的顺序不对,因为 state.maybePop() 已先返回 false
//     触发 SystemNavigator.pop(),来不及救。
//   - D64.19 audit 漏看 — 默认 Flutter ModalBottomSheetRoute 自己处理 back,
//     但实际在 MaterialApp.router + GoRouter 下被 dispatcher 抢先 -> 没机会处理。
//   - D64.20 加 useRootNavigator: false,把 sheet 推到 sub-navigator,但 root
//     dispatcher 仍接管 → popRoute 仍走 GoRouterDelegate.matches 兜底 → 仍退 app。
//
//   本次真修(D66):
//   - 抽 showAppModalBottomSheet<T>() helper,内置两层防御:
//     ① useRootNavigator: false —— sheet 跟调用方同 navigator 栈(shell 或 root)
//     ② PopScope(canPop: false, onPopInvokedWithResult → Navigator.of(ctx).pop())
//        包在 builder 内容外 —— sheet 自己拦截系统 back,根本不走到 GoRouter 兜底
//   - 用法跟 showModalBottomSheet 1:1,call site 替换即可,无业务改动。
//   - 影响范围:全仓库 11 处 call site(流水 picker 3 + 我的 CSV + 记一笔 picker 3
//     + budget + date picker + 报表 range 2 + 分类管理 form)。
import 'package:flutter/material.dart';

/// 应用级 modal bottom sheet —— 修 Android 系统返回键退 app 跟 iOS swipe-down
/// 在 go_router + ShellRoute 下的 back 路由问题。
///
/// 用法跟 [showModalBottomSheet] 1:1,直接替换 call site 的函数名即可:
/// ```dart
/// final picked = await showAppModalBottomSheet<T>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: ...,
///   builder: (_) => MySheet(),
/// );
/// ```
///
/// 跟原 [showModalBottomSheet] 的差异(D66 内置):
/// - [useRootNavigator] 强制 false —— sheet 跟调用方同 Navigator 栈。
/// - builder 内容外包 [PopScope] (canPop: false) —— 系统 back 命中 sheet 自拦截,
///   手动 `Navigator.of(ctx).pop()`,不走 GoRouter.delegate.popRoute 兜底分支。
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  EdgeInsets? insetAnimationDuration,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // D66-①:sheet 推到调用方最深的 Navigator(跟 ledger_page/settings_page 同栈),
    //          不再走 root Navigator。
    useRootNavigator: false,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    shape: shape,
    routeSettings: routeSettings,
    // D66-②:PopScope 自包含 back handler,拦截系统 back → 手动 pop sheet,
    // 不走到 GoRouter 的 popRoute 兜底 → 不再退 app。
    builder: (ctx) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(ctx).pop();
      },
      child: Builder(builder: builder),
    ),
  );
}
