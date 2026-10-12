// lib/core/router/app_router.dart
// go_router 配置 —— 包含 P3+ 子路由(分类管理等)
//
// 路由过渡(2026-10-12 ColorOS Aquamorphic 改造):
//   - /  splash:NoTransition(开场主屏,过渡是 splash 自己处理)
//   - /home /ledger /stats /settings (ShellRoute 内):NoTransitionPage
//     —— tab 切换的"方向感"在 MainShell 的 AnimatedSwitcher 里实现,
//     不在路由层做(否则双层动画叠加看着抖)
//   - /add /edit/:id (root modal):CustomTransitionPage 从底部 480ms 上推
//     + fade,符合"记一笔"全屏 sheet 体感,不是硬 slide-from-bottom
//   - /settings/categories /settings/about (push 子页):fade + 微微上推
//     24px,720ms aquaIn —— 比 M3 默认 transition 慢且有"重量感"
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
import '../../features/settings/ui/about_page.dart';
import '../motion/app_motion.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
// 2026-10-11 暴露:MainShell.onDestinationSelected 用它显式 popUntil 切 tab 时
// 关闭挂着的 modal sheet(navigatorOf(context) 找的 Navigator 不一定就是这个)
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
          child: const AddTransactionPage(),
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
      // 过渡:fade + 微微上推 24px,720ms aquaIn —— 比 M3 默认 transition
      // 慢且有"重量感",不要用 CupertinoPageTransitionsBuilder 那套 iOS slide。
      GoRoute(
        path: '/settings/categories',
        name: 'categoryManagement',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: AppMotion.slow,
          reverseTransitionDuration: AppMotion.normal,
          child: const CategoryManagementPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.06),
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
      GoRoute(
        path: '/settings/about',
        name: 'about',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: AppMotion.slow,
          reverseTransitionDuration: AppMotion.normal,
          child: const AboutPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.06),
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
      // commit 106 加:月度预算配置全屏路由
      //   之前用 showModalBottomSheet(BudgetSheet),user 反馈还有掉帧
      //   改成全屏 page(viewInsets 由 Scaffold 处理 + 无弹窗过渡动画)
      GoRoute(
        path: '/settings/budget',
        name: 'budgetManagement',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: AppMotion.slow,
          reverseTransitionDuration: AppMotion.normal,
          child: const BudgetManagementPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.06),
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
    ],
  );
});
