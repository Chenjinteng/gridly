// lib/core/settings/app_info_provider.dart
// App 版本信息 —— 从 pubspec.yaml + 平台 build number 读取
// 用法:
//   final info = ref.watch(packageInfoProvider).valueOrNull;
//   final label = info == null ? '...' : 'v${info.version}+${info.buildNumber}';
//
// 加载很快(< 100ms),短暂占位不影响 UX
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});