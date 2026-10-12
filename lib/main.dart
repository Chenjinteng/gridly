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
  // 把老用户的系统分类 color 同步到当前代码值(默认分类颜色在 default_categories.dart 集中定义)
  await container.read(categoryRepositoryProvider).syncCategoryColors();
  // 2026-10-12 commit 110 加:首次启动 seed 3 个默认资产(现金/银行卡/微信支付)
  //   P1 阶段:资产表 NOT NULL 流水必须挂靠账户,App 启动兜底 seed,
  //   schemaVersion 3 升级路径上 onUpgrade 也 batch insert 了(老设备升级双保险)。
  await container.read(assetRepositoryProvider).seedDefaultsIfEmpty();
  runApp(
    UncontrolledProviderScope(container: container, child: const LedgerlyApp()),
  );
}
