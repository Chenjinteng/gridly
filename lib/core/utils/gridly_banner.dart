// lib/core/utils/gridly_banner.dart
// gridly 自定义顶部 banner —— 替代 ScaffoldMessenger 的默认 SnackBar。
//
// 之前 SnackBar 在底部 + Material 3 黑底白字,跟 gridly UI 不搭;
// 这里改成:
//   - 位置:屏幕顶部(在 AppBar 下面、状态栏下面)
//   - 卡片样式:ink/cream 背景 + 左侧色条(brand teal / gold / 状态色)
//   - 圆角:AppRadius.brLg,跟 gridly 卡片视觉对齐
//   - 自动消失:1.5s(可配)
//   - 入场:从顶部滑下,AppMotion.fast 240ms + aquaIn
//   - 持续:widget.duration(默认 1500ms)
//   - 出场:从顶部收回,AppMotion.fast 240ms + aquaOut(2026-10-12 加)
//
// 2026-10-12 ColorOS Aquamorphic 改造:
//   - 入场曲线:easeOutCubic → AppMotion.aquaIn(Cubic(0.16, 1, 0.3, 1),
//     非线性阻尼,前快后慢)
//   - 出场曲线:用 aquaOut(对称反向),不沿用入场的镜像(曲线不对称,镜像视觉不对)
//   - 实现:用 TweenSequence 串联"入场 + 持续 + 出场"三段,一个 controller
//     自动播完全程,不需要外部 Future.delayed 触发 reverse
import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../haptics/app_haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

enum GridlyBannerKind { info, success, warning, error }

/// 弹出 gridly 顶部 banner
///
/// [message]: 必填,显示文字(单行省略号)
/// [kind]: 决定左侧色条 + icon;默认 info
/// [duration]: 自动消失时间;默认 1.5s。**最小 100ms**,传 0 会被当作 100ms
///   避免 TweenSequence weight=0 报错。
Future<void> showGridlyBanner(
  BuildContext context,
  String message, {
  GridlyBannerKind kind = GridlyBannerKind.info,
  Duration duration = const Duration(milliseconds: 1500),
}) async {
  // 兜底:duration 太短会被 TweenSequence 当 0 weight 报 RangeError,
  // 实际使用方不会传 0,但写在这里保险
  final safeDuration = duration < const Duration(milliseconds: 100)
      ? const Duration(milliseconds: 100)
      : duration;

  final overlayState = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GridlyBannerOverlay(
      message: message,
      kind: kind,
      duration: safeDuration,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  // 2026-10-12 ColorOS Tactile Haptics:按 banner kind 自动给触觉反馈。
  // banner 是"信息反馈",kind 决定了触觉强度:
  //   info     → tap(轻"嗯"一下,提示用户)
  //   success  → success(中量振,操作完成的肯定)
  //   warning  → warning(重量振,需要引起注意)
  //   error    → warning(重量振,失败)
  // 调用方不再需要单独 trigger,banner 自带。
  switch (kind) {
    case GridlyBannerKind.info:
      AppHaptics.tap();
    case GridlyBannerKind.success:
      AppHaptics.success();
    case GridlyBannerKind.warning:
    case GridlyBannerKind.error:
      AppHaptics.warning();
  }
  overlayState.insert(entry);
}

class _GridlyBannerOverlay extends StatefulWidget {
  const _GridlyBannerOverlay({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final GridlyBannerKind kind;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_GridlyBannerOverlay> createState() => _GridlyBannerOverlayState();
}

class _GridlyBannerOverlayState extends State<_GridlyBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    // 总时长 = 入场(240ms) + 持续(widget.duration) + 出场(240ms)
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.fast + widget.duration + AppMotion.fast,
    );
    final entryMs = AppMotion.fast.inMilliseconds.toDouble();
    final holdMs = widget.duration.inMilliseconds.toDouble();
    final exitMs = AppMotion.fast.inMilliseconds.toDouble();

    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: AppMotion.aquaIn)),
        weight: entryMs,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: holdMs),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: AppMotion.aquaOut)),
        weight: exitMs,
      ),
    ]).animate(_ctrl);

    _slide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).chain(CurveTween(curve: AppMotion.aquaIn)),
        weight: entryMs,
      ),
      TweenSequenceItem(
        tween: ConstantTween<Offset>(Offset.zero),
        weight: holdMs,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0, -1),
        ).chain(CurveTween(curve: AppMotion.aquaOut)),
        weight: exitMs,
      ),
    ]).animate(_ctrl);

    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onDismiss();
    }
  }

  ({Color accent, Color bg, Color fg, IconData icon, Color border}) _resolve(
    ThemeData theme,
  ) {
    // 2026-10-11 UAT 反馈:之前 banner 用 AppBrand.ink 纯黑 + cream 米白,
    // 跟 gridly 主题脱节。改成主题色:
    //   bg     → surfaceContainerHigh(轻微抬升,跟卡片视觉一致)
    //   fg     → onSurface(主题正文色)
    //   border → outlineVariant(细描边,跟卡片边缘一致)
    // accent / icon 保留 kind 颜色(teal / gold / red),作为视觉焦点。
    final kindColor = switch (widget.kind) {
      GridlyBannerKind.info => AppBrand.teal,
      GridlyBannerKind.success => AppBrand.teal,
      GridlyBannerKind.warning => AppBrand.gold,
      GridlyBannerKind.error => AppStatus.error,
    };
    final iconData = switch (widget.kind) {
      GridlyBannerKind.info => Icons.info_outline_rounded,
      GridlyBannerKind.success => Icons.check_circle_outline_rounded,
      GridlyBannerKind.warning => Icons.warning_amber_rounded,
      GridlyBannerKind.error => Icons.error_outline_rounded,
    };
    // fg / accent:按 kind 选"对比色"
    // 浅色 bg(只 gold) → 深字;深色 bg(teal/red) → 白字
    final fg = switch (widget.kind) {
      GridlyBannerKind.warning => const Color(0xFF1A1A1A),
      _ => Colors.white,
    };
    return (
      accent: fg, // 跟 fg 同色,strip / icon 一致
      bg: kindColor, // 100% 纯色,无 alpha
      fg: fg,
      // border 用 kindColor lerp(black, 0.20),纯色块边上一圈
      // 略深边线让 banner 有边界,而不是浮在上面的纯色块
      border: Color.lerp(kindColor, Colors.black, 0.20)!,
      icon: iconData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = _resolve(theme);
    // 状态栏 / safe area 顶部:把 banner 推到 AppBar 下面
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: topInset + AppSpacing.s2),
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.bg,
                    borderRadius: AppRadius.brLg,
                    border: Border.all(color: scheme.border, width: 0.5),
                    boxShadow: [
                      // 2026-10-11 UAT:改成 theme 色后阴影也跟着用主题的 shadowColor,
                      // 不再硬编码 black.withValues(...)。light mode 阴影柔和,
                      // dark mode 阴影偏白,跟 gridly 卡片阴影策略一致。
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Icon(scheme.icon, size: 18, color: scheme.accent),
                          const SizedBox(width: AppSpacing.s2),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.fg,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }
}
