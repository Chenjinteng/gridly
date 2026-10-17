// lib/features/settings/ui/settings_page.dart
// 设置:主题切换 / 预算 / 数据导出 / 分类管理 / 关于
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/amount_visibility_provider.dart';
import '../../../core/settings/app_info_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/card_shadows.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/aqua_switch.dart';
import '../../../core/widgets/gridly_mark.dart';
import '../../../core/widgets/show_app_modal_sheet.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/budget_provider.dart';
import '../../../core/utils/formatters.dart';
import '../application/server_controller.dart';
import 'widgets/backup_restore_sheet.dart';
import 'widgets/csv_export_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final amountVisible = ref.watch(amountVisibilityProvider);
    final pkgInfo = ref.watch(packageInfoProvider).valueOrNull;
    // 版本号:加载中显示占位符;正常显示 'v0.1.0+1' / 完整时 'v0.1.0+1'
    final versionTagline = pkgInfo == null
        ? '一格一账 · ...'
        : '一格一账 · v${pkgInfo.version}+${pkgInfo.buildNumber}';
    final versionTrailing = pkgInfo == null
        ? '...'
        : '${pkgInfo.version}+${pkgInfo.buildNumber}';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                // rim light border + 阴影,与其他黑底卡(月度汇总/range summary)保持一致
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                  width: 1.0,
                ),
                boxShadow: CardShadows.dark(context),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '格子记账',
                          style: TextStyle(
                            color: AppSecondary.cream,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s05),
                        Text(
                          versionTagline,
                          style: const TextStyle(
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
                boxShadow: CardShadows.light(context),
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
                          secondary: Icon(Icons.light_mode_outlined, size: 18),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          title: Text('深色'),
                          secondary: Icon(Icons.dark_mode_outlined, size: 18),
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
              amountVisible ? '首页 / 流水 / 预算的金额正常显示' : '全部金额以 •••••• 遮挡,防偷窥',
              style: const TextStyle(fontSize: 11, color: AppGray.g600),
            ),
            trailing: AquaSwitch(
              value: amountVisible,
              onChanged: (v) =>
                  ref.read(amountVisibilityProvider.notifier).set(v),
            ),
            dense: true,
          ),

          // 资产(2026-10-12 P2 commit 加,放在"预算"和"数据"之间)
          _SectionHeader(title: '资产'),
          _AssetsTile(),

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
          // 2026-10-17 D68 加:数据库全量备份 / 还原
          _ActionTile(
            icon: Icons.cloud_sync_outlined,
            title: '备份还原',
            subtitle: '完整备份 / 还原本地数据库',
            onTap: () => _openBackupSheet(context),
          ),
          _ActionTile(
            icon: Icons.category_outlined,
            title: '分类管理',
            subtitle: '增删改查自定义分类',
            onTap: () => context.push('/settings/categories'),
          ),

          // 局域网(LAN_WEB v2.0.0 P1)
          _SectionHeader(title: '局域网'),
          _LanWebTile(),

          // 关于
          _SectionHeader(title: '关于'),
          _InfoTile(
            icon: Icons.tag,
            title: '版本',
            trailing: Text(versionTrailing),
          ),
          _ActionTile(
            icon: Icons.info_outline,
            title: '关于格子记账',
            subtitle: '简介 + 隐私政策 + 免责说明 + 清空数据',
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    );
  }

  void _openExportSheet(BuildContext context) {
    // D66:showAppModalBottomSheet 已封 useRootNavigator:false + PopScope,
    //   替 D64.20 这里手动 useRootNavigator:false(系统返回键仍退 app)。
    showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const CsvExportSheet(),
    );
  }

  // 2026-10-17 D68 加:数据库备份 / 还原 sheet(D66 showAppModalBottomSheet 顺手)
  void _openBackupSheet(BuildContext context) {
    showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const BackupRestoreSheet(),
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
        // commit 106 改:从 showModalBottomSheet 改 context.push 全屏路由
        //   解决 BudgetSheet 还有点掉帧问题(viewInsets 由 Scaffold 处理,
        //   无 showModalBottomSheet 弹窗过渡动画,见 budget_management_page.dart 注释)
        context.push('/settings/budget');
      },
      dense: true,
    );
  }
}

/// 2026-10-12 P2 commit 加:资产入口 tile(指向 /settings/assets 全屏路由)
class _AssetsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined, size: 20),
      title: const Text('资产', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        '账户管理 + 总资产 + 6 大类',
        style: TextStyle(fontSize: 11, color: AppGray.g600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppGray.g400),
      onTap: () => context.push('/settings/assets'),
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

/// LAN_WEB v2.0.0 P1:局域网服务开关 + 状态 + 访问 URL
///
/// UI 跟「隐私」section 的 ListTile+AquaSwitch 不同,自定义 card 因为:
/// - 状态 + 访问 URL 需要更明确展示
/// - 后续 P2 可能加配对码 / 二维码,放卡片更好扩
class _LanWebTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWebControllerProvider);
    final controller = ref.read(lanWebControllerProvider.notifier);
    final theme = Theme.of(context);
    return Padding(
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
            width: 1.0,
          ),
          boxShadow: CardShadows.light(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_tethering_outlined, size: 20),
                const SizedBox(width: AppSpacing.s3),
                const Expanded(
                  child: Text(
                    '局域网 Web 服务',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                AquaSwitch(
                  value: state.enabled,
                  onChanged: (v) => controller.setEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              _statusText(state),
              style: const TextStyle(fontSize: 11, color: AppGray.g600),
            ),
            if (state.accessUrl != null) ...[
              const SizedBox(height: AppSpacing.s3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppRadius.brMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.accessUrl!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      onPressed: () {
                        // P1 简化:snackbar 显示已复制;P2 可接 share_plus
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制:${state.accessUrl}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      tooltip: '复制',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText(LanWebState state) {
    if (state.ip == null) {
      return '未连接 WiFi,无法启用';
    }
    if (state.enabled && state.serviceRunning) {
      return '运行中 · 同 WiFi 电脑浏览器访问上方地址';
    }
    if (state.enabled && !state.serviceRunning) {
      return '正在启动…';
    }
    return '关闭 · 仅同 WiFi 局域网可访问,无需公网';
  }
}
