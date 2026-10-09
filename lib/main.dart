// lib/main.dart
// 入口 —— 启动时 seed 默认分类
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // 首次启动(或表空时)seed 默认分类
  await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LedgerlyApp(),
    ),
  );
}
