// lib/app.dart
// MaterialApp + 主题 + 路由
//
// D71.4:3 个主题 × 2 个色调 = 4 种 ThemeData 组合
//   - themeMode: system / light / dark(白 / 夜晚 / 跟随系统)
//   - palette: defaultBrand / pink(默认品牌色 / 粉色)
//   - 4 组合:
//     · 白天 + 默认 → AppTheme.light() — 原版(白底/金强调)
//     · 白天 + 粉色 → AppTheme.pinkLight() — 粉色主题(粉底/亮粉强调)
//     · 夜晚 + 默认 → AppTheme.dark() — 原 dark(黑底/金强调)
//     · 夜晚 + 粉色 → AppTheme.dark() + GridlyPalette.darkPink — 黑底 + 粉强调
//       (卡片底色仍是黑,只有阴影/tab 选中/nav bar 选中换成粉色)
//   - themeMode=system:Flutter 自动切 light / dark
//     · 默认 palette:切 AppTheme.light() ↔ AppTheme.dark()
//     · 粉色 palette:切 AppTheme.pinkLight() ↔ AppTheme.dark(GridlyPalette.darkPink)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/gridly_palette.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/theme/theme_palette_provider.dart';

class LedgerlyApp extends ConsumerWidget {
  const LedgerlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final palette = ref.watch(themePaletteProvider);
    final usePink = palette == ThemePalette.pink;
    // D71.5:4 组合的 ThemeData 装配
    //   - 浅色时:用 pinkLight() / light()(整体 surface 跟随 palette)
    //   - 深色时:
    //     · 默认 palette → dark() 原版(cream/底黑字)
    //     · 粉色 palette → darkWithPalette(darkPink) 把 inverseSurface
    //       (button 底色) 也换成亮粉,不是 cream
    final lightTheme = usePink ? AppTheme.pinkLight() : AppTheme.light();
    final darkTheme = usePink
        ? AppTheme.darkWithPalette(GridlyPalette.darkPink)
        : AppTheme.dark();
    return MaterialApp.router(
      title: '格子记账',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

/// D71.4 旧版(已删):直接在 app.dart 复制 _applyPaletteGridly 的逻辑太碎,
///   D71.5 把"夜晚+粉色"做成独立工厂 `AppTheme.darkWithPalette()`,
///   app.dart 只负责选哪个工厂,不再手写 extension