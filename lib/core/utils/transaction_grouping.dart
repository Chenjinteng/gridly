// lib/core/utils/transaction_grouping.dart
// 流水按日分组 + 组内排序(纯函数,repository / provider 层共用)
//
// 2026-10-20 D64.74 抽:组内排序规则只此 1 处定义
//
// 背景:原实现 SQL 只 `ORDER BY occurred_at DESC`(单键),而 SQLite 对排序键
//   相同的行**不保证顺序** → 同一天的多条实际按 rowid 升序返回(先插入的在前),
//   表现像"随机"(user UAT 反馈"同一天插入多条,先后顺序是随机的")。
//
// 组内排序键为什么选 `id`:
//   - id:INTEGER PRIMARY KEY AUTOINCREMENT → 单调递增、**删除后不复用**
//     → id 序 ≡ 插入序,零歧义 ✅
//   - created_at:SQLite `currentDateAndTime` 精度只到**秒**,同秒插入照样并列,
//     还得再叠一层 key,反而更绕 ❌
//   - occurred_at:存的是"发生时间",而且改日期时保留的是**表单打开那一刻**的
//     时分秒(transaction_form.dart _pickDate)→ 补记历史日期的流水 occurred_at
//     可能更早,跟"最新插入在前"矛盾 ❌
//
// 所以:SQL 层 `occurred_at DESC` 定跨天分组顺序,组内纯按 id 降序。
import '../database/app_database.dart';

/// 按自然日分组流水,组内按 id 降序(= 插入顺序,最新插入的最前面)
///
/// - key:发生日期(年月日,时分秒归零)
/// - 组内:id 降序 → 后插入的排前面
/// - 组之间:由调用方决定(UI 层按 key 倒序,新的天在上)
Map<DateTime, List<Transaction>> groupTransactionsByDay(
  List<Transaction> txs,
) {
  final map = <DateTime, List<Transaction>>{};
  for (final t in txs) {
    final day = DateTime(
      t.occurredAt.year,
      t.occurredAt.month,
      t.occurredAt.day,
    );
    map.putIfAbsent(day, () => []).add(t);
  }
  for (final list in map.values) {
    // id 降序 = 插入顺序,新的在前(D64.74)
    list.sort((a, b) => b.id.compareTo(a.id));
  }
  return map;
}
