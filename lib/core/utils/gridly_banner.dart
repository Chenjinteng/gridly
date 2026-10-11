// lib/core/utils/gridly_banner.dart
// gridly 自定义顶部 banner —— 替代 ScaffoldMessenger 的默认 SnackBar。
//
// 之前 SnackBar 在底部 + Material 3 黑底白字,跟 gridly UI 不搭;
// 这里改成:
//   - 位置:屏幕顶部(在 AppBar 下面、状态栏下面)
//   - 卡片样式:ink/cream 背景 + 左侧色条(brand teal / gold / 状态色)
//   - 圆角:AppRadius.brLg,跟 gridly 卡片视觉对齐
//   - 自动消失:1.5s(可配)
//   - 入场:从顶部滑下;退场:滑回顶部
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

enum GridlyBannerKind { info, success, warning, error }

/// 弹出 gridly 顶部 banner
///
/// [message]: 必填,显示文字(单行省略号)
/// [kind]: 决定左侧色条 + icon;默认 info
/// [duration]: 自动消失时间;默认 1.5s
Future<void> showGridlyBanner(
  BuildContext context,
  String message, {
  GridlyBannerKind kind = GridlyBannerKind.info,
  Duration duration = const Duration(milliseconds: 1500),
}) async {
  final overlayState = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GridlyBannerOverlay(
      message: message,
      kind: kind,
      duration: duration,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
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
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  ({Color accent, Color bg, Color fg, IconData icon, Color border}) _resolve(
      ThemeData theme) {
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
    return (
      accent: kindColor,
      // 2026-10-11 UAT 第四轮:30% alpha 在浅色 bg(尤其 cream)上
      // 仍能看到 AppBar "X" / "记一笔" 标题从 banner 后面透出来。
      // 提到 85% 让 banner 接近纯色块,完全盖住后面的内容。
      // bg 接近 kindColor 原色,fg 同步加深到 0.60 让文本在饱和底上
      // 仍有足够对比度。
      bg: kindColor.withValues(alpha: 0.85),
      fg: Color.lerp(kindColor, Colors.black, 0.60)!,
      border: kindColor.withValues(alpha: 0.55),
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
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.bg,
                    borderRadius: AppRadius.brLg,
                    border: Border.all(
                      color: scheme.border,
                      width: 0.5,
                    ),
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 左侧色条(kind accent)
                        Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: scheme.accent,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(AppRadius.lg),
                              bottomLeft: Radius.circular(AppRadius.lg),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s3,
                              vertical: AppSpacing.s3,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  scheme.icon,
                                  size: 18,
                                  color: scheme.accent,
                                ),
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
                      ],
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
    _ctrl.dispose();
    super.dispose();
  }
}