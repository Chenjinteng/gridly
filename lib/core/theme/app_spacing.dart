// lib/core/theme/app_spacing.dart
// 间距规范(8 倍数 + micro 2px)来源:design/THEME.md §5.2
class AppSpacing {
  AppSpacing._();

  /// 2026-10-16 D64.87 加:micro 间距 2px(icon+text 紧贴 / 副标 gap / handle 等)
  ///   - 容器级仍用 s1-s10(8 倍数);micro 例外 2px(原 8+ 处硬编)
  ///   - 跟 s1(4px) 区分,4px 是 8 倍数(0.5x base),2px 是 0.25x(更细)
  static const double s05 = 2;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s8 = 48;
  static const double s10 = 64;
}
