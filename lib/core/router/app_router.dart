// lib/core/router/app_router.dart
// go_router 配置 —— P0 阶段只挂空壳,后续 P1+ 在这里加业务路由
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

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      // 启动页(2 秒后跳到 /home)
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      // 主 Tab 容器
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
    ],
  );
});
