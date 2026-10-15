# Gridly 数据库 Schema 说明

> 本文记录 gridly 的 SQLite 表结构(Drift ORM),覆盖所有表 / 列 / 索引 / 迁移历史 / 种子数据。
>
> 当前 schema 版本:`schemaVersion = 7`(Drift `AppDatabase` 单例,`lib/core/database/app_database.dart`)。
> 数据库文件:`<ApplicationDocumentsDirectory>/gridly.sqlite`(Android 在 app 私有目录,iOS 同)。

---

## 0. 总览

```
┌────────────┐        ┌──────────────────┐        ┌────────────┐
│ categories │◀─┐     │   transactions    │   ┌───▶│  assets    │
│            │  │     │                  │   │    │            │
│ 系统+用户  │  └─────│ categoryId (FK)  │   │    │ 6 段账户   │
│ 自定义分类 │        │ accountId  (FK) ──┼───┘    │            │
└────────────┘        │ destAcctId (FK) ──┼────────│            │
                      └──────────────────┘        └────────────┘
                              │
                              │
                              ▼
                       ┌────────────────┐
                       │ category_      │
                       │ budgets        │
                       │ 月度子额度     │
                       └────────────────┘
```

**4 张表**:
- `categories` — 分类(系统预置 + 用户自定义)
- `transactions` — 流水记录(支出 / 收入 / 调拨 / 投资)
- `assets` — 资产 / 账户(6 段 enum)
- `category_budgets` — 月度分类子额度

**通用约定**:
- 所有表都有 `id` (autoIncrement, PK) + `createdAt` + `updatedAt`(Drift `currentDateAndTime` 默认)
- 所有 FK 都开启 `PRAGMA foreign_keys = ON`(`MigrationStrategy.beforeOpen`)
- 时间戳统一 `DateTime`(Drift 内部存 `INTEGER` Unix epoch ms)

---

## 1. `categories` — 分类表

**文件**: `lib/core/database/tables/categories.dart`

| 列         | 类型      | 约束 / 默认               | 说明                                       |
| ---------- | --------- | ------------------------- | ------------------------------------------ |
| `id`       | `INTEGER` | PK, autoIncrement         |                                            |
| `name`     | `TEXT`    | 1-16 字符                 | 分类名(中文 1-8 字)                        |
| `icon`     | `TEXT`    | NOT NULL                  | icon key,对应预设几何图标                  |
| `color`    | `INTEGER` | NOT NULL                  | ARGB 32-bit(`AppCategory.*`)               |
| `type`     | `TEXT`    | NOT NULL                  | `'expense'` \| `'income'`                  |
| `isSystem` | `BOOLEAN` | default `false`           | true = 系统预置,清空数据时保留             |
| `sortOrder`| `INTEGER` | default `0`               | 列表排序(用户拖拽排序)                    |
| `createdAt`| `DATETIME`| default `currentDateAndTime` |                                          |
| `updatedAt`| `DATETIME`| default `currentDateAndTime` |                                          |

**索引**:无自定义(只有主键索引)。

**种子数据**:见 [`§ 7 种子数据`](#7-种子数据),共 22 条(12 expense + 10 income)。

---

## 2. `transactions` — 流水表

**文件**: `lib/core/database/tables/transactions.dart`

| 列                   | 类型       | 约束 / 默认               | 说明                                                |
| -------------------- | ---------- | ------------------------- | --------------------------------------------------- |
| `id`                 | `INTEGER`  | PK, autoIncrement         |                                                     |
| `amount`             | `REAL`     | NOT NULL                  | 金额,单位:元(保留 2 位)                            |
| `type`               | `TEXT`     | NOT NULL                  | `'expense'` \| `'income'` \| `'balance'`            |
| `categoryId`         | `INTEGER`  | FK → `categories.id`      | 分类(必填)                                         |
| `occurredAt`         | `DATETIME` | NOT NULL                  | 流水发生时间(用于月度 / 日度分组)                   |
| `note`               | `TEXT`     | nullable                  | 备注                                                |
| `accountId`          | `INTEGER`  | FK → `assets.id`          | 源账户(P1 后必填,流水必须挂靠到某账户)             |
| `destinationAccountId` | `INTEGER` | FK → `assets.id`,nullable | 目标账户(仅 investment 投入 / 收益 / 调拨存值)    |
| `createdAt`          | `DATETIME` | default                   |                                                     |
| `updatedAt`          | `DATETIME` | default                   |                                                     |

**`type` 字段语义**:

| 值         | 语义                                                                                  | accountId        | destinationAccountId |
| ---------- | ------------------------------------------------------------------------------------- | ---------------- | -------------------- |
| `expense`  | 现金流出(cash_flow 段,如餐饮/交通/购物)                                              | 现金账户(source) | `null`               |
| `income`   | 现金流入(cash_flow 段,如工资/奖金)                                                    | 现金账户(target) | `null`               |
| `balance`  | 资产流转:① 投资段 投入 / 收益 ② 调拨(双账户)③ 公积金 / 期权 / 外借等不计月度收支场景 | 源账户           | nullable(投资/调拨填) |

**口径约定**(D62 起):
- 月度"收入" = `type == 'income'` 之和(只算 cash_flow income)
- 月度"支出" = `type == 'expense' && category.type == 'expense'` ∪ 还款(`type == 'balance' && category.type == 'liability'`)
- 月度"结余" = 收入 − 支出

**索引**:无自定义。

---

## 3. `assets` — 资产 / 账户表

**文件**: `lib/core/database/tables/assets.dart`(2026-10-12 P1 加)

| 列                       | 类型       | 约束 / 默认                 | 说明                                                  |
| ------------------------ | ---------- | --------------------------- | ----------------------------------------------------- |
| `id`                     | `INTEGER`  | PK, autoIncrement           |                                                       |
| `name`                   | `TEXT`     | 1-24 字符                   | 账户名(如 "现金" / "招行信用卡" / "花呗")            |
| `type`                   | `TEXT`     | NOT NULL                    | 6 段 enum,见下                                        |
| `icon`                   | `TEXT`     | default `'account_balance_wallet'` | Material Icon key                              |
| `color`                  | `INTEGER`  | default `0xFF14B8A6`(teal)  | ARGB 32-bit                                           |
| `initialBalance`         | `REAL`     | default `0.0`               | 期初余额(持久化)                                     |
| `includeInTransactions`  | `BOOLEAN`  | default `true`              | 是否计入日常流水(P6 加,filter 暂未启用)             |
| `isDefault`              | `BOOLEAN`  | default `false`             | cash_flow 段"日常流水默认账户"标记(P7,单例)         |
| `actAsCashFlow`          | `BOOLEAN`  | default `false`             | receivable 段"充当现金流"开关(D61,只对 receivable 有效) |
| `displayOrder`           | `INTEGER`  | default `0`                 | 列表排序                                              |
| `createdAt`              | `DATETIME` | default                     |                                                       |
| `updatedAt`              | `DATETIME` | default                     |                                                       |

**`type` 6 段 enum**(P6 从 4 段 → 6 段):

| 值              | 中文    | 语义                                                    |
| --------------- | ------- | ------------------------------------------------------- |
| `cash_flow`     | 现金流  | 银行卡 / 钱包 / 现金 / 微信支付(99% 场景)               |
| `investment`    | 投资    | 余额宝 / 基金 / 股票                                    |
| `benefit`       | 福利    | 社保 / 公积金 / 公司期权                                |
| `receivable`    | 债务    | 借出 / 借入 / 花呗 / 信用卡(D51 v2 口语化)              |
| `fixed_asset`   | 不动产  | 房 / 车                                                 |
| `other`         | 其它    | 兜底                                                    |

**关键业务开关**:
- `isDefault`(P7):cash_flow 段"日常流水默认账户"标记,记一笔优先命中。**单例**:同时只 1 个 `isDefault=true`(由 `AssetRepository.setDefaultForCashFlow` 维护)。
- `actAsCashFlow`(D61):receivable 段"充当现金流"开关。
  - `true` = 可消费债务(花呗 / 白条 / 信用卡)→ 在记一笔 cash_flow 支出 picker 能选
  - `false` = 不可消费债务(车贷 / 房贷 / 借款)→ 只走 receivable 段调拨还款
  - 非 receivable `type` 恒为 `false`

**当前余额计算**:实时算,不存。
```
currentBalance = initialBalance
               + Σ(type='income' AND accountId = self) amount
               - Σ(type='expense' AND accountId = self) amount
               - Σ(type='balance' AND accountId = self) amount       # 源
               + Σ(type='balance' AND destinationAccountId = self) amount  # 目标
```

**索引**:无自定义。

**种子数据**:见 [`§ 7 种子数据`](#7-种子数据),首次启动 3 个 cash_flow 默认账户(现金 / 银行卡 / 微信支付),老设备升级时按 migration 走。

---

## 4. `category_budgets` — 月度分类子额度表

**文件**: `lib/core/database/tables/category_budgets.dart`(commit 90 加)

| 列         | 类型       | 约束 / 默认                  | 说明                              |
| ---------- | ---------- | ---------------------------- | --------------------------------- |
| `id`       | `INTEGER`  | PK, autoIncrement            |                                   |
| `categoryId` | `INTEGER` | FK → `categories.id`         | 分类                              |
| `year`     | `INTEGER`  | NOT NULL                     | 年                                |
| `month`    | `INTEGER`  | NOT NULL                     | 月(1-12)                          |
| `amount`   | `REAL`     | NOT NULL                     | 子额度(元)                       |
| `createdAt`| `DATETIME` | default                      |                                   |
| `updatedAt`| `DATETIME` | default                      |                                   |

**Unique Key**: `(categoryId, year, month)` —— 同一分类同月只能有一条子额度(Drift `uniqueKeys` 配置)。

**业务语义**(P7 改):
- **总额度** = `monthlyBudget`,存 `SharedPreferences`(不在 DB)
- **子额度** = 本表(用户给具体分类分配)
- **共享剩余池** = 总额度 − Σ(本年本月所有子额度)
- 未配置分类共享共享池

**索引**:Unique key `(categoryId, year, month)` 自动建索引。

---

## 5. 外键关系图

```
categories (1) ──────< (N) transactions
   ▲                          │
   │                          │
   └──── (N) category_budgets │
                              │
                              ▼
                          assets (1) ──────< (N) transactions (accountId)
                              │
                              └────────< (N) transactions (destinationAccountId)
```

**外键约束**:
- `transactions.categoryId` → `categories.id` — RESTRICT(默认,删分类前必须先删流水)
- `transactions.accountId` → `assets.id` — RESTRICT
- `transactions.destinationAccountId` → `assets.id` — RESTRICT
- `category_budgets.categoryId` → `categories.id` — RESTRICT

**启用**:`PRAGMA foreign_keys = ON`(`MigrationStrategy.beforeOpen`,每次打开 db 都设一次)。

---

## 6. 迁移历史(`schemaVersion`)

Drift `MigrationStrategy.onUpgrade` 按 `if (from < N)` 顺序串行跑:

| 版本 | 变更                                                                                              | 引入点                |
| ---- | ------------------------------------------------------------------------------------------------- | --------------------- |
| 1    | 初版:`categories` + `transactions`                                                                | P1 之前               |
| 2    | 新增 `category_budgets` 表                                                                        | commit 90(P7 月度预算) |
| 3    | 新增 `assets` 表 + `transactions.accountId NOT NULL` + FK;首次启动 seed 3 个 cash_flow 默认账户 | commit 110(P1 资产)   |
| 4    | `assets.includeInTransactions` 列,默认 `true`                                                    | P6(4 段 → 6 段)        |
| 5    | `assets.isDefault` 列,默认 `false`;老设备升级时把 displayOrder=0 的"现金"置 `true`              | P7                    |
| 6    | `transactions.destinationAccountId` 列(nullable,FK 引用 assets)                                  | P8(投资场景)           |
| 7    | `assets.actAsCashFlow` 列,默认 `false`                                                           | D61                   |

> **当前版本 7**(`lib/core/database/app_database.dart:33`)。
> 新版本时只需在该 onUpgrade 块追加 `if (from < N)` 分支 + `schemaVersion = N`。

---

## 7. 种子数据

### 7.1 categories — 22 条

**文件**: `lib/shared/constants/default_categories.dart`

#### 7.1.1 支出分类(12 条,`type = 'expense'`)

| name  | icon                | color         |
| ----- | ------------------- | ------------- |
| 餐饮  | `restaurant`        | `food`        |
| 交通  | `directions_bus`    | `transport`   |
| 购物  | `shopping_bag`      | `shopping`    |
| 居住  | `home`              | `housing`     |
| 通讯  | `phone_iphone`      | `telecom`     |
| 医疗  | `medical_services`  | `medical`     |
| 教育  | `school`            | `education`   |
| 娱乐  | `sports_esports`    | `entertainment` |
| 居家  | `chair`             | `housing`     |
| 美妆  | `face_retouching_natural` | `shopping` |
| 宠物  | `pets`              | `housing`     |
| 其他  | `more_horiz`        | `gray`        |

#### 7.1.2 收入分类(10 条,`type = 'income'`)

| name       | 用途                          |
| ---------- | ----------------------------- |
| 工资       | 主收入                        |
| 奖金       | 年终 / 项目奖                 |
| 理财       | 利息 / 余额宝收益             |
| 兼职       | 副业                          |
| 退款       | 退款                          |
| 投资投入   | P8 投资段专用(配合 `type='balance'`) |
| 投资收益   | P8 投资段专用                 |
| 福利       | 福利(社保 / 公积金等)         |
| 债务       | D51 v2 口语化(原"负债"),借出 / 借入 |
| 其它       | 兜底                          |

### 7.2 assets — 3 条(`type = 'cash_flow'`)

**文件**: `lib/core/database/seeds/default_assets.dart`

| name     | icon                        | color            | displayOrder | isDefault |
| -------- | --------------------------- | ---------------- | ------------ | --------- |
| 现金     | `payments`                  | `gold`(0xFFF5BC1F) | 0            | **true**  |
| 银行卡   | `credit_card`               | `teal`(0xFF14B8A6) | 1            | false     |
| 微信支付 | `account_balance_wallet`    | `teal`           | 2            | false     |

> 老设备升级到 schemaVersion=3 时(seed 时期),用 `seedDefaultsIfEmpty()` 兜底,避免重复 seed。
> 其它 5 段(investment / benefit / receivable / fixed_asset / other)不预置,user 主动创建。

---

## 8. 清空数据

`AppDatabase.clearAllData()`(`lib/core/database/app_database.dart:118`):
```dart
Future<void> clearAllData() async {
  await delete(transactions).go();        // 全删流水
  await delete(categoryBudgets).go();     // 全删月度预算
  await (delete(categories)
        ..where((c) => c.isSystem.equals(false))).go();  // 只删用户分类
  await delete(assets).go();              // 全删资产(包括 seed 的 3 个 cash_flow)
}
```

- **保留**:系统预置分类(`isSystem=true`)
- **删除**:所有流水 / 月度预算 / 用户分类 / 全部资产

> 删资产后 caller(UI 层)需主动调 `seedDefaultsIfEmpty()` 重 seed 默认 3 个现金账户,或者 user 自己建。
> D46 修:之前漏删 assets,user 反馈"清空所有数据"按钮实际没清空资产。

---

## 9. 关键代码路径

| 关注点                | 文件                                                  |
| --------------------- | ----------------------------------------------------- |
| Schema 集中定义       | `lib/core/database/app_database.dart`                 |
| 各表 Table class      | `lib/core/database/tables/*.dart`                     |
| Repository 层(增删改查) | `lib/core/database/repositories/*.dart`             |
| 预置分类 / 资产       | `lib/shared/constants/default_categories.dart` + `lib/core/database/seeds/default_assets.dart` |
| Drift 生成代码        | `lib/core/database/app_database.g.dart`(**勿手改**)   |
| 类型 token(色 / 段位) | `lib/core/theme/app_colors.dart`(`AppCategory` / `AppBrand` / `AppStatus`) |

---

> **修订历史**:
> - 2026-10-15 初版(D64.8 同步归档):覆盖 schemaVersion 7 全量结构 + 22+3 种子数据
