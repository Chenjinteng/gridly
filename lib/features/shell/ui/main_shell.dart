// lib/features/shell/ui/main_shell.dart
// 5 Tab 主容器:首页 / 流水 / 记一笔(中央) / 报表 / 我的
// 设计参考:design/THEME.md §6.2
//
// Stack 底层铺 LedgerGridBackground(16×16 格子纸背景),强化"格子"主题。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/ledger_grid_background.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/home', '/ledger', '/add', '/stats', '/settings'];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final i = _tabs.indexWhere((p) => loc.startsWith(p));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LedgerGridBackground()),
          Positioned.fill(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          context.go(_tabs[i]);
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, size: 24),
            selectedIcon: Icon(Icons.dashboard_rounded, size: 24),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined, size: 24),
            selectedIcon: Icon(Icons.list_alt_rounded, size: 24),
            label: '流水',
          ),
          // 中央"+" 走大色块,THEME.md §6.2
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.s1),
              child: _CenterFab(),
            ),
            label: '',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline, size: 24),
            selectedIcon: Icon(Icons.pie_chart_rounded, size: 24),
            label: '报表',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, size: 24),
            selectedIcon: Icon(Icons.person_rounded, size: 24),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 中央"+":大圆角色块,呼应 LOGO
class _CenterFab extends StatelessWidget {
  const _CenterFab();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppBrand.ink,
        borderRadius: AppRadius.brXl,
      ),
      child: const Icon(
        Icons.add_rounded,
        color: AppBrand.gold,
        size: 32,
      ),
    );
  }
}
