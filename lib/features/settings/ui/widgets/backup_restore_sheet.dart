// lib/features/settings/ui/widgets/backup_restore_sheet.dart
// 2026-10-17 D68 加:数据库备份 / 还原底部表单
//   - 仿 csv_export_sheet 的视觉结构(handle + title + 主体 + 底部按钮)
//   - 顶部展示 db 元信息(位置 / 大小 / 修改时间)
//   - 中部两个大按钮:导出备份 / 从备份还原
//   - 底部安全提示
//
// 还原流程(user 选 D68 2 次确认):
//   1. 点"从备份还原" → dialog 1 警告"这会覆盖所有数据" → 确认后进入 file_picker
//   2. file_picker 选完 → dialog 2 最后确认"真的要还原 [filename] 吗?" → 确认后执行
//   3. backupService.restoreDbFromFile 关 db + 复制 + SystemNavigator.pop()
//   4. app 退出,user 重开 → 读到新 db
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/gridly_banner.dart';
import '../../data/backup_service.dart';

class BackupRestoreSheet extends ConsumerStatefulWidget {
  const BackupRestoreSheet({super.key});

  @override
  ConsumerState<BackupRestoreSheet> createState() => _BackupRestoreSheetState();
}

class _BackupRestoreSheetState extends ConsumerState<BackupRestoreSheet> {
  DbInfo? _dbInfo;
  bool _busy = false; // 备份 or 还原进行中,锁按钮

  @override
  void initState() {
    super.initState();
    _loadDbInfo();
  }

  Future<void> _loadDbInfo() async {
    final info = await ref.read(backupServiceProvider).getDbInfo();
    if (mounted) setState(() => _dbInfo = info);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? tmp;
    try {
      final db = ref.read(databaseProvider);
      final file = await ref.read(backupServiceProvider).exportDb(db);
      tmp = file;
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(backupServiceProvider).shareDb(file);
    } catch (e) {
      if (mounted) {
        showGridlyBanner(context, '备份失败:$e', kind: GridlyBannerKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      // 分享后清临时文件(用户可能没真分享完,但下次备份会生成新文件名,留旧文件无意义)
      try {
        await tmp?.delete();
      } catch (_) {}
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    // 第 1 次确认:警告会覆盖所有数据
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('从备份还原?'),
        content: const Text(
          '这会用备份文件覆盖当前所有数据。\n'
          '覆盖后不可撤销,App 会被强制退出,重开后才会生效。\n\n'
          '建议先导出一份 CSV 作为兜底。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppStatus.warning),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续选文件'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !mounted) return;

    // file_picker 选 .sqlite 文件
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.any, // sqlite 没内置 MIME,走 any + 后续扩展名校验
        withData: false, // 大文件路径流,只取 path
      );
    } catch (e) {
      if (mounted) {
        showGridlyBanner(context, '选文件失败:$e', kind: GridlyBannerKind.error);
      }
      return;
    }
    final path = picked?.files.single.path;
    if (path == null) return; // user 取消
    if (!mounted) return;

    // 扩展名校验(防止误选 word 文档等)
    if (!path.toLowerCase().endsWith('.sqlite') &&
        !path.toLowerCase().endsWith('.db')) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('文件类型不对'),
          content: const Text(
            '请选择 .sqlite 或 .db 格式的备份文件。\n'
            '如果是 CSV / Excel 导出,不能用作数据库还原。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }

    // 选完文件,显示元信息给 user 二次确认
    final file = File(path);
    final stat = await file.stat();
    if (!mounted) return;
    final fileName = path.split(Platform.pathSeparator).last;

    // 第 2 次确认:显示备份文件信息 + 最后警告
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('最后确认'),
        content: Text(
          '备份文件:$fileName\n'
          '大小:${_formatSize(stat.size)}\n'
          '修改时间:${formatBackupTimestamp(stat.modified)}\n\n'
          '确认用这个文件覆盖当前数据库?\n'
          '此操作不可撤销,App 会立即退出。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppStatus.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !mounted) return;

    // 执行还原
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      await ref.read(backupServiceProvider).restoreDbFromFile(db, file);
      // 不会执行到这里(SystemNavigator.pop 已退出 app)
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showGridlyBanner(context, '还原失败:$e', kind: GridlyBannerKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s3,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.s3),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '数据库备份还原',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              '完整备份本地数据库 / 从备份还原',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            // 数据库信息卡
            _DbInfoCard(info: _dbInfo),
            const SizedBox(height: AppSpacing.s4),
            // 备份按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                label: Text(_busy ? '处理中...' : '导出数据库备份'),
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                  foregroundColor: isDark ? AppBrand.ink : null,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 还原按钮(危险)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.cloud_download_outlined, size: 20),
                label: const Text('从备份还原'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStatus.warning,
                  side: const BorderSide(color: AppStatus.warning, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            // 底部安全提示
            Text(
              '· 备份包含所有流水/分类/资产/预算/设置\n'
              '· 备份文件用系统分享存到任意位置(网盘/U盘/微信文件)\n'
              '· 还原后 App 会自动退出,重开才会生效\n'
              '· 建议同时定期导出 CSV 备份,作为人读兜底',
              style: TextStyle(fontSize: 11, height: 1.5, color: AppGray.g600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数据库元信息卡(顶部白底卡)
class _DbInfoCard extends StatelessWidget {
  const _DbInfoCard({required this.info});
  final DbInfo? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_outlined, size: 16, color: AppGray.g600),
              const SizedBox(width: AppSpacing.s2),
              Text(
                '当前数据库',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          _InfoRow(
            label: '位置',
            value: info == null
                ? '加载中...'
                : (info!.path.isEmpty
                      ? '(数据库文件不存在)'
                      : _shortenPath(info!.path)),
          ),
          const SizedBox(height: 4),
          _InfoRow(
            label: '大小',
            value: info == null
                ? '加载中...'
                : (info!.sizeBytes == 0 ? '0 B' : _formatSize(info!.sizeBytes)),
          ),
          const SizedBox(height: 4),
          _InfoRow(
            label: '修改时间',
            value: info == null
                ? '加载中...'
                : (info!.modifiedAt == null
                      ? '—'
                      : formatBackupTimestamp(info!.modifiedAt!)),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppGray.g600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 路径缩短(只显示文件名 + 末级目录)
String _shortenPath(String full) {
  final parts = full.split(Platform.pathSeparator);
  if (parts.length <= 2) return full;
  return '...${Platform.pathSeparator}${parts[parts.length - 2]}${Platform.pathSeparator}${parts.last}';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}
