// lib/core/utils/formatters.dart
// 全局格式化工具:金额、日期
import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  /// 单笔金额硬上限(个人记账合理天花板):999 万
  /// 超出此值的数据(极端/脏数据)显示截断值 + "+" 后缀提示被 cap
  static const double maxAmount = 9999999.99;

  /// 单位切换阈值:绝对值 ≥ 1 万元(10000)时切到"万"显示
  /// 选 10000 而不是 1000000 的原因:
  ///   - 越大越省长度(50000 直接 5.00万 不需要 50,000.00 占位)
  ///   - "万"是中文自然单位,1万起跳更符合中文记账习惯
  static const double _wanThreshold = 10000.0;

  static final NumberFormat _amountFmt = NumberFormat('#,##0.00');

  /// 金额格式化,智能单位切换:
  ///   - abs(v) < 10000        → 元 mode (千分位逗号 + 2 位小数)
  ///     例:123.45 → "123.45"; 9,999.50 → "9,999.50"
  ///   - 10000 ≤ abs(v) < cap  → 万 mode (千分位 + 2 位小数 + 可选 "万")
  ///     例:10,000 → "1.00万" (withUnit) 或 "1.00" (无 unit)
  ///         999,999 → "99.99万" 或 "99.99"
  ///         9,999,999 → "999.99万" 或 "999.99"
  ///   - abs(v) ≥ cap          → cap display "999.99万+" 或 "999.99+"
  ///
  /// `withUnit` (默认 true): 是否在数值后拼 "万" 单位。
  ///   - true: 用于没有 (元)/(万元) label 的展示位置(同心环"共"、大数字)
  ///   - false: 用于 label 已经带 (元)/(万元) 的 cell/cells,数字只显示数值,
  ///            避免跟 label 重复(如 `收入(万元) ¥999.99`)
  ///
  /// 万 mode 用 truncate 而非 round,避免 9999999/10000=999.9999 舍入到
  /// 1000.00(用户给的目标就是 "9999999 → 999.99万元")。
  static String amount(double v, {bool withUnit = true}) {
    final absV = v.abs();
    if (absV >= maxAmount) {
      return withUnit ? '999.99万+' : '999.99+';
    }
    if (absV >= _wanThreshold) {
      // truncate 到 2 位小数 (向 0 截断)
      // 9999999/10000 = 999.9999 → 999.99
      // -99999/10000 = -9.9999 → -9.99 (truncateTowardZero)
      final wan = v / 10000;
      final truncated = (wan * 100).truncateToDouble() / 100;
      final num = truncated.toStringAsFixed(2);
      return withUnit ? '$num万' : num;
    }
    return _amountFmt.format(v);
  }

  /// 配合 `amount` 用:返回当前 amount 对应单位,用于 label 拼 "(元)/(万元)"
  /// 例:`Formatters.labelledUnit('收入', 9999)` → "收入(元)"
  ///    `Formatters.labelledUnit('支出', 99999)` → "支出(万元)"
  static String unit(double v) =>
      v.abs() >= _wanThreshold ? '万元' : '元';

  /// 快捷 label + unit 拼接。"收入(元)" / "支出(万元)"
  static String labelledUnit(String label, double v) =>
      '$label(${unit(v)})';

  /// 流水按日分组的标题:"12月3日 周二"
  static String dayHeader(DateTime d) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  /// 简短日期:"12-03"
  static String shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}