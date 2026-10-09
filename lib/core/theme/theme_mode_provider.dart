// lib/core/theme/theme_mode_provider.dart
// 主题模式 Provider(跟随系统 / 浅色 / 深色)+ 持久化
// 首次启动:默认 system,异步从 SharedPreferences 加载真实值
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';

/// ThemeMode 字符串 <-> enum 转换
String _themeModeToKey(ThemeMode m) {
  return switch (m) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };
}

ThemeMode _keyToThemeMode(String? key) {
  return switch (key) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    // 异步加载持久化值,避免启动阻塞
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeModeKey);
    final loaded = _keyToThemeMode(raw);
    if (loaded != state) {
      state = loaded;
    }
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, _themeModeToKey(mode));
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
