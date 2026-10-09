// lib/features/settings/ui/settings_page.dart
// 设置:主题切换 / 数据导出 / 分类管理 / 关于
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_provider.dart';
import 'widgets/csv_export_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
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
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: AppBrand.gold,
                      size: 32,
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
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '主题',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          label: Text('跟随系统'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('深色'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) {
                        ref.read(themeModeProvider.notifier).set(s.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

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
