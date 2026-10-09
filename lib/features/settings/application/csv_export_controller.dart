// lib/features/settings/application/csv_export_controller.dart
// CSV 导出 controller:生成文件 + 触发系统分享
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/providers.dart';
import '../data/csv_exporter.dart';

final csvExporterProvider = Provider<CsvExporter>((ref) {
  return CsvExporter(ref.watch(databaseProvider));
});

/// 时间范围预设
enum CsvRange { thisMonth, lastMonth, thisYear, all }

class CsvRangeOption {
  const CsvRangeOption(this.label, this.start, this.end);
  final String label;
  final DateTime start;
  final DateTime end;
}

List<CsvRangeOption> buildRangeOptions() {
  final now = DateTime.now();
  final thisMonthStart = DateTime(now.year, now.month, 1);
  final nextMonthStart = DateTime(now.year, now.month + 1, 1);
  final lastMonthStart = DateTime(now.year, now.month - 1, 1);
  return [
    CsvRangeOption(
      '本月',
      thisMonthStart,
      nextMonthStart.subtract(const Duration(seconds: 1)),
    ),
    CsvRangeOption(
      '上月',
      lastMonthStart,
      thisMonthStart.subtract(const Duration(seconds: 1)),
    ),
    CsvRangeOption(
      '本年',
      DateTime(now.year, 1, 1),
      DateTime(now.year + 1, 1, 1).subtract(const Duration(seconds: 1)),
    ),
    CsvRangeOption(
      '全部',
      DateTime(2000),
      DateTime(now.year + 1, 1, 1),
    ),
  ];
}

/// 触发 CSV 导出 + 分享
Future<File> generateCsvFile(WidgetRef ref, CsvRangeOption range) async {
  final csv = await ref.read(csvExporterProvider).generate(range.start, range.end);
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final file = File(p.join(dir.path, 'gridly_$stamp.csv'));
  await file.writeAsString(csv);
  return file;
}

Future<void> shareCsvFile(File file, CsvRangeOption range) async {
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv')],
    text: '格子记账导出 · ${range.label}',
  );
}
