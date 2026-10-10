// lib/features/settings/ui/settings_page.dart
// 设置:主题切换 / 预算 / 数据导出 / 分类管理 / 关于
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: unused_import
import 'package:go_router/go_router.dart';

import '../../../core/settings/amount_visibility_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/gridly_mark.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/budget_provider.dart';
import '../../../core/utils/formatters.dart';
import 'widgets/budget_sheet.dart';
import 'widgets/csv_export_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final amountVisible = ref.watch(amountVisibilityProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
        children: [
          // 关于卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: AppBrand.ink,
                borderRadius: AppRadius.brLg,
              ),
              child: Row(
                children: [
Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: AppRadius.brMd,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: GridlyMark(onDark: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '格子记账',
                          style: TextStyle(
                            color: AppSecondary.cream,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '一格一账 · v0.1.0+1',
                          style: TextStyle(
                            color: AppGray.g400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 外观
          _SectionHeader(title: '外观'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s2,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.brLg,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.0, // 全卡片统一:0.5 → 1.0
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '主题',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  // 主题选择 —— 改用 RadioGroup + RadioListTile 整行排列,
                  // 每行全宽,不再被 SegmentedButton 内部 padding 卡住而换行
                  // (Flutter 3.32+ RadioListTile 单独用 onChanged/groupValue 被 deprecated)
                  RadioGroup<ThemeMode>(
                    groupValue: mode,
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(themeModeProvider.notifier).set(v);
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.system,
                          title: Text('跟随系统'),
                          secondary: Icon(
                            Icons.brightness_auto_outlined,
                            size: 18,
                          ),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.light,
                          title: Text('浅色'),
                          secondary: Icon(
                            Icons.light_mode_outlined,
                            size: 18,
                          ),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          title: Text('深色'),
                          secondary: Icon(
                            Icons.dark_mode_outlined,
                            size: 18,
                          ),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 隐私
          _SectionHeader(title: '隐私'),
          ListTile(
            leading: Icon(
              amountVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
            title: const Text('显示金额', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              amountVisible
                  ? '首页 / 流水 / 预算的金额正常显示'
                  : '全部金额以 •••••• 遮挡,防偷窥',
              style: const TextStyle(fontSize: 11, color: AppGray.g600),
            ),
            trailing: Switch(
              value: amountVisible,
              onChanged: (v) =>
                  ref.read(amountVisibilityProvider.notifier).set(v),
            ),
            dense: true,
          ),

          // 预算
          _SectionHeader(title: '预算'),
          _BudgetTile(),

          // 数据
          _SectionHeader(title: '数据'),
          _ActionTile(
            icon: Icons.upload_outlined,
            title: '导出 CSV',
            subtitle: '按时间范围导出流水',
            onTap: () => _openExportSheet(context),
          ),
          _ActionTile(
            icon: Icons.category_outlined,
            title: '分类管理',
            subtitle: '增删改查自定义分类',
            onTap: () => context.push('/settings/categories'),
          ),

          // 关于
          _SectionHeader(title: '关于'),
          _InfoTile(
            icon: Icons.tag,
            title: '版本',
            trailing: const Text('0.1.0+1'),
          ),
          _InfoTile(
            icon: Icons.code_rounded,
            title: '技术栈',
            trailing: const Text(
              'Flutter 3.47',
              style: TextStyle(color: AppGray.g600),
            ),
          ),
          _InfoTile(
            icon: Icons.storage_outlined,
            title: '数据存储',
            trailing: const Text(
              '本地 SQLite',
              style: TextStyle(color: AppGray.g600),
            ),
          ),
          _ActionTile(
            icon: Icons.info_outline,
            title: '关于格子记账',
            subtitle: '品牌 + 隐私政策 + 清空数据',
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    );
  }

  void _openExportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const CsvExportSheet(),
    );
  }
}

class _BudgetTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(monthlyBudgetProvider);
    return ListTile(
      leading: const Icon(Icons.savings_outlined, size: 20),
      title: const Text('月度预算', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        budget > 0 ? '当前 ¥${Formatters.amount(budget)}' : '未设置',
        style: const TextStyle(fontSize: 11, color: AppGray.g600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppGray.g400),
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          builder: (_) => const BudgetSheet(),
        );
      },
      dense: true,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s1,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppGray.g600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppGray.g400),
      onTap: onTap,
      dense: true,
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.trailing,
  });
  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: trailing,
      dense: true,
    );
  }
}
