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
//
// 2026-10-19 D70.4 修(1.0.1 装机实测 user 反馈仍有 2 个 sheet — 我的 CSV 导出 +
//   流水快速筛选 — 退 app):
//   - 单独 PopScope 防御在某些场景仍被绕开(可能是 Flutter 3.47.7 + GoRouter 14.8.1
//     下 PopScope 的 PopEntry 注册时序问题,或 popDisposition 走到 bubble 分支)
//   - 加 WillPopScope(legacy API,直接调 addScopedWillPopCallback 钩 ModalRoute.willPop)
//     做 belt-and-suspenders 兜底,跟 PopScope 互不影响
//     · WillPopScope.onWillPop → Future.value(false) → 阻止 back 弹掉 modal route
//     · 用户期待"按 back 关掉 sheet",但默认 modal route 是会自己 pop 掉
//     · 关键是 WillPopScope 拦下 back 后手动 Navigator.pop(ctx),走 ModalRoute
//       自带的 onDidPopNext/onDispose 清理栈,不会让 back 漏到 GoRouter 兜底
//   - PopScope 保留作为现代 API 优先路径(canPop:false → popDisposition doNotPop)
//   - 两层任一生效就够,互不冲突
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
/// 跟原 [showModalBottomSheet] 的差异(D66 + D70.4 内置):
/// - [useRootNavigator] 强制 false —— sheet 跟调用方同 Navigator 栈。
/// - builder 内容外双层防御:
///   · PopScope (canPop: false) —— Flutter 3.12+ 现代 API,hook popDisposition
///   · WillPopScope (onWillPop → false, 内部 pop) —— legacy API,直接 addScopedWillPopCallback
///     hook ModalRoute.willPop。两者互不冲突,任一生效都够
/// - 命中任一拦截 → 手动 `Navigator.of(ctx).pop()` 关闭 sheet,
///   不走到 GoRouter.delegate.popRoute 兜底 → 不再退 app
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
    builder: (ctx) {
      // D66-②:PopScope 自包含 back handler,拦截系统 back → 手动 pop sheet,
      // 不走到 GoRouter 的 popRoute 兜底 → 不再退 app。
      // D70.4:保留作为现代 API 优先路径
      final popScopeLayer = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          Navigator.of(ctx).pop();
        },
        child: Builder(builder: builder),
      );
      // D70.4:WillPopScope 兜底层,直接调 addScopedWillPopCallback 钩
      // ModalRoute.willPop(legacy API,Flutter 3.12 标记 deprecated 但仍 work)。
      // 跟 PopScope 互不影响 —— 一个 hook popDisposition,一个 hook willPop,
      // Navigator.maybePop 链路上任一拦下就够,不会漏到 GoRouter 兜底退 app。
      // ignore: deprecated_member_use
      return WillPopScope(
        onWillPop: () async {
          Navigator.of(ctx).pop();
          return false; // 阻止 back 弹掉 route 本身(我们已经手动 pop 了)
        },
        child: popScopeLayer,
      );
    },
  );
}
