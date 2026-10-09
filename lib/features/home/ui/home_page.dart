// lib/features/home/ui/home_page.dart
// 首页(P0 空壳) —— P1 实装:本月汇总 + 最近流水
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('格子记账'),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('P0 · 空壳', style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.s2),
              Text(
                '首页(Home)',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.s3),
              const Text('P1 实装:本月收入 / 支出 / 结余三色块 + 最近 5 条流水'),
              const SizedBox(height: AppSpacing.s5),
              const _SemanticLegend(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 记账语义色 demo —— 把"金 = 收入 / 青 = 支出 / 炭黑 = 结余"展示出来
class _SemanticLegend extends StatelessWidget {
  const _SemanticLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s3,
      runSpacing: AppSpacing.s2,
      children: const [
        _Chip(color: AppBrand.gold, label: '收入 Gold #F5BC1F'),
        _Chip(color: AppBrand.teal, label: '支出 Teal #14B8A6'),
        _Chip(color: AppBrand.ink, label: '结余 Ink #0F1419'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
