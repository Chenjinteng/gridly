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
  // 把老用户的系统分类 icon 升级到 v2 语义化图标(幂等,无命中也无害)
  await container.read(categoryRepositoryProvider).syncCategoryIcons();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LedgerlyApp(),
    ),
  );
}
