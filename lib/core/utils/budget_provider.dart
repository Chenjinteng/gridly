// lib/core/utils/budget_provider.dart
// 月度预算 Provider(SharedPreferences 持久化)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBudgetKey = 'monthly_budget';

class MonthlyBudgetNotifier extends StateNotifier<double> {
  MonthlyBudgetNotifier() : super(0) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_kBudgetKey) ?? 0;
    if (value != state) state = value;
  }

  Future<void> set(double value) async {
    if (value == state) return;
    state = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBudgetKey, state);
  }
}

final monthlyBudgetProvider =
    StateNotifierProvider<MonthlyBudgetNotifier, double>((ref) {
  return MonthlyBudgetNotifier();
});
