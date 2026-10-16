// lib/features/settings/data/csv_exporter.dart
// 流水导出为 CSV 字符串
//
// 2026-10-16 D65.7 改:CSV 格式升级,支持完整 round-trip
//   - 老格式:date,type,category,amount,note (5 列)
//     - Bug 1:amount 用 Formatters.amount 带千分位逗号,没 quote,
//       解析器把 1,618.41 拆成 2 字段,所有 ≥¥1,000 的行错位
//     - Bug 2:type 压缩成 income/expense,balance/lend_out/borrow_in 全丢,
//       重新导入时调拨/借出/借入 全部当 expense 算,数字炸
//   - 新格式:date,type,category,amount,account,destination_account,note (7 列)
//     - amount 用 toStringAsFixed(2) 无千分位,无歧义
//     - type 直接传 DB 5 个值,完整保留 income/expense/balance/lend_out/borrow_in
//     - account / destination_account 人类可读的账户名
//     - D65.8 改:account 跟 destination_account 用 name 而非 id
//       (D65.7 用了 id,user 反馈"我要人类可读的",name 优先于 id
//       —— 重命名后 re-import 会失效,但人工对账一眼看懂)
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
    // D65.8 加:账户 id → name 映射(跟 catMap 镜像)
    //   - 导出人类可读,Excel 打开一眼看懂"现金→花呗"调拨方向
    //   - re-import 失效的话,人工对账/审计也够用
    final assets = await _db.select(_db.assets).get();
    final assetMap = {for (final a in assets) a.id: a.name};

    // D65.8:7 列 — 跟 D65.7 一样,只是 account / destination_account 改用 name
    final buffer = StringBuffer()
      ..writeln('date,type,category,amount,'
          'account,destination_account,note');

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
      // D65.8:account / destination_account 改账户名(人类可读)
      //   - source (account) 必填 → 一定有 name
      //   - destination (dest) 可空 → null 走空字符串
      //   - 都走 _escape 防账户名带逗号(罕见,defensive)
      final account = _escape(assetMap[t.accountId] ?? '未分类账户');
      final destAccount = t.destinationAccountId != null
          ? _escape(assetMap[t.destinationAccountId] ?? '未分类账户')
          : '';
      final note = _escape(t.note ?? '');
      buffer.writeln(
        '$date,$type,$category,$amount,'
        '$account,$destAccount,$note',
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
