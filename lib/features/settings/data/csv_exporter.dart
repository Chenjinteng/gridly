// lib/features/settings/data/csv_exporter.dart
// 流水导出为 CSV 字符串
// 格式:date,type,category,amount,note
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/formatters.dart';

class CsvExporter {
  CsvExporter(this._db);
  final AppDatabase _db;

  /// 生成指定时间范围的 CSV 字符串
  Future<String> generate(DateTime start, DateTime end) async {
    final txs = await (_db.select(_db.transactions)
          ..where((t) => t.occurredAt.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
        .get();

    final cats = await _db.select(_db.categories).get();
    final catMap = {for (final c in cats) c.id: c.name};

    final buffer = StringBuffer()
      ..writeln('date,type,category,amount,note');

    for (final t in txs) {
      final date = '${t.occurredAt.year.toString().padLeft(4, "0")}-'
          '${t.occurredAt.month.toString().padLeft(2, "0")}-'
          '${t.occurredAt.day.toString().padLeft(2, "0")}';
      final type = t.type == 'income' ? 'income' : 'expense';
      final category = _escape(catMap[t.categoryId] ?? '未分类');
      final amount = Formatters.amount(t.amount);
      final note = _escape(t.note ?? '');
      buffer.writeln('$date,$type,$category,$amount,$note');
    }

    // UTF-8 BOM,Excel 打开不乱码
    return '\uFEFF${buffer.toString()}';
  }

  String _escape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}

/// 在文件里直接生成
class CsvExportService {
  CsvExportService(this._db);
  final AppDatabase _db;

  Future<int> countTransactions(DateTime start, DateTime end) async {
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([_db.transactions.id.count()])
      ..where(_db.transactions.occurredAt.isBetweenValues(start, end));
    return query.map((row) => row.read(_db.transactions.id.count())!).getSingle();
  }
}
