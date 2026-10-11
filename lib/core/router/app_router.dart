// lib/core/router/app_router.dart
// go_router 配置 —— 包含 P3+ 子路由(分类管理等)
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
import '../../features/settings/ui/about_page.dart';

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
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/ledger',
            name: 'ledger',
            pageBuilder: (context, state) => const NoTransitionPage(child: LedgerPage()),
          ),
          GoRoute(
            path: '/stats',
            name: 'stats',
            pageBuilder: (context, state) => const NoTransitionPage(child: StatsPage()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
      // /add 放在 ShellRoute 之外 —— 作为 root navigator 上的 modal-style 页面。
      // 关闭或保存时 context.pop() 自动回到 shell 当前 tab(在哪个 tab 点 + 就回哪个),
      // 不再强制跳 /home。
      GoRoute(
        path: '/add',
        name: 'add',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: AddTransactionPage()),
      ),
      // /edit/:id 跟 /add 同架构(全屏 + resizeToAvoidBottomInset:false),
      // 流水编辑场景的全屏路由版 —— 2026-10-11 改,替换之前的 modal sheet 路线
      // (sheet 内 AnimatedPadding 推 Numpad 上移,跟全屏记一笔页不一致)
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
          return NoTransitionPage(child: EditTransactionPage(transactionId: id));
        },
      ),
      // Tab 外的子页面(在 root navigator 栈上,不全屏被 Shell 覆盖)
      GoRoute(
        path: '/settings/categories',
        name: 'categoryManagement',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CategoryManagementPage(),
      ),
      GoRoute(
        path: '/settings/about',
        name: 'about',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AboutPage(),
      ),
    ],
  );
});
