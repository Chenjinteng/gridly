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

  ({Color accent, Color bg, Color fg, IconData icon}) _resolve(ThemeData theme) {
    switch (widget.kind) {
      case GridlyBannerKind.info:
        return (
          accent: AppBrand.teal,
          bg: AppBrand.ink,
          fg: AppSecondary.cream,
          icon: Icons.info_outline_rounded,
        );
      case GridlyBannerKind.success:
        return (
          accent: AppBrand.teal,
          bg: AppBrand.ink,
          fg: AppSecondary.cream,
          icon: Icons.check_circle_outline_rounded,
        );
      case GridlyBannerKind.warning:
        return (
          accent: AppBrand.gold,
          bg: AppBrand.ink,
          fg: AppSecondary.cream,
          icon: Icons.warning_amber_rounded,
        );
      case GridlyBannerKind.error:
        return (
          accent: AppStatus.error,
          bg: AppBrand.ink,
          fg: AppSecondary.cream,
          icon: Icons.error_outline_rounded,
        );
    }
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
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