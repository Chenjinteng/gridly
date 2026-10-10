// lib/core/settings/amount_visibility_provider.dart
// 金额可见性设置 —— 防偷窥/截图分享
// true = 显示金额(默认),false = 全部金额用 •••••• 遮挡
// 启动时异步从 SharedPreferences 加载,首次默认 true
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAmountVisibleKey = 'amount_visible';

class AmountVisibilityNotifier extends StateNotifier<bool> {
  AmountVisibilityNotifier() : super(true) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    // 缺失 key 时 getBool 返回 false,需要 nullable 处理
    final raw = prefs.getBool(_kAmountVisibleKey);
    if (raw == null) return; // 首次启动,沿用默认 true
    if (raw != state) {
      state = raw;
    }
  }

  Future<void> set(bool visible) async {
    if (visible == state) return;
    state = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAmountVisibleKey, visible);
  }

  Future<void> toggle() => set(!state);
}

final amountVisibilityProvider =
    StateNotifierProvider<AmountVisibilityNotifier, bool>((ref) {
  return AmountVisibilityNotifier();
});