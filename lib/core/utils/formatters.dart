// lib/core/utils/formatters.dart
// 全局格式化工具:金额、日期
import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  /// 单笔金额硬上限(个人记账合理天花板):999 万
  /// 超出此值的数据(极端/脏数据)显示截断值 + "+" 后缀提示被 cap
  static const double maxAmount = 9999999.99;

  // 金额:千分位逗号 + 始终 2 位小数
  // 例:10000 → "10,000.00", 10000.5 → "10,000.50"
  // 超过 maxAmount 时压缩成 "9,999,999+" —— .XX 已隐含在 cap 里所以去掉,
  // "+" 单一符号够说明"被截断"。避免在报表黑底汇总 / 同心环中心这种
  // 紧凑位置把字体强行缩到失衡("9,999,999.99+" 比 "9,999,999+" 长 4 字符)。
  static final NumberFormat _amountFmt = NumberFormat('#,##0.00');
  static String amount(double v) {
    if (v.abs() > maxAmount) return '9,999,999+';
    return _amountFmt.format(v);
  }

  /// 流水按日分组的标题:"12月3日 周二"
  static String dayHeader(DateTime d) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  /// 简短日期:"12-03"
  static String shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}