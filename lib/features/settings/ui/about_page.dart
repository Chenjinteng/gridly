// lib/features/settings/ui/about_page.dart
// 关于页:品牌说明 + 隐私政策
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/providers.dart';
import '../../../core/settings/app_info_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/card_shadows.dart';
import '../../../core/widgets/gridly_mark.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgInfo = ref.watch(packageInfoProvider).valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final versionTagline = pkgInfo == null
        ? '一格一账 · ...'
        : '一格一账 · v${pkgInfo.version}+${pkgInfo.buildNumber}';
    return Scaffold(
      appBar: AppBar(title: const Text('关于格子记账')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
        children: [
          // 品牌卡
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s3,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s5),
              decoration: BoxDecoration(
                color: AppBrand.ink,
                borderRadius: AppRadius.brLg,
                // rim light border + 阴影,与其他黑底卡保持一致
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                  width: 1.0,
                ),
                boxShadow: CardShadows.dark(context),
              ),
              child: Column(
                children: [
                  const GridlyMark(size: 64, onDark: true),
                  const SizedBox(height: AppSpacing.s3),
                  const Text(
                    '格子记账',
                    style: TextStyle(
                      color: AppSecondary.cream,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    versionTagline,
                    style: const TextStyle(color: AppGray.g400, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          _Section(title: '简介'),
          _BodyCard(
            text: '格子记账是一款本地优先的记账工具,'
                '所有数据只存在你的设备上,不上传任何服务器。'
                '用"格子"的几何语言,让每一笔账目都有自己的位置。',
          ),

          _Section(title: '隐私政策'),
          _BodyCard(
            // markdown 语法修正:
            // - `**` 必须紧贴文字(无空格),CommonMark 不识别 `** 文字 **`
            // - 列表必须用 `-` 或 `*` 开头,`·` 只会当纯文本渲染
            text: '**数据本地化**\n'
                '- 所有流水、分类、设置只存在你的手机/电脑本地数据库中。\n'
                '- 不会上传到任何服务器,不会收集任何使用统计。\n\n'
                '**导出**\n'
                '- CSV 导出由你主动触发,文件用系统分享发出去。\n'
                '- 你可以选择用 AirDrop、邮件、微信等任何渠道,数据流向完全由你控制。\n\n'
                '**权限**\n'
                '- 不申请通讯录 / 短信 / 定位等敏感权限。\n'
                '- 写笔记账只需你主动点击"+"按钮,无需后台监控。\n\n'
                '**开源 / 第三方**\n'
                '- 本应用使用 Flutter / Riverpod / Drift / fl_chart / share_plus 等开源库。\n'
                '- 这些库各自遵循 MIT / BSD / Apache 协议,源代码公开。',
          ),

          _Section(title: '联系'),
          _BodyCard(
            text: '· 仓库:github.com/Chenjinteng/gridly\n'
                '· 项目代号:gridly\n'
                '· 包名:cn.jinteng.gridly',
          ),

          // 危险操作:清空所有数据
          const _Section(title: '危险操作'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s2,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmClearData(context, ref),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppStatus.error),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.brLg,
                  ),
                ),
                child: const Text(
                  '清空所有数据',
                  style: TextStyle(
                    color: AppStatus.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: Text(
              '⚠ 删掉所有流水、自定义分类、本地设置(主题、月度预算等)。\n'
              '  系统预置分类会保留。\n'
              '  此操作不可撤销。',
              style: TextStyle(fontSize: 11, color: AppGray.g600),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
        ],
      ),
    );
  }

  Future<void> _confirmClearData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空所有数据?'),
        content: const Text(
          '所有流水和自定义分类都会被删除。\n'
          '系统预置的 17 个分类会保留。\n'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppStatus.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(databaseProvider).clearAllData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空所有流水')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败:$e')),
        );
      }
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
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

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Container(
        width: double.infinity,
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
        child: MarkdownBody(
          data: text,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(fontSize: 13, height: 1.6),
            h1: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            h2: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            strong: const TextStyle(fontWeight: FontWeight.w700),
            listBullet: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ),
    );
  }
}
