// lib/features/shell/ui/main_shell.dart
// 5 Tab 主容器:首页 / 流水 / 记一笔(中央) / 报表 / 我的
// 设计参考:design/THEME.md §6.2
//
// Stack 底层铺 LedgerGridBackground(16×16 格子纸背景),强化"格子"主题。
//
// 2026-10-12 ColorOS Aquamorphic 改造:
//   - StatelessWidget → ConsumerStatefulWidget(为了持 _prevIndex)
//   - body child 包 AnimatedSwitcher,根据 _prevIndex → currentIndex 方向
//     计算 slide offset(±1 = 左右滑入/滑出)
//   - 切到 /add 时 currentIndex fallback 到 1(流水),不触发 slide ——
//     因为 /add 是 root modal 路由,自身已经带从底上推动画,叠加会抖
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart' show shellNavigatorKey;
import '../../../core/theme/app_colors.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/ledger_grid_background.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 上一次 build 的 tab index —— 用于 AnimatedSwitcher 计算 slide 方向。
  /// 初始 0(首页),切到 /add 时仍 fall back 到 1(流水)但不更新 prev,
  /// 因为 /add 是 root modal 不触发 tab 动画。
  int _prevIndex = 0;

  /// 之前是否在 modal 路由(/add 或 /edit)。modal 不计入 tab slide。
  bool _wasOnModal = false;

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

  bool _isModal(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    return loc.startsWith('/add') || loc.startsWith('/edit');
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);
    final onModal = _isModal(context);

    // slide 方向:只在 tab 间切换时算(从 modal 进/出不算 tab slide)
    int dir = 0;
    if (!_wasOnModal && !onModal) {
      dir = currentIndex > _prevIndex ? 1 : (currentIndex < _prevIndex ? -1 : 0);
    }
    _prevIndex = currentIndex;
    _wasOnModal = onModal;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LedgerGridBackground()),
          // AnimatedSwitcher 包 child:tab 切换时左右 slide + fade,
          // /add modal 时 fallback 到 1 不触发 slide(模态自己带从底上推)。
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              reverseDuration: AppMotion.fast,
              switchInCurve: AppMotion.aquaIn,
              switchOutCurve: AppMotion.aquaOut,
              // 用 pageStorageBucket-style key 维持各 tab 的滚动位置;
              // PageStorageKey 用 path 区分每个 tab。
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topLeft,
                  children: <Widget>[
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                // 进:从 -dir*0.06 滑入 + fade;出:滑到 +dir*0.06 + fade
                final enterOffset = Tween<Offset>(
                  begin: Offset(-dir * 0.06, 0),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(
                  position: enterOffset,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              // key 用 currentIndex + 是否 modal —— modal 时 key 跟当前 tab
              // 一样,不会触发新的 switcher 切换(叠加路由层动画)
              child: KeyedSubtree(
                key: ValueKey('tab-$currentIndex-${onModal ? 'modal' : 'page'}'),
                child: widget.child,
              ),
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
          // 5 个 destination:0=首页 / 1=流水 / 2=中央 "+" / 3=报表 / 4=我的
          // i==2 推到 root modal,其它用 go 清栈切换
          switch (i) {
            case 0:
              context.go('/home');
            case 1:
              context.go('/ledger');
            case 2:
              context.push('/add');
            case 3:
              context.go('/stats');
            case 4:
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