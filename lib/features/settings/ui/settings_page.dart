// lib/features/settings/ui/settings_page.dart
// 我的 / 设置(P0 空壳) —— P1 实装:主题切换 / 数据导入导出 / 关于
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('P0 · 空壳', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s2),
            Text('我的(Settings)', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.s3),
            const Text('P1 实装:主题切换 + 数据导入导出 + 关于页(LOGO + 文字版)'),
          ],
        ),
      ),
    );
  }
}
