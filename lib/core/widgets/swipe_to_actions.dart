// lib/core/widgets/swipe_to_actions.dart
//
// 2026-10-16 D64.42 加:跨 tile 类型通用的"左滑露 [编辑][删除]"交互组件。
//   - 之前是 transaction_tile.dart 里的私有 `_SwipeToDelete`,只有流水用。
//   - 抽成 public `SwipeToActions`,业务侧 widget(资产 / 流水 / 未来分类等)
//     只要 wrap child + 传 tileId + onEdit + onDelete 就能复用同一套交互。
//   - 设计目标:跟流水 tile 完全一致,iOS Mail.app 风格:
//     * 左滑超过阈值 → snap 露出 [编辑][删除] 两个 64px 圆角矩形按钮(中间 4px gap)
//     * 编辑按钮 = primary 色,删除按钮 = error 红 —— iOS 标准 destructive 语义
//     * 按钮跟随 _offset 渐显(opacity + translate 双过渡)
//     * 点 tile 自身 → 关闭 + 触发 onEdit(asset 没详情页,onTap = onEdit 复用原行为)
//     * 点编辑/删除 → 触发对应回调,tile 状态不动
//     * 外部 tap / 别的 tile 滑开 → 通过 openSwipeIdProvider 全局协调自动收回
//     * 物理:spring(stiffness 380 / damping 38,临界)+ friction(0.135)
//       fling > 800 px/s 用 friction continuation,慢速直接 spring
//
// 共享 openSwipeIdProvider 协调全局 tile 展开互斥,
// 任何 widget 通过 ref.read(openSwipeIdProvider.notifier).state = null
// 都能收回所有开着的 tile(例如页面 body 加全局 GestureDetector)。
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/open_swipe_id_provider.dart';

/// 通用滑动操作 wrapper —— 把 child 包起来,左滑露 [编辑][删除] 按钮。
///
/// 用法:
/// ```dart
/// SwipeToActions(
///   tileId: asset.id,
///   onEdit: () => _showForm(context, asset),
///   onDelete: () => _confirmDelete(context, ref, asset),
///   child: Container(...),  // 实际 tile UI
/// )
/// ```
class SwipeToActions extends ConsumerStatefulWidget {
  const SwipeToActions({
    super.key,
    required this.tileId,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
  });

  /// tile 的唯一 id(用于注册到 openSwipeIdProvider,全局互斥展开)
  final int tileId;

  /// 实际显示的 tile widget
  final Widget child;

  /// 左按钮(编辑,primary 色)回调
  final VoidCallback onEdit;

  /// 右按钮(删除,error 红)回调
  final VoidCallback onDelete;

  /// tile 自身 tap 回调(默认 null,只触发关闭 + 不动作);
  /// asset tile 没有详情页,业务侧直接传 onEdit 复用原"点 tile = 编辑"行为
  final VoidCallback? onTap;

  @override
  ConsumerState<SwipeToActions> createState() => _SwipeToActionsState();
}

class _SwipeToActionsState extends ConsumerState<SwipeToActions>
    with SingleTickerProviderStateMixin {
  /// 划开的固定宽度(px)—— 露出 [编辑 64 + 4 gap + 删除 64 = 132 + 8 视觉 = 140]px 的按钮区域
  /// (中间留 4px surface 色 gap 让两个按钮视觉独立,不粘成一条)
  static const double _kOpenOffset = 140;

  /// snap 阈值:划到这个距离就锁住,否则弹回
  static const double _kSnapThreshold = 40;

  /// fling 速度阈值(向左 px/s),即使没划够阈值,快速左滑也直接 snap 打开
  static const double _kFlingVelocity = -500;

  /// 超过这个速度认为是"快速 fling"—— 用 friction continuation(模拟惯性)
  /// 然后 spring snap 到最近端点。比慢速 spring 更有"原生"感。
  static const double _kFastFlingThreshold = 800;

  /// 按钮"从右滑入"距离(opacity 0 时偏移 +12px,opacity 1 时偏移 0)
  static const double _kButtonSlideIn = 12;

  /// 按钮 Padding(跟 child tile margin 一致:横 s4 + 纵 s1,视觉对齐)
  static const double _kRowHorizontalInset = AppSpacing.s4; // 16
  static const double _kRowVerticalInset = AppSpacing.s1; // 4

  /// Spring 物理参数 —— 接近 iOS 9+ UIKit swipe action 弹性。
  /// critical damping = 2*sqrt(stiffness*mass) ≈ 39;damping=38 几乎临界,
  /// 几乎无过冲,响应快速,视觉"丝滑不拖泥带水"。
  static const SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 38.0,
  );

  /// Friction 系数 —— iOS 默认 ~0.135,模拟大阻力快速收敛。
  static const double _kDrag = 0.135;

  late final AnimationController _ctrl;
  double _offset = 0;

  /// fling continuation 中标志 —— 监听 fling 完成后切到 spring snap
  bool _isFlinging = false;

  @override
  void initState() {
    super.initState();
    // unbounded:_ctrl.value 直接是 position(spring/friction simulation 输出),
    // 不限定在 [0, 1]。_offset 在 _handleAnimTick 中 clamp 到 [-_kOpenOffset, 0]。
    _ctrl = AnimationController.unbounded(vsync: this, value: 0);
    _ctrl.addListener(_handleAnimTick);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleAnimTick);
    _ctrl.dispose();
    super.dispose();
  }

  /// 动画 tick —— 直接用 _ctrl.value 作为 offset(spring/friction simulation)
  /// fling continuation 完成后切到 spring snap
  void _handleAnimTick() {
    if (!mounted) return;
    final wasAnimating = _ctrl.isAnimating;
    final raw = _ctrl.value;
    final clamped = raw.clamp(-_kOpenOffset, 0.0);
    setState(() {
      _offset = clamped;
    });
    // fling 撞墙 / 衰减完成后,根据当前位置 spring snap 到最近端点
    if (_isFlinging && !wasAnimating) {
      _isFlinging = false;
      final target = _offset.abs() > _kOpenOffset / 2 ? -_kOpenOffset : 0.0;
      _springTo(target);
    }
  }

  /// 用 spring 把 _offset 平滑带到 target —— iOS 风格弹性收敛
  /// velocity 传 fling 末速度,让 spring "惯性" 自然
  void _springTo(double target, {double velocity = 0}) {
    if ((_offset - target).abs() < 0.5) return;
    _ctrl.stop();
    // SpringSimulation 签名: (spring, start, end, velocity)
    _ctrl.animateWith(SpringSimulation(_kSpring, _offset, target, velocity));
  }

  /// 用 friction 让 _offset 自然减速 —— 模拟 fling 释放后的惯性滑动
  /// 衰减到 0 后由 _handleAnimTick 切到 spring snap
  void _flingWith(double velocity) {
    _ctrl.stop();
    _isFlinging = true;
    _ctrl.animateWith(FrictionSimulation(_kDrag, _offset, velocity));
  }

  /// 用户开始拖动:立即停止正在进行的吸附动画,防止 drag 与 animation 并发修改 _offset
  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    _isFlinging = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final delta = d.primaryDelta!;
    // closed(_offset == 0)时右滑忽略(没什么可关闭);
    // 已开(_offset < 0)时右滑允许(用于关闭方向的手势,原生 iOS 标准)
    if (delta > 0 && _offset == 0) return;
    setState(() {
      _offset = (_offset + delta).clamp(-_kOpenOffset, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // 决定目标:
    //   - 划得够远 → open(不管速度,慢拖过阈值也应该锁开)
    //   - 快速左 fling → open(没划够也锁开)
    //   - 快速右 fling → close(强反向)
    //   - 其它 → close
    final shouldOpen =
        _offset.abs() > _kSnapThreshold || velocity < _kFlingVelocity;

    if (shouldOpen) {
      // 注册自己到 openSwipeIdProvider,
      // 让页面 body 全局 tap handler / 其他 tile 都能找到要关掉的 tile,
      // 实现"点屏幕任何地方 / 别的 tile 滑开,正在开的 tile 自动收回"。
      ref.read(openSwipeIdProvider.notifier).state = widget.tileId;
    }

    if (velocity.abs() > _kFastFlingThreshold) {
      // 快速 fling:friction continuation + 完成后 spring snap 到最近端点
      _flingWith(velocity);
    } else {
      // 慢速:直接 spring snap(传部分 velocity 模拟惯性)
      _springTo(shouldOpen ? -_kOpenOffset : 0.0, velocity: velocity * 0.5);
    }
  }

  void _close() {
    if (_offset != 0) _springTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 监听 openSwipeIdProvider。
    //   - 如果 provider 变成 null 或别人的 id(说明外面被点了),而且我自己正开着,
    //     就 spring 回 0 收回。
    ref.listen<int?>(openSwipeIdProvider, (prev, next) {
      if (next != widget.tileId && _offset < 0) {
        _springTo(0);
      }
    });
    // 按钮"显现进度":_offset.abs() / _kOpenOffset。tile 滑得越多,按钮越显现,
    // 用 opacity 0→1 + Transform.translate(+12px → 0)双重过渡让按钮
    // "从 tile 背后挤出来"的感觉,而不是突然显示。
    final reveal = (_offset.abs() / _kOpenOffset).clamp(0.0, 1.0);
    final slideInOffset = (1 - reveal) * _kButtonSlideIn;

    return Stack(
      children: [
        // 底层:操作按钮条 — [编辑 64px][4px gap][删除 64px],brLg 圆角矩形 + elevation 4
        // 2026-10-11 UAT 反馈:胶囊"丑且太大",退回圆角矩形,加 elevation 落影
        // 按钮跟随 _offset 渐显(opacity + translate),不再"突然出现"。
        // 左按钮(编辑)用主题色 primary,右按钮(删除)用 error 红 —— iOS 标准。
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kRowHorizontalInset,
              vertical: _kRowVerticalInset,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 左按钮(编辑)—— primary + elevation=4 + shadowColor=black38
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 64,
                        child: Material(
                          color: theme.colorScheme.primary,
                          borderRadius: AppRadius.brLg,
                          elevation: 4,
                          shadowColor: Colors.black38,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onEdit,
                            child: const Center(
                              child: Text(
                                '\ue3c9', // Material Icons Round "edit"
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialIconsRound',
                                  fontSize: 32,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(color: Colors.white, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 中间 4px surface 色 gap
                  const SizedBox(width: 4),
                  // 右按钮(删除)—— 同款 Round + 红色 destructive 语义
                  Transform.translate(
                    offset: Offset(slideInOffset, 0),
                    child: Opacity(
                      opacity: reveal,
                      child: SizedBox(
                        width: 64,
                        child: Material(
                          color: AppStatus.error,
                          borderRadius: AppRadius.brLg,
                          elevation: 4,
                          shadowColor: Colors.black38,
                          child: InkWell(
                            borderRadius: AppRadius.brLg,
                            onTap: widget.onDelete,
                            child: const Center(
                              child: Text(
                                '\ue872', // Material Icons Round "delete"
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MaterialIconsRound',
                                  fontSize: 32,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(color: Colors.white, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 上层:tile(随 _offset 水平平移)—— drag 1:1 跟随,松手才 snap
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: () {
              // tile 自身 onTap 时主动清 openSwipeIdProvider:
              //   - 点开着的 tile 自己 → provider 清成 null,ref.listen 触发
              //     二次 _springTo(0)(无害二次 snap)
              //   - 点另一个 closed tile → provider 清成 null,开着的 tile
              //     通过 ref.listen(next=null != myId && _offset<0)自己收回
              //   - 点编辑/删除按钮 → InkWell 消耗 tap,tile.onTap 不触发,
              //     provider 不动(预期:点按钮不动 tile 状态)
              ref.read(openSwipeIdProvider.notifier).state = null;
              _close();
              widget.onTap?.call();
            },
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
