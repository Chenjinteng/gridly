// lib/features/ledger/ui/ledger_page.dart
// 流水(P0 空壳) —— P1 实装:按日分组 ListView
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('流水')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('P0 · 空壳', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s2),
            Text('流水(Ledger)', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.s3),
            const Text('P1 实装:按日分组,每条流水卡片用 r-lg 圆角'),
          ],
        ),
      ),
    );
  }
}
