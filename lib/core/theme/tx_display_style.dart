// lib/core/theme/tx_display_style.dart
// 流水显示风格集中表(label / color / prefix)
//
// 2026-10-16 D64.77 抽:同一概念"流水类型 → 显示"在 3 处 switch(支出/收入/调拨/
// 借出/借入)
//   - amount_display.dart:switch(type) → color
//   - transaction_tile.dart:switch(type) → prefix (+/-/空)
//   - transaction_tile.dart:switch(type) → label(借出/借入显示 transaction.type,
//     其它走 cat.name)
//   3 处分散后改 1 处必漏改其它处,抽此集中表 3 处共用
//
// 设计要点:
//   - 跟 DB type 直接对应(expense/income/balance/lend_out/borrow_in)
//   - 投资 input/output/transfer 不在内(投资 record 显示走 cat.name '投资投入'/
//     '投资收益' 区分,跟 amount_display / tile 无关)
//   - 调拨 prefix 为空(balance 流水可正可负,跟"支出=负/收入=正"语义不同)
//   - 借出/借入 prefix 反向 ——
//     asset 走"债务方向"语义(借出=+, 借入=-),
//     display 走"现金流向"语义(借出=我失去钱=-, 借入=我得到钱=+),
//     transaction_tile 已注释说明 D51 v2 双视角
import 'package:flutter/painting.dart';

import 'app_colors.dart';

class TxDisplayStyle {
  const TxDisplayStyle({
    required this.label,
    required this.color,
    required this.prefix,
  });

  /// 中文显示(支出 / 收入 / 调拨 / 借出 / 借入)
  final String label;

  /// 文字色(金额 / 标签)
  final Color color;

  /// 金额前 prefix('-' / '+' / '' 调拨)
  final String prefix;

  /// 5 种 DB type 静态实例,集中常量,避免重复 new
  static const TxDisplayStyle expense = TxDisplayStyle(
    label: '支出',
    color: AppStatus.error,
    prefix: '-',
  );
  static const TxDisplayStyle income = TxDisplayStyle(
    label: '收入',
    color: AppBrand.teal,
    prefix: '+',
  );
  static const TxDisplayStyle balance = TxDisplayStyle(
    label: '调拨',
    color: AppSecondary.softGold,
    prefix: '',
  );
  static const TxDisplayStyle lendOut = TxDisplayStyle(
    label: '借出',
    color: AppSegment.receivable,
    prefix: '-',
  );
  static const TxDisplayStyle borrowIn = TxDisplayStyle(
    label: '借入',
    color: AppStatus.error,
    prefix: '+',
  );

  /// DB type → TxDisplayStyle 工厂
  ///   - 不在 5 种里的 type 兜底为 expense(原 amount_display 行为)
  ///   - 投资 input/output/transfer(3 种 _intent)走 cat.name,不在此表
  static TxDisplayStyle forType(String type) {
    switch (type) {
      case 'income':
        return income;
      case 'balance':
        return balance;
      case 'lend_out':
        return lendOut;
      case 'borrow_in':
        return borrowIn;
      case 'expense':
      default:
        return expense;
    }
  }
}
