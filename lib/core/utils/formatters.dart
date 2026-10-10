// lib/core/utils/formatters.dart
// 全局格式化工具:金额、日期
import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  // 金额:千分位逗号 + 始终 2 位小数
  // 例:10000 → "10,000.00", 10000.5 → "10,000.50"
  static final NumberFormat _amountFmt = NumberFormat('#,##0.00');
  static String amount(double v) => _amountFmt.format(v);

  /// 流水按日分组的标题:"12月3日 周二"
  static String dayHeader(DateTime d) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  /// 简短日期:"12-03"
  static String shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}