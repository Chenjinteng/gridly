// lib/core/utils/formatters.dart
// 全局格式化工具:金额、日期
import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  /// 单笔金额硬上限(个人记账合理天花板):999 万
  /// 超出此值的数据(极端/脏数据)显示截断值 + "+" 后缀提示被 cap
  static const double maxAmount = 9999999.99;

  /// 单位切换阈值:绝对值 ≥ 100 万元(1000000)时切到"万"显示
  ///
  /// 阈值选 100 万(百万级)而不是更小的原因:
  ///   - 个人记账年收通常 6 位数(几十万),999999 这种长度 cell 用
  ///     `FittedBox(scaleDown)` 能正常展示,不需要万元切单位
  ///   - 真正到百万级(月入 ≥ 100 万、年收 ≥ 1200 万)才"万元起跳",
  ///     这时"¥1,500,000"已是 11+ 字符,cell 会被缩得难看,切"150.00万"
  ///     才换回可读性
  ///   - "万"是中文自然单位,但触发阈值要高,避免普通人月收入 2~3 万
  ///     满屏"2.50万 / 3.65万"那种"中英文混排"感
  ///   - 注:不要自作主张改成 10000 / 1万,2026-10-11 UAT 确认"万元太过了"
  ///
  /// 公开展出给 chart 类(报表 Y 轴)复用,避免再硬编码阈值。
  static const double wanThreshold = 1000000.0;

  static final NumberFormat _amountFmt = NumberFormat('#,##0.00');

  /// 金额格式化,智能单位切换:
  ///   - abs(v) < 100万         → 元 mode (千分位逗号 + 2 位小数)
  ///     例:123.45 → "123.45"; 99,999.50 → "99,999.50"; 999,999 → "999,999.00"
  ///   - 100万 ≤ abs(v) < cap   → 万 mode (2 位小数 + 可选 "万")
  ///     例:1,000,000 → "100.00万" (withUnit) 或 "100.00" (无 unit)
  ///         5,500,000 → "550.00万" 或 "550.00"
  ///         9,999,999 → "999.99万" 或 "999.99"
  ///   - abs(v) ≥ cap           → cap display "999.99万+" 或 "999.99+"
  ///
  /// `withUnit` (默认 true): 是否在数值后拼 "万" 单位。
  ///   - true: 用于没有 (元)/(万元) label 的展示位置(同心环"共"、大数字)
  ///   - false: 用于 label 已经带 (元)/(万元) 的 cell/cells,数字只显示数值,
  ///            避免跟 label 重复(如 `收入(万元) ¥999.99`)
  ///
  /// `forceWan` (默认 false): 强制走万元 mode,无视 wanThreshold。
  ///   - 默认 false: 跟金额本身的绝对值联动(<100万 元,≥100万 万)
  ///   - true: 一律按万元输出,用于"单图 Y 轴统一单位"等需要避免
  ///           小 ticks 走元大 ticks 走万的视觉割裂场景
  ///   - 例:5000 走 forceWan → "0.50万" 而非 "5,000.00"
  ///         0    走 forceWan → "0.00万" 或 "0.00",跟其他 tick 同模式
  ///
  /// 万 mode 用 truncate 而非 round,避免 9999999/10000=999.9999 舍入到
  /// 1000.00(用户给的目标就是 "9999999 → 999.99万元")。
  ///
  /// `trimTrailingZeros` (2026-10-11 UAT 加,默认 false):
  ///   - true → 把整数值的 ".00" 后缀去掉,用于 chart Y 轴 / 紧凑列表等
  ///     "刻度感"场景。"300,000.00" → "300,000", "100.00万" → "100万",
  ///     "0.00" → "0", "0.00万" → "0万"; 非整数值("99,999.50"、"100.50万")保留 ".50"。
  ///   - false → 保留 ".00"(默认,流水 cell / 月度汇总等"金额"场景要明确精度)。
  static String amount(
    double v, {
    bool withUnit = true,
    bool forceWan = false,
    bool trimTrailingZeros = false,
  }) {
    final absV = v.abs();
    if (absV >= maxAmount) {
      return withUnit ? '999.99万+' : '999.99+';
    }
    String result;
    if (forceWan || absV >= wanThreshold) {
      // truncate 到 2 位小数 (向 0 截断)
      // 9999999/10000 = 999.9999 → 999.99
      // -99999/10000 = -9.9999 → -9.99 (truncateTowardZero)
      final wan = v / 10000;
      final truncated = (wan * 100).truncateToDouble() / 100;
      final num = truncated.toStringAsFixed(2);
      result = withUnit ? '$num万' : num;
    } else {
      result = _amountFmt.format(v);
    }
    if (trimTrailingZeros && result.endsWith('.00')) {
      result = result.substring(0, result.length - 3);
    }
    return result;
  }

  /// 配合 `amount` 用:返回当前 amount 对应单位,用于 label 拼 "(元)/(万元)"
  /// 例:`Formatters.labelledUnit('收入', 9999)` → "收入(元)"
  ///    `Formatters.labelledUnit('年收入', 1500000)` → "年收入(万元)"
  static String unit(double v) =>
      v.abs() >= wanThreshold ? '万元' : '元';

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