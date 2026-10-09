// lib/features/settings/ui/widgets/csv_export_sheet.dart
// CSV 导出底部表单:选时间范围 → 生成 → 触发分享
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/csv_export_controller.dart';

class CsvExportSheet extends ConsumerStatefulWidget {
  const CsvExportSheet({super.key});

  @override
  ConsumerState<CsvExportSheet> createState() => _CsvExportSheetState();
}

class _CsvExportSheetState extends ConsumerState<CsvExportSheet> {
  int _selectedIndex = 0;
  bool _exporting = false;

  late final _ranges = buildRangeOptions();

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final range = _ranges[_selectedIndex];
      final file = await generateCsvFile(ref, range);
      if (!mounted) return;
      Navigator.of(context).pop();
      await shareCsvFile(file, range);
      // 分享后删除临时文件
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败:$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _ranges[_selectedIndex];
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
              '导出 CSV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              '选个时间范围,导出后用系统分享发出去',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            ..._ranges.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                child: _RangeOption(
                  label: r.label,
                  sub: '${Formatters.shortDate(r.start)} - ${Formatters.shortDate(r.end)}',
                  selected: _selectedIndex == i,
                  onTap: () => setState(() => _selectedIndex = i),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.s4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _exporting ? null : _export,
                style: FilledButton.styleFrom(
                  backgroundColor: AppBrand.ink,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.brLg,
                  ),
                ),
                child: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppBrand.gold,
                        ),
                      )
                    : Text('导出 · ${range.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeOption extends StatelessWidget {
  const _RangeOption({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppBrand.teal.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected ? AppBrand.teal : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppBrand.teal : AppGray.g400,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 12, color: AppGray.g600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
