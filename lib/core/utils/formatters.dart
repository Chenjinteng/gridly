// lib/core/utils/formatters.dart
// 全局格式化工具:金额、日期
class Formatters {
  Formatters._();

  /// 金额:始终 2 位小数(¥ 符号在 UI 层加)
  static String amount(double v) => v.toStringAsFixed(2);

  /// 流水按日分组的标题:"12月3日 周二"
  static String dayHeader(DateTime d) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  /// 简短日期:"12-03"
  static String shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
