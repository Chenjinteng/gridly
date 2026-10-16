// lib/features/settings/data/csv_exporter.dart
// 流水导出为 CSV 字符串
//
// 2026-10-16 D65.7→D65.9 改:CSV 格式升级,完全中文化给人工对账
//   - 老格式:date,type,category,amount,note (5 列)
//     - Bug 1:amount 用 Formatters.amount 带千分位逗号,没 quote,
//       解析器把 1,618.41 拆成 2 字段,所有 ≥¥1,000 的行错位
//     - Bug 2:type 压缩成 income/expense,balance/lend_out/borrow_in 全丢,
//       重新导入时调拨/借出/借入 全部当 expense 算,数字炸
//   - D65.9 当前格式:日期,类型,分类,金额,账户,目标账户,备注 (7 列,全中文)
//     - 标题全中文(日期/类型/分类/金额/账户/目标账户/备注)
//     - 类型值全中文(收入/支出/调拨/借出/借入,DB 5 个值 1:1 翻译)
//     - amount 用 toStringAsFixed(2) 无千分位,无歧义
//     - 账户用 name(D65.8),人类可读
//   - 代价:re-import 需要 1 个反向 map(中→DB enum),目前项目无 import 功能,不做
//   - 优先级:人工对账/Excel 看 > re-import 自动化(D65.7~D65.9 迭代方向)
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class CsvExporter {
  CsvExporter(this._db);
  final AppDatabase _db;

  /// D65.9:DB tx.type 5 个 enum → 中文标签映射
  ///   - income → 收入
  ///   - expense → 支出
  ///   - balance → 调拨(源账户减,目标账户加)
  ///   - lend_out → 借出(我是债主,balance 正数)
  ///   - borrow_in → 借入(我是负债方,balance 正数)
  ///   - user 反馈"标准的可读可分辨的",中文标签比 DB enum 直观
  ///   - re-import 需要反向 map,目前项目无 import,不做
  static const Map<String, String> _typeLabel = {
    'income': '收入',
    'expense': '支出',
    'balance': '调拨',
    'lend_out': '借出',
    'borrow_in': '借入',
  };

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

    // D65.9:7 列,全中文 — user 反馈"标准的可读可分辨的"
    //   标题:日期 / 类型 / 分类 / 金额 / 账户 / 目标账户 / 备注
    //   类型:收入 / 支出 / 调拨 / 借出 / 借入(DB 5 个 enum 1:1 翻译)
    final buffer = StringBuffer()
      ..writeln('日期,类型,分类,金额,'
          '账户,目标账户,备注');

    for (final t in txs) {
      final date =
          '${t.occurredAt.year.toString().padLeft(4, "0")}-'
          '${t.occurredAt.month.toString().padLeft(2, "0")}-'
          '${t.occurredAt.day.toString().padLeft(2, "0")}';
      // D65.9:tx.type DB 5 个值 → 中文 1:1 翻译(走 _typeLabel 静态表)
      final type = _typeLabel[t.type] ?? t.type;
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
