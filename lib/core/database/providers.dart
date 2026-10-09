// lib/core/database/providers.dart
// Riverpod Provider:Database / Repository 注入
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';
import 'repositories/transaction_repository.dart';
import 'repositories/category_repository.dart';

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
