// lib/core/database/tables/assets.dart
// 资产/账户表(2026-10-12 P1 加,commit 110)
//   - type 字段 6 段 enum:
//     'cash_flow' | 'investment' | 'benefit' | 'receivable' |
//     'fixed_asset' | 'other'
//   - name 字段 free text(具体账户名)
//   - initialBalance 持久化,currentBalance 读时实时算
//   - displayOrder 排序字段
// 2026-10-13 P6 改:
//   - type 4 段 → 6 段(去掉'liability',加'investment' / 'benefit' / 'receivable')
//   - 加 includeInTransactions:BoolColumn,默认 true
//     - true = 计入日常流水(银行卡/钱包/现金)
//     - false = 不计入(投资/福利/债权等"非日常"资产)
//     - 当前只存,filter 暂不动(等调拨 source/target 设计落地再启用过滤)
// 2026-10-13 P7 加:
//   - isDefault:BoolColumn,默认 false
//     - 标记每只 cash_flow 段的"日常流水默认账户",记一笔时优先选
//     - 单例:cash_flow 段同时只能有 1 只 isDefault=true(由 repo.setDefaultForCashFlow 维护)
//     - 非 cash_flow 段恒为 false(记一笔只关心 cash_flow 段默认)
//     - 老数据默认 false,需要 user 主动在资产列表"设为默认"开启,首次启动 seed 时给"现金"开
import 'package:drift/drift.dart';

class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 24)();
  // 6 段 enum:
  //   'cash_flow'     现金流(银行卡/钱包/现金)
  //   'investment'    投资(余额宝/基金/股票)
  //   'benefit'       福利(社保/公积金)
  //   'receivable'    债权/借出(外借给别人)
  //   'fixed_asset'   不动产(房/车)
  //   'other'         其它(兜底)
  TextColumn get type => text()();
  TextColumn get icon =>
      text().withDefault(const Constant('account_balance_wallet'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF14B8A6))();
  RealColumn get initialBalance => real().withDefault(const Constant(0.0))();
  // 2026-10-13 P6 加:开关位,默认 true(老数据全部默认计入流水)
  BoolColumn get includeInTransactions =>
      boolean().withDefault(const Constant(true))();
  // 2026-10-13 P7 加:cash_flow 段的"日常流水默认账户"标记
  //   - 老数据默认 false,seed "现金" 时主动置 true
  //   - 非 cash_flow 段恒为 false(setDefaultForCashFlow 只动 cash_flow 段)
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
