// lib/features/shell/ui/main_shell.dart
// 5 Tab 主容器:首页 / 流水 / 记一笔(中央) / 报表 / 我的
// 设计参考:design/THEME.md §6.2
//
// Stack 底层铺 LedgerGridBackground(16×16 格子纸背景),强化"格子"主题。
//
// 2026-10-12 ColorOS Aquamorphic 改造(commit 40):丝滑 tab 切换
//   - body:AnimatedSwitcher keyed,带 layoutBuilder Stack cross-fade
//     ── 之前 ──(commit 36):
//       PageView + animateToPage(720ms aquaIn)
//       切换是 horizontal slide,像 PPT 一页一页翻过去
//     ── 现在 ──:
//       AnimatedSwitcher 320ms aquaIn 交叉淡入淡出,无水平 slide
//       切入新 tab 时旧的跟新的同时存在(Stack 同时透明),全新/旧 view 之间
//       是 cross-fade,ColorOS 标准切 tab 风格
//   - bottom nav:NavigationBar + 自定义 ColorOS 17 风格 pill 指示器
//     (AnimatedPositioned 滑行 + easeOutBack 微 overshoot)
//     NavigationBar 自带的 tonal 指示器 indicatorColor:transparent 关掉,
//     自绘 pill 替上,更"圆滑有重量"
//   - tab 切换动效时长 320ms(比 M3 短促的 150ms 长,ColorOS 主动放慢)
//   - 触觉:select feedback(已在 commit 17 加)
//
// 注:PageView swipe-tab 已弃用 — ColorOS 应用从不支持左滑切 tab,那是
//     iOS 风。需要时再补回(commit 36 加过,但跟 cross-fade 不可叠加)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart' show shellNavigatorKey;
import '../../../core/theme/app_colors.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/ledger_grid_background.dart';
import '../../home/ui/home_page.dart';
import '../../ledger/ui/ledger_page.dart';
import '../../stats/ui/stats_page.dart';
import '../../settings/ui/settings_page.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 4 个 tab 页面的当前索引:0=首页 / 1=流水 / 2=报表 / 3=我的
  /// 注意:FAB 不在 4 个 tab 内,dest 2 走 push '/add' 路由
  int _currentTab = 0;

  /// 上一次 sync 过的 route tab —— 防 context.go 与 route 同步之间循环
  int _lastRouteTab = -1;

  /// 4 个 tab 实际渲染的页面(dest 0/1/3/4 直接索引)
  static const _pages = <Widget>[
    HomePage(),
    LedgerPage(),
    StatsPage(),
    SettingsPage(),
  ];

  /// 从 GoRouter 当前路径算出 tab index(0/1/2/3),对不上路由(例如 /add
  /// modal)时 fallback 1(流水),避免底部 nav 错乱高亮
  int _tabFromRoute(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/home')) return 0;
    if (loc.startsWith('/ledger')) return 1;
    if (loc.startsWith('/stats')) return 2;
    if (loc.startsWith('/settings')) return 3;
    // /add、/edit 弹 modal 期间默认高亮流水
    if (loc.startsWith('/add')) return 1;
    if (loc.startsWith('/edit')) return 1;
    return 0;
  }

  /// tab index → router path
  String _routeFor(int tab) {
    switch (tab) {
      case 0:
        return '/home';
      case 1:
        return '/ledger';
      case 2:
        return '/stats';
      case 3:
      default:
        return '/settings';
    }
  }

  /// NavigationBar 的 destination 索引(0/1/2/3/4),tab index 与之差 1
  /// ── tab 0=home → dest 0
  /// ── tab 1=ledger → dest 1
  /// ── tab 2=stats → dest 3
  /// ── tab 3=settings → dest 4
  /// ── (dest 2 是中央 + FAB)
  int _destForTab(int tab) => tab < 2 ? tab : tab + 1;

  /// 处理 tab 切换(NavigationBar onDestinationSelected 入口)
  void _handleDestSelected(int dest) {
    // 中央 + 走 push 路由,不切 tab
    if (dest == 2) {
      AppHaptics.tap();
      final shellNav = shellNavigatorKey.currentState;
      if (shellNav != null && shellNav.canPop()) {
        shellNav.popUntil((route) => route.isFirst);
      }
      context.push('/add');
      return;
    }

    final newTab = dest < 2 ? dest : dest - 1;
    if (newTab == _currentTab) return;

    // 切 tab 时收掉挂着的 modal(2026-10-11 UAT bug)
    final shellNav = shellNavigatorKey.currentState;
    if (shellNav != null && shellNav.canPop()) {
      shellNav.popUntil((route) => route.isFirst);
    }
    // 触觉:标准切 tab 用 select(短促 selectionClick)
    AppHaptics.select();
    _lastRouteTab = newTab;
    setState(() => _currentTab = newTab);
    context.go(_routeFor(newTab));
  }

  @override
  Widget build(BuildContext context) {
    // 路由 → tab index 同步(deeplink / 外部触发)
    final routeTab = _tabFromRoute(context);
    if (routeTab != _lastRouteTab && routeTab != _currentTab) {
      _lastRouteTab = routeTab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentTab = routeTab);
      });
    } else {
      _lastRouteTab = routeTab;
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LedgerGridBackground()),
          // 2026-10-12 (commit 40):body 切 tab 用 AnimatedSwitcher cross-fade
          // ── 之前 ──:PageView + animateToPage → 水平横滑,iOS 风
          // ── 现在 ──:320ms aquaIn/aquaOut 交叉淡入淡出,完全无水平 slide
          // layoutBuilder Stack 让 previous children 跟 current child 同时
          // 渲染,中间没有"空白帧"
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: AppMotion.aquaIn,
              switchOutCurve: AppMotion.aquaOut,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: ValueKey('tab-$_currentTab'),
                child: _pages[_currentTab],
              ),
            ),
          ),
        ],
      ),
      // 2026-10-12 (commit 40):底 nav 自定义 ColorOS 17 pill indicator
      //   - NavigationBar 内部 indicator(tonal pill) 关掉(indicatorColor: 透明)
      //   - 上面叠 LayerBuilder + AnimatedPositioned 来自绘 pill
      //   - easeOutBack 微 overshoot,ColorOS 风格"轻撞击感"
      bottomNavigationBar: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            const destCount = 5;
            const pillW = 64.0;
            const pillH = 32.0;
            final slotW = constraints.maxWidth / destCount;
            // pill 选中 dest(0..4);dest 2 (FAB 选中)时 pill 隐藏
            final selectedDest = _destForTab(_currentTab);
            // pill left:slot 中心对齐
            final pillLeft =
                selectedDest * slotW + (slotW - pillW) / 2;
            return SizedBox(
              height: 72,
              child: Stack(
                children: [
                  NavigationBar(
                    height: 72,
                    selectedIndex: selectedDest,
                    onDestinationSelected: _handleDestSelected,
                    backgroundColor:
                        Theme.of(context).colorScheme.surface,
                    // 关闭 NavigationBar 自带的 tonal pill
                    indicatorColor: Colors.transparent,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined, size: 24),
                        selectedIcon: Icon(Icons.dashboard_rounded, size: 24),
                        label: '首页',
                        tooltip: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.list_alt_outlined, size: 24),
                        selectedIcon: Icon(Icons.list_alt_rounded, size: 24),
                        label: '流水',
                        tooltip: '',
                      ),
                      // 中央"+":大圆角色块
                      NavigationDestination(
                        icon: Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.s1),
                          child: _CenterFab(),
                        ),
                        label: '',
                        tooltip: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.pie_chart_outline, size: 24),
                        selectedIcon: Icon(Icons.pie_chart_rounded, size: 24),
                        label: '报表',
                        tooltip: '',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline, size: 24),
                        selectedIcon: Icon(Icons.person_rounded, size: 24),
                        label: '我的',
                        tooltip: '',
                      ),
                    ],
                  ),
                  // ColorOS 17 风格 pill indicator:
                  //   - secondaryContainer 实色(更高对比度的"小药丸")
                  //   - 选中时 fade in(200ms aquaIn),位置滑过去(420ms easeOutBack)
                  //   - dest 2 (中央 FAB 选中)时整 pill 隐藏
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    left: pillLeft,
                    top: (72 - pillH) / 2 + 4,
                    width: pillW,
                    height: pillH,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: AppMotion.aquaIn,
                      opacity: selectedDest == 2 ? 0.0 : 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 中央"+":大圆角色块,呼应 LOGO
/// - BoxShape.circle 保证真正圆(56x56 下 borderRadius=24 是圆角矩形不是圆)
/// - dark mode 下 ink 块 → cream,和 LOGO onDark 模式一致(避免和 Ink surface 融掉)
class _CenterFab extends StatelessWidget {
  const _CenterFab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? AppSecondary.cream : AppBrand.ink,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.add_rounded,
        color: isDark ? AppBrand.ink : AppBrand.gold,
        size: 32,
      ),
    );
  }
}
