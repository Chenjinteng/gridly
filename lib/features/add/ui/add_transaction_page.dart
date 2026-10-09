// lib/features/add/ui/add_transaction_page.dart
// 记一笔(P0 空壳) —— P1 实装:金额大字号 + 数字键盘 + 分类网格
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class AddTransactionPage extends StatelessWidget {
  const AddTransactionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('记一笔')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('P0 · 空壳', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s2),
            Text('记一笔(Add)', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.s3),
            const Text('P1 实装:金额大字号(Teal 入 / Gold 出) + 数字键盘 + 分类网格'),
          ],
        ),
      ),
    );
  }
}
