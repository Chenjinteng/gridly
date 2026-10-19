// lib/core/widgets/show_app_modal_sheet.dart
// 应用级 modal bottom sheet 包装 —— 修 go_router + ShellRoute 下系统返回键退 app。
//
// 2026-10-17 D66 加:
//   修 user UAT 报"几个 popup 弹,系统返回操作会退出整个 app,不会只关闭 popup"。
//   这是历史反复 bug,三次尝试(D64.18 / D64.19 / D64.20)都只修一类 call site 漏一类。
//
//   D66 当时 useRootNavigator:false + PopScope 双层防御。但装机实测仍有 2 个 sheet
//   退 app(我的 CSV 导出 + 流水快速筛选)。D70.4 加 WillPopScope 兜底也没用。
//
// 2026-10-19 D70.5 抓到 logcat root cause(原 useRootNavigator:false 假设错了):
//   logcat 完整 trace:
//     RootBackButtonDispatcher.didPopRoute
//       → GoRouterDelegate.popRoute
//         → _findCurrentNavigator()
//           → line 114: `walker.navigatorKey.currentState!` 抛 NPE
//     `Null check operator used on a null value`
//   异常被 WidgetsBinding.handlePopRoute 的 try-catch 吞掉,继续往下走
//   → SystemNavigator.pop() → app 退
//
//   反过来 D70.5 useRootNavigator:true 没修到,因为 NPE 跟 modal 位置无关,
//   是 go_router 14.8.1 _findCurrentNavigator 在 matches.last 是 ShellRouteMatch
//   时访问 shellNavigatorKey.currentState 拿到 null 的框架 bug。
//
// 2026-10-19 D70.6 真正修法(WidgetsBindingObserver 拦截 back 在 GoRouter 之前):
//   - 注册一个 WidgetsBindingObserver 在 main.dart 启动时(早于 MaterialApp.router
//     创建 RootBackButtonDispatcher),WidgetsBinding.handlePopRoute 遍历 observers
//     时按注册顺序调用,我们的 observer 先于 RootBackButtonDispatcher 处理 back
//   - observer 检查是否有 modal 打开,有则自己 pop modal + 返回 true(back handled),
//     WidgetsBinding 不再往下调 RootBackButtonDispatcher → 绕开 NPE
//   - 没有 modal 时返回 false,让默认 RootBackButtonDispatcher 处理(正常 GoRouter 行为)
//
//   PopScope + WillPopScope 保留(D70.4)作为 inner 兜底,modal 自己被任何方式
//   关闭(drag / close 按钮 / 滑下来)都能干净 dispose。
import 'dart:async';

import 'package:flutter/material.dart';

/// 应用级 modal bottom sheet —— 修 Android 系统返回键退 app 跟 iOS swipe-down
/// 在 go_router + ShellRoute 下的 back 路由问题(D70.6)。
///
/// 用法跟 [showModalBottomSheet] 1:1,直接替换 call site 的函数名即可。
///
/// 跟原 [showModalBottomSheet] 的差异(D66 + D70.4 + D70.5 + D70.6 内置):
/// - [WidgetsBindingObserver] 拦截器(D70.6) —— 全局单例,在 main.dart 启动时注册,
///   早于 MaterialApp.router 的 RootBackButtonDispatcher,系统 back 先到我们这里
/// - [useRootNavigator] 强制 true(D70.5) —— modal 推到 root Navigator
/// - builder 内容外双层防御(D70.4)保留:PopScope + WillPopScope
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
  // D70.6:在 WidgetsBindingObserver 注册 modal。observer 在 main.dart 启动时
  // 已 add,我们的 handlePopRoute 会先于 RootBackButtonDispatcher 被调,
  // 有 modal 时直接 pop 模态,返回 true → WidgetsBinding 不再往下调 GoRouter
  // → 绕开 go_router 14.8.1 _findCurrentNavigator NPE
  final navigator = Navigator.of(context, rootNavigator: true);

  return _ModalBackInterceptor.instance.runWithModal<T>(
    navigator: navigator,
    showSheet: () => showModalBottomSheet<T>(
      context: context,
      // D70.5:改回 true(反 D66)。go_router 14.8.1 的 _findCurrentNavigator
      //   在 modal 在 shell sub-navigator 时会 NPE (delegate.dart:114
      //   `walker.navigatorKey.currentState!`),所以 modal 必须推到 root navigator
      //   让 GoRouter 的 matches.last 是 RouteMatch (不是 ShellRouteMatch),
      //   跳过 while 循环,不触发 NPE。
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      shape: shape,
      routeSettings: routeSettings,
      builder: (ctx) {
        // D66-② + D70.4:PopScope 现代 API 优先路径
        //   canPop:false → ModalRoute.popDisposition 走 doNotPop 分支
        //   onPopInvokedWithResult → 手动 Navigator.of(ctx).pop() 关闭 sheet
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
    ),
  );
}

/// 全局 WidgetsBindingObserver,系统 back 拦截器(D70.6)。
///
/// 注册时机:必须在 MaterialApp.router 创建 RootBackButtonDispatcher 之前
/// (在 main.dart `WidgetsBinding.instance.addObserver(_ModalBackInterceptor.instance)`
/// 早于 runApp 调用)。
///
/// 工作原理:
/// - WidgetsBinding.handlePopRoute 遍历 observers(按注册顺序)调 didPopRoute
/// - 我们 observer 第一个被调,因为 main.dart 启动时先 add 我们
/// - 有 modal 打开时,我们的 didPopRoute 手动 pop 模态 + 返回 true
/// - 返回 true → WidgetsBinding.handlePopRoute 直接返 true → 不再调后续
///   RootBackButtonDispatcher → 绕开 go_router 14.8.1 _findCurrentNavigator NPE
/// - 没 modal 时返回 false → 后续 RootBackButtonDispatcher 正常处理(正常 GoRouter 行为)
class _ModalBackInterceptor with WidgetsBindingObserver {
  _ModalBackInterceptor._();

  /// 全局单例。main.dart 启动时 addObserver 后,modal 拦截就生效。
  static final _ModalBackInterceptor instance = _ModalBackInterceptor._();

  /// 记录当前打开的 modal 数量(stack 形式,支持嵌套 sheet)
  int _modalCount = 0;

  /// D70.6 系统 back 拦截器 + modal 生命周期管理
  Future<T?> runWithModal<T>({
    required NavigatorState navigator,
    required Future<T?> Function() showSheet,
  }) {
    _modalCount++;
    final completer = Completer<T?>();
    showSheet().then((result) {
      _modalCount--;
      if (!completer.isCompleted) completer.complete(result);
    }).catchError((Object e, StackTrace s) {
      _modalCount--;
      if (!completer.isCompleted) completer.completeError(e, s);
    });
    return completer.future;
  }

  @override
  Future<bool> didPopRoute() async {
    // 有 modal 打开:我们自己 pop 模态,返回 true 让 WidgetsBinding 不再往下走
    if (_modalCount > 0) {
      // 找一个能 pop 的 navigator(root navigator 是最稳的)
      final rootNav = WidgetsBinding.instance.rootElement
          ?.findAncestorStateOfType<NavigatorState>();
      if (rootNav != null && rootNav.canPop()) {
        rootNav.pop();
        return true;
      }
    }
    // 没 modal:让默认 RootBackButtonDispatcher 处理(返回 false 让 handlePopRoute
    // 继续遍历 / 调 SystemNavigator.pop)
    return false;
  }
}

/// 暴露注册入口给 main.dart,在 runApp 之前调用一次
void registerModalBackInterceptor() {
  WidgetsBinding.instance.addObserver(_ModalBackInterceptor.instance);
}
