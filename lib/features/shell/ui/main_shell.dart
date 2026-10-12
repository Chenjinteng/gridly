// lib/features/shell/ui/main_shell.dart
// 5 Tab 主容器:首页 / 流水 / 记一笔(中央) / 报表 / 我的
// 设计参考:design/THEME.md §6.2
//
// Stack 底层铺 LedgerGridBackground(16×16 格子纸背景),强化"格子"主题。
//
// 2026-10-12 ColorOS Aquamorphic 改造:
//   - body child 包 PageView(BouncingScrollPhysics),支持左滑右滑手势切 tab
//   - PageView 4 children:首页 / 流水 / 报表 / 我的(中央 + 是 push 路由,
//     不在 PageView 内)
//   - PageController 控制位置;切 nav (0/1/3/4) → animateToPage 对应 pageIndex;
//       swipe PageView → onPageChanged → context.go 同步路由
//   - PageView vs AnimatedSwitcher:PageView 的 swipe gesture 是用户主动手势,
//     navigation 手感更"原生";BouncingScrollPhysics 给 swipe 到边界回弹
//     (ColorOS Tactile)。
//
//   之前 commit 3 用 AnimatedSwitcher + 左右 slide,提供程序化切 tab 的过场;
//   这次 commit 36 加 PageView,左滑右滑手势支持。仍保留 nav 点击切 tab。
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
  /// PageController 控制 PageView 当前页。
  /// 初始 0(首页)。
  late final PageController _pageCtrl;

  /// 上一次 tab 切换的目的地 index —— 防止 onPageChanged 跟 nav 点击
  /// 之间出现重复 context.go() 循环。
  int? _lastDestIndex;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// nav destination index (0/1/3/4) → PageView pageIndex (0/1/2/3)
  /// 中央 + (dest 2) 不映射,走 push 路由。
  int _pageFromDest(int dest) => dest < 2 ? dest : dest - 1;

  /// PageView pageIndex (0/1/2/3) → nav destination index (0/1/3/4)
  int _destFromPage(int page) => page < 2 ? page : page + 1;

  /// 从当前路径算 nav destination index,跟 _currentIndex 等价
  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    // 中央"+" 占 destination index 2(空 label),所以 /stats / /settings
    // 在 destinations 里要 +1(跳开 index 2)
    // 在 /add(root modal)时不命中任何 tab;fallback 到 1(流水)避免
    // 底部 nav 高亮错乱。
    if (loc.startsWith('/add')) return 1;
    if (loc.startsWith('/edit')) return 1;
    if (loc.startsWith('/home')) return 0;
    if (loc.startsWith('/ledger')) return 1;
    if (loc.startsWith('/stats')) return 3;
    if (loc.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    // URL 路径变化(切路由、deeplink)时,PageView 同步过去
    //   守卫 _lastDestIndex 防 context.go 触发的 controller.animateToPage
    //   → onPageChanged → context.go 循环。
    final expectedPage = _pageFromDest(currentIndex);
    if (_pageCtrl.hasClients &&
        _pageCtrl.page?.round() != expectedPage) {
      // 路由先动,PageView 跟过去(用 jumpToPage 避免再触发 onPageChanged)
      _pageCtrl.jumpToPage(expectedPage);
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LedgerGridBackground()),
          // PageView:4 children,左滑右滑切换。PageView 自身动画已经够"丝滑",
          // 720ms 的曲线跟之前 AnimatedSwitcher 等价,无需额外 transition。
          // BouncingScrollPhysics:swipe 到边界 overscroll + 回弹(ColorOS 风)。
          Positioned.fill(
            child: PageView(
              controller: _pageCtrl,
              physics: const BouncingScrollPhysics(),
              // 不显示 PageView 默认的左右滚动条
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                scrollbars: false,
              ),
              onPageChanged: (page) {
                final dest = _destFromPage(page);
                // /add 或 /edit 期间(PageView user input 不会触发,因为 nav 2
                // 不在 PageView children 里),忽略
                if (dest == _lastDestIndex) return;
                _lastDestIndex = dest;
                // 触觉:swipe 切 tab 跟点 nav 一致,都用 selectionClick
                AppHaptics.select();
                // 路由同步
                switch (dest) {
                  case 0:
                    context.go('/home');
                  case 1:
                    context.go('/ledger');
                  case 3:
                    context.go('/stats');
                  case 4:
                    context.go('/settings');
                }
              },
              // 4 children 顺序对应 dest 0/1/3/4
              children: const [
                HomePage(),
                LedgerPage(),
                StatsPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          // 切 tab 时收掉挂着的 modal sheet:
          //   showModalBottomSheet 默认 push 到 ShellRoute 自带的 navigator
          //   (_shellNavigatorKey → 现在已暴露为 shellNavigatorKey)
          //   context.go() 只换 go_router 配置的 route,Navigator 栈不动,所以
          //   sheet 会"跨 tab 不消失"(2026-10-11 UAT bug 反复)。
          //
          // 不用 Navigator.of(context) 取就近 Navigator — 那值取决于 BuildContext
          // 的位置,在 onDestinationSelected 回调里不一定拿到 shellNavigatorKey
          // 那个。直接拿全局 key 的 currentState 准。
          final shellNav = shellNavigatorKey.currentState;
          if (shellNav != null && shellNav.canPop()) {
            shellNav.popUntil((route) => route.isFirst);
          }
          // 2026-10-12 ColorOS Tactile Haptics:tab 切换的标志性"咔哒"。
          // 用 selectionClick 比 lightImpact 更"轻",符合 ColorOS O-Haptic
          // 设计。中央"+" 按下用 tap(数字键同款,因为是触发操作)。
          if (i == 2) {
            AppHaptics.tap();
          } else {
            AppHaptics.select();
          }
          // 5 个 destination:0=首页 / 1=流水 / 2=中央 "+" / 3=报表 / 4=我的
          // i==2 推到 root modal;其它先同步 _lastDestIndex(避免 swipe 后
          // 反向 onPageChanged 触发重复 context.go),再用 PageController
          // 平滑滚到对应页。
          switch (i) {
            case 0:
              _lastDestIndex = 0;
              _pageCtrl.animateToPage(
                _pageFromDest(0),
                duration: const Duration(milliseconds: 720),
                curve: AppMotion.aquaIn,
              );
              context.go('/home');
            case 1:
              _lastDestIndex = 1;
              _pageCtrl.animateToPage(
                _pageFromDest(1),
                duration: const Duration(milliseconds: 720),
                curve: AppMotion.aquaIn,
              );
              context.go('/ledger');
            case 2:
              context.push('/add');
            case 3:
              _lastDestIndex = 3;
              _pageCtrl.animateToPage(
                _pageFromDest(3),
                duration: const Duration(milliseconds: 720),
                curve: AppMotion.aquaIn,
              );
              context.go('/stats');
            case 4:
              _lastDestIndex = 4;
              _pageCtrl.animateToPage(
                _pageFromDest(4),
                duration: const Duration(milliseconds: 720),
                curve: AppMotion.aquaIn,
              );
              context.go('/settings');
          }
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, size: 24),
            selectedIcon: Icon(Icons.dashboard_rounded, size: 24),
            label: '首页',
            // NavigationBar 默认把 label 当 tooltip 用,长按/悬停就弹一个
            // 跟 label 文字完全一样的浮窗(底部 nav 上是冗余噪声)。
            // tooltip 显式置空字符串关闭。
            tooltip: '',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined, size: 24),
            selectedIcon: Icon(Icons.list_alt_rounded, size: 24),
            label: '流水',
            tooltip: '',
          ),
          // 中央"+" 走大色块,THEME.md §6.2
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