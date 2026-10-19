// lib/core/theme/theme_palette_provider.dart
// 主题色调(品牌色)Provider —— D71.1 加 · 2026-10-19
//   跟 theme_mode_provider 平行:
//     - theme_mode 决定 浅色/深色 (系统/light/dark)
//     - theme_palette 决定 默认品牌色 / 粉色
//   两个维度正交叠加,组合出 4 种主题(浅+默认/浅+粉/深+默认/深+粉)
//
//   app.dart 根据 (mode, palette) 选 ThemeData
//
//   持久化:SharedPreferences key 'theme_palette',值 'default' / 'pink',默认 'default'
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePaletteKey = 'theme_palette';

/// 主题色调选项
enum ThemePalette {
  /// 默认品牌色(炭黑/金黄/明亮青)
  defaultBrand,

  /// 粉色(深紫红/亮粉/柔粉)
  pink,
}

String _paletteToKey(ThemePalette p) {
  return switch (p) {
    ThemePalette.defaultBrand => 'default',
    ThemePalette.pink => 'pink',
  };
}

ThemePalette _keyToPalette(String? key) {
  return switch (key) {
    'pink' => ThemePalette.pink,
    _ => ThemePalette.defaultBrand,
  };
}

class ThemePaletteNotifier extends StateNotifier<ThemePalette> {
  ThemePaletteNotifier() : super(ThemePalette.defaultBrand) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemePaletteKey);
    final loaded = _keyToPalette(raw);
    if (loaded != state) {
      state = loaded;
    }
  }

  Future<void> set(ThemePalette palette) async {
    if (palette == state) return;
    state = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePaletteKey, _paletteToKey(palette));
  }
}

final themePaletteProvider =
    StateNotifierProvider<ThemePaletteNotifier, ThemePalette>((ref) {
  return ThemePaletteNotifier();
});
