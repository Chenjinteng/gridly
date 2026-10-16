// lib/features/settings/data/csv_exporter.dart
// 流水导出为 CSV 字符串
//
// 2026-10-16 D65.7 改:CSV 格式升级,支持完整 round-trip
//   - 老格式:date,type,category,amount,note (5 列)
//     - Bug 1:amount 用 Formatters.amount 带千分位逗号,没 quote,
//       解析器把 1,618.41 拆成 2 字段,所有 ≥¥1,000 的行错位
//     - Bug 2:type 压缩成 income/expense,balance/lend_out/borrow_in 全丢,
//       重新导入时调拨/借出/借入 全部当 expense 算,数字炸
//   - 新格式:date,type,category,amount,account_id,destination_account_id,note (7 列)
//     - amount 用 toStringAsFixed(2) 无千分位,无歧义
//     - type 直接传 DB 5 个值,完整保留 income/expense/balance/lend_out/borrow_in
//     - account_id(source) 必填;destination_account_id(dest) null 走空字符串
//     - 这样 re-import 可还原所有调拨方向(source ← 减 / dest ← 加 / 调拨双方)
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class CsvExporter {
  CsvExporter(this._db);
  final AppDatabase _db;

  /// 生成指定时间范围的 CSV 字符串
  Future<String> generate(DateTime start, DateTime end) async {
    final txs =
        await (_db.select(_db.transactions)
              ..where((t) => t.occurredAt.isBetweenValues(start, end))
              ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
            .get();

    final cats = await _db.select(_db.categories).get();
    final catMap = {for (final c in cats) c.id: c.name};

    // D65.7:7 列 — 多了 account_id + destination_account_id,支持 balance
    //   调拨 round-trip;不传时(纯 income/expense)destination 留空字符串
    final buffer = StringBuffer()
      ..writeln('date,type,category,amount,'
          'account_id,destination_account_id,note');

    for (final t in txs) {
      final date =
          '${t.occurredAt.year.toString().padLeft(4, "0")}-'
          '${t.occurredAt.month.toString().padLeft(2, "0")}-'
          '${t.occurredAt.day.toString().padLeft(2, "0")}';
      // D65.7:tx.type 5 个值全传(原代码压缩成 income/expense 丢 3 个)
      //   - income / expense:真收支
      //   - balance:调拨(源账户减,目标账户加)
      //   - lend_out:借出(我是债主,balance 正数)
      //   - borrow_in:借入(我是负债方,balance 正数)
      final type = t.type;
      final category = _escape(catMap[t.categoryId] ?? '未分类');
      // D65.7:amount 改 toStringAsFixed(2) 替代 Formatters.amount
      //   - Formatters.amount 加千分位逗号("1,618.41"),CSV 无 quote → 错位
      //   - toStringAsFixed 纯数字("1618.41"),CSV 解析无误
      final amount = t.amount.toStringAsFixed(2);
      // D65.7:account_id (source,必填) + destination_account_id (dest,可空)
      //   - type=income/expense:destination 留空(没调拨)
      //   - type=balance/lend_out/borrow_in:两边都填,可还原方向
      final accountId = t.accountId;
      final destAccountId =
          t.destinationAccountId?.toString() ?? '';
      final note = _escape(t.note ?? '');
      buffer.writeln(
        '$date,$type,$category,$amount,'
        '$accountId,$destAccountId,$note',
      );
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
    return query
        .map((row) => row.read(_db.transactions.id.count())!)
        .getSingle();
  }
}
