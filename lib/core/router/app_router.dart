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
import '../../features/stats/ui/stats_page.dart';
import '../../features/settings/ui/settings_page.dart';
import '../../features/settings/ui/category_management_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

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
        navigatorKey: _shellNavigatorKey,
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
            path: '/add',
            name: 'add',
            pageBuilder: (context, state) => const NoTransitionPage(child: AddTransactionPage()),
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
      // Tab 外的子页面(在 root navigator 栈上,不全屏被 Shell 覆盖)
      GoRoute(
        path: '/settings/categories',
        name: 'categoryManagement',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CategoryManagementPage(),
      ),
    ],
  );
});
