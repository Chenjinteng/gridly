// lib/core/database/providers.dart
// Riverpod Provider:Database / Repository 注入
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'repositories/asset_repository.dart';
import 'repositories/transaction_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/category_budget_repository.dart';

/// Database 单例 Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// TransactionRepository Provider
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(ref.watch(databaseProvider));
});

/// CategoryRepository Provider
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(databaseProvider));
});

/// CategoryBudgetRepository Provider(commit 90 加)
final categoryBudgetRepositoryProvider = Provider<CategoryBudgetRepository>((
  ref,
) {
  return CategoryBudgetRepository(ref.watch(databaseProvider));
});

/// AssetRepository Provider(commit 110 加)
final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository(ref.watch(databaseProvider));
});
