// lib/core/router/app_router.dart
// go_router 配置 —— 包含 P3+ 子路由(分类管理等)
//
// 路由过渡(2026-10-12 ColorOS Aquamorphic 改造,commit 107 改):
//   - /  splash:NoTransition(开场主屏,过渡是 splash 自己处理)
//   - /home /ledger /stats /settings (ShellRoute 内):NoTransitionPage
//     —— tab 切换的"方向感"在 MainShell 的 AnimatedSwitcher 里实现,
//     不在路由层做(否则双层动画叠加看着抖)
//   - /add /edit/:id (root modal):CustomTransitionPage 从底部 480ms 上推
//     + fade,符合"记一笔"全屏 sheet 体感,不是硬 slide-from-bottom
//   - /settings/categories /settings/about /settings/budget (push 子页):
//     slide-up 24px + fade,normal 480ms aquaIn(commit 107 改 slow→normal)
//     + fade 用 Interval(0.0, 0.4) 在前 40% 时间完成 —— 解决"淡入看到
//     背景残影"问题(原来 slow 680ms + 全程 fade 透明度渐变,过程中能
//     看到底下 home 页内容残影)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/splash/splash_page.dart';
import '../../features/shell/ui/main_shell.dart';
import '../../features/home/ui/home_page.dart';
import '../../features/ledger/ui/ledger_page.dart';
import '../../features/add/ui/add_transaction_page.dart';
import '../../features/add/ui/edit_transaction_page.dart';
import '../../features/stats/ui/stats_page.dart';
import '../../features/settings/ui/settings_page.dart';
import '../../features/settings/ui/category_management_page.dart';
import '../../features/settings/ui/budget_management_page.dart';
import '../../features/settings/ui/assets_management_page.dart';
import '../../features/settings/ui/about_page.dart';
import '../motion/app_motion.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
// 2026-10-11 暴露:MainShell.onDestinationSelected 用它显式 popUntil 切 tab 时
// 关闭挂着的 modal sheet(navigatorOf(context) 找的 Navigator 不一定就是这个)

/// commit 108 加:统一 push 子页过渡(slide + fade,360ms)
///   - 之前(commit 107)用 normal 480ms + Interval(0.0, 0.4),user 反馈
///     "淡入淡出太慢,跟 enter 一样配置"——reverse 也 480ms + Interval(0.0, 0.4)
///     在 aquaIn 曲线前段慢感下,reverse 仍觉得拖
///   - 改 360ms + Interval(0.0, 0.3) — 紧凑、reverse 跟 enter 一致配置
///     fade 前 30% 时间完成(108ms),slide 仍跑完全程保留 aquaIn 重量感
CustomTransitionPage<void> _pushSubPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    // commit 108 改:enter 跟 reverse 同步,360ms
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppMotion.aquaIn)),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.3, curve: AppMotion.aquaIn),
          ),
          child: child,
        ),
      );
    },
  );
}

final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => MainShell(),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/ledger',
            name: 'ledger',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LedgerPage()),
          ),
          GoRoute(
            path: '/stats',
            name: 'stats',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StatsPage()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
      // /add 放在 ShellRoute 之外 —— 作为 root navigator 上的 modal-style 页面。
      // 关闭或保存时 context.pop() 自动回到 shell 当前 tab(在哪个 tab 点 + 就回哪个),
      // 不再强制跳 /home。
      //
      // 过渡:从底部 480ms 上推 + fade —— ColorOS Aqua Dynamics 的 modal-style。
      // 比 M3 的 slide-from-bottom 慢且"软",不是硬切。
      GoRoute(
        path: '/add',
        name: 'add',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: AppMotion.normal,
          reverseTransitionDuration: AppMotion.fast,
          // 2026-10-13 P6:接受 extra:preselectedAssetType(短按='cash_flow',长按=5 小圆选)
          child: AddTransactionPage(
            preselectedAssetType: state.extra as String?,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: AppMotion.aquaIn),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: AppMotion.aquaIn,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      // /edit/:id 跟 /add 同架构(全屏 + resizeToAvoidBottomInset:false),
      // 流水编辑场景的全屏路由版 —— 2026-10-11 改,替换之前的 modal sheet 路线
      // (sheet 内 AnimatedPadding 推 Numpad 上移,跟全屏记一笔页不一致)
      // 过渡同 /add(从底上推)。
      GoRoute(
        path: '/edit/:id',
        name: 'edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) {
            // 路由参数错误,退回上一页
            return NoTransitionPage(
              child: Builder(
                builder: (ctx) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!ctx.mounted) return;
                    ctx.pop();
                  });
                  return const Scaffold();
                },
              ),
            );
          }
          return CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: AppMotion.normal,
            reverseTransitionDuration: AppMotion.fast,
            child: EditTransactionPage(transactionId: id),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: AppMotion.aquaIn,
                          ),
                        ),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: AppMotion.aquaIn,
                      ),
                      child: child,
                    ),
                  );
                },
          );
        },
      ),
      // Tab 外的子页面(在 root navigator 栈上,不全屏被 Shell 覆盖)
      // 过渡(commit 107 改):_pushSubPage helper(slide + fade,normal 480ms)
      //   解决"淡入看到背景残影"问题(原 slow 680ms 全程 fade 透明度渐变)
      GoRoute(
        path: '/settings/categories',
        name: 'categoryManagement',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _pushSubPage(
          key: state.pageKey,
          child: const CategoryManagementPage(),
        ),
      ),
      GoRoute(
        path: '/settings/about',
        name: 'about',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _pushSubPage(key: state.pageKey, child: const AboutPage()),
      ),
      // commit 106 加:月度预算配置全屏路由
      //   之前用 showModalBottomSheet(BudgetSheet),user 反馈还有掉帧
      //   改成全屏 page(viewInsets 由 Scaffold 处理 + 无弹窗过渡动画)
      GoRoute(
        path: '/settings/budget',
        name: 'budgetManagement',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _pushSubPage(
          key: state.pageKey,
          child: const BudgetManagementPage(),
        ),
      ),
      // 2026-10-12 P2 加:我的页资产 section 全屏路由
      //   类比 /settings/budget:全屏 page,viewInsets 由 Scaffold 处理,
      //   无 showModalBottomSheet 弹窗过渡动画。
      GoRoute(
        path: '/settings/assets',
        name: 'assetsManagement',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _pushSubPage(
          key: state.pageKey,
          child: const AssetsManagementPage(),
        ),
      ),
    ],
  );
});
