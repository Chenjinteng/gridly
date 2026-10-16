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
// 2026-10-15 D61 加:
//   - actAsCashFlow:BoolColumn,默认 false
//     - 标记 receivable 段账户是否"充当现金流"(花呗/白条/信用卡等可消费债务)
//     - true:在记一笔 cash_flow 段支出 picker 里能选(走 D59 逻辑);调拨也允许
//     - false:不参与"现金流场景",只在 receivable 段(借出/借入/调拨)显示
//       (车贷/房贷/借款,只走调拨还款,不让出现在 cash_flow 支出 source picker)
//     - 新建 receivable 账户默认 false,user 主动在 form 勾选才开
//     - 其它 type 字段恒为 false(只对 receivable 有意义)
//     - 老设备升级默认 false(老数据不会被新列影响,需 user 显式开)
// 2026-10-16 D64.58 加:
//   - isLender:BoolColumn,默认 false
//     - receivable 段账户的"债权人/负债方"标记,默认 false = 借入(我是负债方)
//     - true:借出账户(我是债权人,余额为正,例如借给老王)
//     - false:借入账户(我是负债方,余额为负,例如花呗/车贷/房贷/借款)
//     - 新建 receivable 账户默认 false,user 主动在 form 勾选才开
//     - 其它 type 字段恒为 false(form 切 type 时清零)
//     - 老设备升级默认 false(老数据不会被新列影响,需 user 显式开)
//   - 本次 D64.58 只做 label 落地(form 加 toggle UI + DB 列);后续 D64.59+
//     展开"基于 isLender 的进一步分析"(transaction_form 默认值联动 /
//     AssetTile 显示借出 chip / AssetSummaryCard receivable 拆应收+负债 /
//     LiabilitiesDashboard 加应收卡)
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
  // 2026-10-15 D61 加:receivable 段"充当现金流"开关
  //   - true:可消费债务(花呗/白条/信用卡),在记一笔 cash_flow 支出 picker 里能选
  //   - false:不可消费债务(车贷/房贷/借款),只走 receivable 段调拨
  //   - 默认 false,user 主动勾选;非 receivable type 段恒为 false
  BoolColumn get actAsCashFlow =>
      boolean().withDefault(const Constant(false))();
  // 2026-10-16 D64.58 加:receivable 段"借出"开关(默认 false = 借入)
  //   - true:借出账户(我是债权人,余额为正,例如借给老王)
  //   - false:借入账户(我是负债方,余额为负,例如花呗/车贷/房贷/借款)
  //   - 默认 false,user 主动勾选;非 receivable type 段恒为 false(form 切 type 时清零)
  BoolColumn get isLender =>
      boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
