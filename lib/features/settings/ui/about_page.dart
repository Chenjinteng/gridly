// lib/features/settings/ui/about_page.dart
// 关于页:品牌卡 + 简介(开发缘起 + 格子记账)+ 隐私政策 + 免责说明 + 联系 + 危险操作(清空数据)
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/providers.dart';
import '../../../core/settings/app_info_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/card_shadows.dart';
import '../../../core/theme/gridly_palette.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../../core/utils/refresh_providers.dart';
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
                // D71.3:永远走 inkPalette.inkSurface — 深色模式不会变 cream
                color: Theme.of(context).extension<GridlyPalette>()!.inkSurface,
                borderRadius: AppRadius.brLg,
                // rim light border + 阴影,与其他黑底卡保持一致
                border: Border.all(
                  color: Theme.of(context)
                      .extension<GridlyPalette>()!
                      .onInkSurface
                      .withValues(alpha: isDark ? 0.08 : 0.15),
                  width: 1.0,
                ),
                boxShadow: CardShadows.dark(context),
              ),
              child: Column(
                children: [
                  const GridlyMark(size: 64, onDark: true),
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    '格子记账',
                    style: TextStyle(
                      // D71.3:onInkSurface 永远是 cream
                      color:
                          Theme.of(context).extension<GridlyPalette>()!.onInkSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    versionTagline,
                    style: TextStyle(
                      // D71.3:次级文字用 onInkSurface 60% alpha
                      color: Theme.of(context)
                          .extension<GridlyPalette>()!
                          .onInkSurface
                          .withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          _Section(title: '简介'),
          _BodyCard(
            text:
                '**为什么自己做**\n'
                '市面上的记账软件,要么塞满广告,要么订阅收费,要么用不顺手,'
                '更让人不安的是大部分默认联网——你的数据被传到哪、怎么用、谁在看,'
                '你既看不到也管不了。\n'
                '索性自己造一个真正符合自己场景的工具,'
                '所有数据就放在自己的设备里,谁也拿不走。\n\n'
                '**格子记账**\n'
                '一款本地优先的离线记账 app。'
                '不联网、不申请任何权限、不收集任何信息、不上传任何内容。'
                '没有广告、没有内购、没有订阅。'
                '用"格子"的几何语言,让每一笔账目都有自己的位置。'
                '打开就记,关上就忘。',
          ),

          _Section(title: '隐私政策'),
          _BodyCard(
            // markdown 语法修正:
            // - `**` 必须紧贴文字(无空格),CommonMark 不识别 `** 文字 **`
            // - 列表必须用 `-` 或 `*` 开头,`·` 只会当纯文本渲染
            text:
                '**数据本地化**\n'
                '- 所有流水、分类、设置只存在你的手机/电脑本地数据库中。\n'
                '- 不会上传到任何服务器,不会收集任何使用统计。\n\n'
                '**导出**\n'
                '- CSV 导出只导流水(收入/支出/分类/账户/时间/备注),由你主动触发,用系统分享发出去。\n'
                '- 数据库备份导出完整 SQLite(流水 + 分类 + 资产 + 预算 + 设置),适合带完整备份 / 换机迁移。\n'
                '- 你可以选择用 AirDrop、邮件、微信等任何渠道,数据流向完全由你控制。\n\n'
                '**权限**\n'
                '- 不申请通讯录 / 短信 / 定位等敏感权限。\n'
                '- 写笔记账只需你主动点击"+"按钮,无需后台监控。',
          ),

          _Section(title: '免责说明'),
          _BodyCard(
            text:
                '**这是一个个人项目**\n'
                '格子记账是作者用爱发电的个人作品,源代码按 AGPL-3.0 协议开源。\n'
                '不保证无 bug、不保证数据 100% 安全、不保证长期持续维护。\n\n'
                '**请自行备份数据**\n'
                '- 强烈建议定期使用"导出数据库备份"或"导出 CSV"功能备份你的数据。\n'
                '- 一旦设备损坏、丢失、刷机,本地数据无法找回,作者无法恢复。\n'
                '- 本应用不是云端服务,数据只在你手上,备份也只在你手上。\n\n'
                '**责任限制**\n'
                '- 因使用本应用导致的任何损失(包括但不限于记账错误、数据丢失、误操作),'
                '作者不承担任何责任。\n'
                '- 记账数据请以官方银行 / 支付平台账单为准,本应用只作辅助记录。\n\n'
                '**反馈**\n'
                '- 官方站点 gridly.sretalk.com 提供最新 APK 下载、版本日志、反馈入口。\n'
                '- 源码 / Issue:github.com/Chenjinteng/gridly。\n'
                '- 这不是一个商业产品,没有客服、没有 SLA、也没有承诺。',
          ),

          _Section(title: '联系'),
          _BodyCard(
            text:
                '· 官网:gridly.sretalk.com\n'
                '· 仓库:github.com/Chenjinteng/gridly\n'
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
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
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
          // 2026-10-14 改(D46):提示文案补'资产'和'分类预算',
          // 之前 user 看到"清空所有数据"按钮但 assets 没被清,提示误导
          '所有流水 / 自定义分类 / 分类预算 / 资产 都会被删除。\n'
          '系统预置的 17 个分类会保留(后续清空仍能使用)。\n'
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
      // 2026-10-14 加(D46):refreshAllData 让 UI 同步看到'已清空'状态
      // 之前没 refresh,流水列表 / 资产页 仍显示旧缓存数据
      refreshAllData(ref);
      if (context.mounted) {
        showGridlyBanner(context, '已清空所有数据', kind: GridlyBannerKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        showGridlyBanner(context, '清空失败:$e', kind: GridlyBannerKind.error);
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
            h1: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            strong: const TextStyle(fontWeight: FontWeight.w700),
            listBullet: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ),
    );
  }
}
