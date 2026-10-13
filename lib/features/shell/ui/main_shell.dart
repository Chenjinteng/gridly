// lib/features/shell/ui/main_shell.dart
// 5 Tab 主容器:首页 / 流水 / 记一笔(中央) / 报表 / 我的
// 设计参考:design/THEME.md §6.2
//
// Stack 底层铺 LedgerGridBackground(16×16 格子纸背景),强化"格子"主题。
//
// 2026-10-12 ColorOS Aquamorphic 改造(commit 40):丝滑 tab 切换
//   - body:AnimatedSwitcher keyed + 方向感知 SlideTransition
//     ── commit 36 ──:PageView + animateToPage(720ms aquaIn)横滑,iOS 风
//     ── commit 40 ──:纯 AnimatedSwitcher 320ms cross-fade,无水平位移,
//                     但 user 反馈"页面切换还是生硬"
//     ── commit 43 ──:撤掉 pill,只靠 icon + label 改色标识
//     ── commit 44 (本版)──:cross-fade 上加方向感知 slide,offset = -dir*0.06
//                     tap→右:新页从 +0.06(右侧)滑入,旧页向左侧滑出
//                     tap→左:新页从 -0.06(左侧)滑入,旧页向右侧滑出
//                     ColorOS 切 tab 的标志性"页面推过去"
//   - bottom nav:NavigationBar 直接靠默认 selectIndIcon + 金 label 颜色做
//     选区标识,不叠自定义 pill(commit 41-42 两版 pill 都撞视觉,撤掉)
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
import 'speed_dial_list_popup.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// 4 个 tab 页面的当前索引:0=首页 / 1=流水 / 2=报表 / 3=我的
  /// 注意:FAB 不在 4 个 tab 内,dest 2 走 push '/add' 路由
  int _currentTab = 0;

  /// 2026-10-13 P6 第 11 次改:Speed Dial 状态
  ///   - 之前用 Overlay,在 Overlay 内 Listener 收不到 long press 之后的
  ///     PointerMove(用户描述"得先松开再触碰才能滑动选")
  ///   - 改用 main_shell root Stack 内的全屏 Listener,
  ///     Listener 跟 _CenterFab 同 widget tree(不在 Overlay 内),
  ///     100% 接收 pointer events
  bool _speedDialOpen = false;
  int? _hoveredIndex;

  /// 上一次 build 的 tab index —— 用于计算 slide 方向。
  /// 初始 0(首页);从 modal 进/出不算 tab slide。
  int _prevTab = 0;

  /// 上一次 build 是不是 modal 路由(/add 等)
  bool _wasOnModal = false;

  /// 上一次 sync 过的 route tab —— 防 context.go 与 route 同步之间循环
  int _lastRouteTab = -1;

  /// 累计水平 swipe 距离(commit 47 加)。GestureDetector 不直接提供
  /// "总拖动距离",需在 onHorizontalDragUpdate 累加 dx
  double _swipeDx = 0;

  /// 2026-10-13 P6 第 11 次改:删除 Overlay 方式,改 main_shell Stack 内全屏 Listener
  ///   - 之前 _speedDialOverlay: OverlayEntry(2026-10-13 P6 第 5 次改的版本)
  ///   - 现在改用 `_speedDialOpen: bool` + `_hoveredIndex: int?` 在 main_shell
  ///     root Stack 内放全屏 Listener + SpeedDialListPopup UI
  ///   - 长按 _CenterFab → 触发 _openSpeedDial() → setState(_speedDialOpen = true)
  ///   - 全屏 Listener 立即接管后续 pointer move / up,跟 _CenterFab 同 widget tree
  ///   - 100% 接收 pointer events,跟 _CenterFab 的 gesture arena 无冲突
  // (原 _speedDialOverlay 字段已删除)

  /// Speed Dial 5 小圆配置(5 个非现金流的 type)
  /// 顺序:投资 / 福利 / 债权 / 不动产 / 其它(跟 asset_form 顺序一致)
  /// 配色跟 asset_type 配色一致(gold/success/warning/info/gray600)
  static const _speedDialItems = <SpeedDialItem>[
    SpeedDialItem(
      key: 'investment',
      label: '投资',
      icon: Icons.trending_up_rounded,
      color: AppBrand.gold,
    ),
    SpeedDialItem(
      key: 'benefit',
      label: '福利',
      icon: Icons.favorite_rounded,
      color: AppStatus.success,
    ),
    SpeedDialItem(
      key: 'receivable',
      label: '债权',
      icon: Icons.handshake_rounded,
      color: AppStatus.warning,
    ),
    SpeedDialItem(
      key: 'fixed_asset',
      label: '不动产',
      icon: Icons.home_rounded,
      color: AppStatus.info,
    ),
    SpeedDialItem(
      key: 'other',
      label: '其它',
      icon: Icons.category_rounded,
      color: AppGray.g600,
    ),
  ];

  void _openSpeedDial() {
    if (_speedDialOpen) return; // 防重入
    setState(() {
      _speedDialOpen = true;
    });
  }

  void _closeSpeedDial() {
    setState(() {
      _speedDialOpen = false;
      _hoveredIndex = null;
    });
  }

  /// 2026-10-13 P6 第 12 次改:SpeedDialListPopup 内 Listener 算 rowIndex
  ///   通过此 callback 传出,main_shell 只负责更新 _hoveredIndex 状态
  void _onSpeedDialHoveredIndexChanged(int? i) {
    if (i == _hoveredIndex) return;
    setState(() {
      _hoveredIndex = i;
    });
    if (i != null) AppHaptics.select();
  }

  /// 跳 /add 路由,带 preselectedAssetType extra
  ///   - assetType='cash_flow'(短按默认)→ form 选 cash_flow 第一个账户
  ///   - assetType='investment'(长按选)→ form 选 investment 第一个账户
  void _pushAdd({required String assetType}) {
    final shellNav = shellNavigatorKey.currentState;
    if (shellNav != null && shellNav.canPop()) {
      shellNav.popUntil((route) => route.isFirst);
    }
    context.push('/add', extra: assetType);
  }

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

  /// 处理 tab 切换(NavigationBar onDestinationSelected / 水平 swipe 入口)
  void switchToTab(int tab) {
    if (tab < 0 || tab > 3 || tab == _currentTab) return;

    // 切 tab 时收掉挂着的 modal(2026-10-11 UAT bug)
    final shellNav = shellNavigatorKey.currentState;
    if (shellNav != null && shellNav.canPop()) {
      shellNav.popUntil((route) => route.isFirst);
    }
    // 触觉:commit 46 撤掉 — 切 tab 不再 selectionClick,避免打扰
    // (之前用 select 的初衷是 ColorOS O-Haptic 咔哒,但 user 反馈
    // "切换时的震动不需要",停掉)
    _lastRouteTab = tab;
    setState(() => _currentTab = tab);
    context.go(_routeFor(tab));
  }

  /// 处理 NavigationBar onDestinationSelected 入口。dest 是 5 个 destination
  /// 的索引(0/1/2/3/4),中央 + 是 dest 2 → push /add 路由,不走 tab 切换
  ///
  /// 2026-10-13 P6:dest 2 短按 = 默认 cash_flow(走 _pushAdd)
  /// 长按由 _CenterFab 内部 GestureDetector → _openSpeedDial 处理
  void _handleDestSelected(int dest) {
    if (dest == 2) {
      AppHaptics.tap();
      _pushAdd(assetType: 'cash_flow');
      return;
    }
    switchToTab(dest < 2 ? dest : dest - 1);
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

    // ── 方向感知 slide ── (commit 44,参考 aecec3f 那版):
    // 只在 tab 之间切换算方向(+1 / -1),modal 进/出不算 tab slide,
    // 因为 modal 自己带从底上推动画,叠加会抖。
    int dir = 0;
    final locForDir = GoRouterState.of(context).uri.path;
    final onModalNow =
        locForDir.startsWith('/add') || locForDir.startsWith('/edit');
    if (!_wasOnModal && !onModalNow) {
      dir = _currentTab > _prevTab ? 1 : (_currentTab < _prevTab ? -1 : 0);
    }
    _prevTab = _currentTab;
    _wasOnModal = onModalNow;

    // 2026-10-13 P6 第 11 次改:整个 Scaffold 包在 Stack 内,
    //   Stack 末尾放全屏 Listener + SpeedDialListPopup
    //   - Listener 覆盖整个屏幕,在 _CenterFab 之上(Stack 后写在上)
    //   - Listener 跟 _CenterFab 同一 widget tree,不被 Overlay 隔断
    //   - 100% 接收 pointer events,跟 _CenterFab gesture arena 无冲突
    return Stack(
      children: [
        Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: LedgerGridBackground()),
          // 2026-10-12 (commit 44+46+47+88) body 切 tab:
          //   - GestureDetector + LayoutBuilder 监听水平 swipe 触发 switchToTab
          //     (commit 47 加:commit 40 撤 PageView 时把 swipe 一起撤了,
          //     user 反馈"现在左右滑动手势不行")
          //   - commit 88 改:阈值从 OR(distance > 18% OR velocity > 280)
          //     改成 AND(distance > 18% AND velocity > 400)
          //     原因:user 反馈"chart 内的横向滑动跟切 tab 手势冲突"
          //     - BarChart 内部用 RenderObject 直接吃 pointer(不走
          //       GestureDetector arena),所以 chart 内的 horizontal pan
          //       不会被外层 GestureDetector 拒绝
          //     - 原 OR 阈值让 chart 内慢速或短距离 pan 也能误触切 tab
          //     - 改成 AND:chart 内单柱 pan(短距离慢速)不会触发,
          //       user 真要切 tab 需要快速 + 大距离 swipe(正常 swipe tab
          //       动作)
          //   - AnimatedSwitcher 480ms AppMotion.normal cross-fade
          //   - 再叠一层方向感知 SlideTransition,offset = -dir * 0.06(屏宽 6%)
          //   - 触觉:commit 46 撤掉切换震动,保留 FAB 主操作震动
          Positioned.fill(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final screenWidth = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // 累计水平拖动距离;GestureDetector 不提供"delta 求和",
                  // 自己 addPostFrameCallback 维护一份 dx 累加
                  onHorizontalDragStart: (_) {
                    _swipeDx = 0;
                  },
                  onHorizontalDragUpdate: (d) {
                    _swipeDx += d.delta.dx;
                  },
                  onHorizontalDragEnd: (d) {
                    final velocity = d.primaryVelocity ?? 0;
                    // commit 88 改 OR → AND:避免 chart 内 pan 误触发切 tab
                    final pastDistance = _swipeDx.abs() > screenWidth * 0.18;
                    final pastVelocity = velocity.abs() > 400;
                    if (pastDistance && pastVelocity) {
                      // drag 负方向(向左)→ 下一 tab;正方向(向右)→ 上一 tab
                      final dir = _swipeDx < 0 ? 1 : -1;
                      final target = (_currentTab + dir).clamp(0, 3);
                      switchToTab(target);
                    }
                    _swipeDx = 0;
                  },
                  // AnimatedSwitcher 包 child:tab 切换时左右 slide + fade
                  child: AnimatedSwitcher(
                    duration: AppMotion.normal,
                    reverseDuration: AppMotion.fast,
                    switchInCurve: AppMotion.aquaIn,
                    switchOutCurve: AppMotion.aquaOut,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: <Widget>[...previousChildren, ?currentChild],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      // SlideTransition 让新 page 从 ±0.06 横向位移滑入,
                      // 同时 FadeTransition 让两 page 透明度同步过渡。
                      final slide = Tween<Offset>(
                        begin: Offset(-dir * 0.06, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return SlideTransition(
                        position: slide,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey('tab-$_currentTab'),
                      child: _pages[_currentTab],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // 2026-10-12 (commit 43):底 nav 去掉自定义 pill
      //   - 之前 commit 40-41 试过 self-drawn ColorOS pill,无论宽 64 还是 56,
      //     pill 跟中央 FAB 在 slot 内视觉冲突(都是大色块),撤掉
      //   - 改回纯 NavigationBar + selectedIndex,选区只靠 "icon 改金 +
      //     label 改金" 标识,极简
      //   - 切 tab 时 NavigationBar 内部 fade 过渡足够丝滑
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          height: 72,
          selectedIndex: _destForTab(_currentTab),
          onDestinationSelected: _handleDestSelected,
          backgroundColor: Theme.of(context).colorScheme.surface,
          // 关掉自带的 tonal pill(就是 M3 那个"小药丸"背景);
          // 我们只靠 icon + label 颜色变化表示选区
          indicatorColor: Colors.transparent,
          // 2026-10-13 P6:destinations list 不能再 const(中央 + 接受 closure)
          //   - 其它 4 个 destination 仍保留 const NavigationDestination(...) 内部,
          //     但 list literal 整体需要去掉 const 才能混 _CenterFab(onLongPress: ...)
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, size: 24),
              selectedIcon: Icon(Icons.dashboard_rounded, size: 24),
              label: '首页',
              tooltip: '',
            ),
            const NavigationDestination(
              icon: Icon(Icons.list_alt_outlined, size: 24),
              selectedIcon: Icon(Icons.list_alt_rounded, size: 24),
              label: '流水',
              tooltip: '',
            ),
            // 中央"+":大圆角色块
            // 2026-10-13 P6:长按 0.4s 弹 Speed Dial(5 小圆选 type),短按走默认 cash_flow
            //   - onTap:NavigationBar → onDestinationSelected → _handleDestSelected → _pushAdd
            //   - onLongPress:_CenterFab 内部 GestureDetector → _openSpeedDial
            NavigationDestination(
              icon: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s1),
                child: _CenterFab(onLongPress: _openSpeedDial),
              ),
              label: '',
              tooltip: '',
            ),
            const NavigationDestination(
              icon: Icon(Icons.pie_chart_outline, size: 24),
              selectedIcon: Icon(Icons.pie_chart_rounded, size: 24),
              label: '报表',
              tooltip: '',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline, size: 24),
              selectedIcon: Icon(Icons.person_rounded, size: 24),
              label: '我的',
              tooltip: '',
            ),
          ],
        ),
        ),
        ),
        // 2026-10-13 P6 第 12 次改:Listener 在 SpeedDialListPopup 内
        //   (用 main_shell 跟 popup 同一个 Stack 内的 size 算 rowIndex,避免 size 不一致)
        //   - main_shell 只管 _speedDialOpen(开/关) + _hoveredIndex(高亮)
        //   - SpeedDialListPopup 自己用全屏 Listener 接管 pointer events,
        //     跟 _CenterFab 同 widget tree,100% 接收 events
        if (_speedDialOpen)
          SpeedDialListPopup(
            items: _speedDialItems,
            hoveredIndex: _hoveredIndex,
            onHoveredIndexChanged: _onSpeedDialHoveredIndexChanged,
            onSelected: (item) {
              _closeSpeedDial();
              _pushAdd(assetType: item.key);
            },
            onDismiss: _closeSpeedDial,
          ),
      ],
    );
  }
}


/// 中央"+":大圆角色块,呼应 LOGO
/// - BoxShape.circle 保证真正圆(56x56 下 borderRadius=24 是圆角矩形不是圆)
/// - dark mode 下 ink 块 → cream,和 LOGO onDark 模式一致(避免和 Ink surface 融掉)
/// - 2026-10-13 P6:加 onLongPress 弹 Speed Dial,onTap 由父 NavigationBar 转发
///   不在 _CenterFab 内处理(避免双重响应)
class _CenterFab extends StatelessWidget {
  const _CenterFab({required this.onLongPress});
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      // onTap 留空:让父 NavigationBar 转发 tap → onDestinationSelected → _handleDestSelected
      // 只在 _CenterFab 内部处理 longPress,避免双重响应
      onLongPress: () {
        AppHaptics.tap();
        onLongPress();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
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
      ),
    );
  }
}
