# Gridly 数据库 Schema 说明

> 本文记录 gridly 的 SQLite 表结构(Drift ORM),覆盖所有表 / 列 / 索引 / 迁移历史 / 种子数据。
>
> 当前 schema 版本:`schemaVersion = 9`(Drift `AppDatabase` 单例,`lib/core/database/app_database.dart:38`)。
> 数据库文件:`<ApplicationDocumentsDirectory>/gridly.sqlite`(Android 在 app 私有目录,iOS 同)。
>
> **本文档以 `release/1.0` 分支代码为准**,2026-10-20 依据真实设备库(`gridly.sqlite`,`user_version = 9`)逐表核对重写。

---

## 0. 总览

```
┌────────────┐        ┌──────────────────┐        ┌────────────┐
│ categories │◀─┐     │   transactions    │   ┌───▶│  assets    │
│            │  │     │                  │   │    │            │
│ 系统+用户  │  └─────│ category_id      │   │    │ 6 段账户   │
│ 自定义分类 │        │ account_id       │   │    │            │
│ 7 种 type  │        │ destination_     │◀──┘    │            │
└────────────┘        │ account_id       │        └────────────┘
      ▲               └──────────────────┘
      │                        ▲
      │                        │
┌─────┴──────────┐   ┌─────────┴─────────┐
│ category_      │   │ monthly_budgets   │
│ budgets        │   │ 月度总额度历史     │
│ 分类月度子额度  │   │ (year, month 唯一) │
└────────────────┘   └───────────────────┘
```

**5 张表**:
- `categories` — 分类(系统预置 + 用户自定义)
- `transactions` — 流水记录(支出 / 收入 / 调拨 / 借出 / 借入)
- `assets` — 资产 / 账户(6 段 enum)
- `category_budgets` — 分类月度子额度
- `monthly_budgets` — 月度总额度历史(全年预算走势数据源)

**通用约定**:
- 所有表都有 `id` (autoIncrement, PK) + `createdAt` + `updatedAt`(Drift `currentDateAndTime` 默认)
  - 例外:`monthly_budgets` **只有 `updatedAt`**,没有 `createdAt`(见 §4)
- SQLite 实际列名是 **snake_case**(drift 自动从 camelCase 转换,`categoryId` → `category_id`)
- 时间戳统一 `DateTime`(Drift 内部存 `INTEGER` Unix epoch **seconds** — drift 默认 `storeDateTimeValuesAsText = false`,**见 §9 D71.7**)

### 0.1 关于外键约束(重要,勿照旧文档想当然)

**Drift 的 `.references()` 只在 Dart 层做存在性校验,不会生成 SQL 级 `FOREIGN KEY` 子句。**

已核对真实设备库(`user_version = 9`):
```sql
CREATE TABLE IF NOT EXISTS "transactions" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "amount" REAL NOT NULL,
  "type" TEXT NOT NULL,
  "category_id" INTEGER NOT NULL,
  "occurred_at" INTEGER NOT NULL,
  "note" TEXT NULL,
  "account_id" INTEGER NOT NULL,
  "destination_account_id" INTEGER NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
);
```
> ⚠️ 表里**没有** `REFERENCES` 子句,`PRAGMA foreign_key_list(transactions)` 返回 0 行。
> drift 2.35.2 源码 `lib/src/runtime/query_builder/schema/` 下**不产出** `FOREIGN KEY` 字符串。

**这意味着**:
- `MigrationStrategy.beforeOpen` 里的 `PRAGMA foreign_keys = ON` **对当前 schema 实际无效果**(没有 FK 约束可启用)
- 删分类 / 删账户时,**SQLite 不会**自动拦截悬挂引用
- 引用完整性由 **Repository 层**负责(删资产前先查引用它的流水,见 `asset_repository.dart`)
- 若将来要启用真 FK,需要手写 `customStatement('CREATE TABLE ... FOREIGN KEY ...')` 或改用 drift 文件式 schema

---

## 1. `categories` — 分类表

**文件**: `lib/core/database/tables/categories.dart`

| 列(Dart)     | 列(SQLite)   | 类型      | 约束 / 默认               | 说明                                        |
| ------------- | ------------- | --------- | ------------------------- | ------------------------------------------- |
| `id`          | `id`          | `INTEGER` | PK, autoIncrement         |                                             |
| `name`        | `name`        | `TEXT`    | NOT NULL,1-16 字符        | 分类名(中文 1-8 字)                         |
| `icon`        | `icon`        | `TEXT`    | NOT NULL                  | icon key,对应 `CategoryIcons.map` 预设图标  |
| `color`       | `color`       | `INTEGER` | NOT NULL                  | ARGB 32-bit(`AppCategory.*`)                |
| `type`        | `type`        | `TEXT`    | NOT NULL                  | 7 种值,见下表                                |
| `isSystem`    | `is_system`   | `BOOLEAN` | default `false`           | true = 系统预置,清空数据时保留              |
| `sortOrder`   | `sort_order`  | `INTEGER` | default `0`               | 列表排序(用户拖拽排序)                     |
| `createdAt`   | `created_at`  | `DATETIME`| default `currentDateAndTime` |                                           |
| `updatedAt`   | `updated_at`  | `DATETIME`| default `currentDateAndTime` |                                           |

> `withLength(min: 1, max: 16)` 是 **Dart 层**校验(`checkTextLength`),**不生成 SQL CHECK 约束**。
> SQLite 侧只有 `BOOLEAN` 列带 `CHECK ("xxx" IN (0, 1))`(drift 对 bool 的硬约束)。

**`type` 字段 7 种语义**(不只是 expense / income 两类):

| 值           | 中文     | 用途                                  | UI 可见 |
| ------------ | -------- | ------------------------------------- | ------- |
| `expense`    | 支出     | 日常支出分类(餐饮/交通/…)             | ✅      |
| `income`     | 收入     | 日常收入分类(工资/奖金/…)             | ✅      |
| `investment` | 投资     | 投资投入 / 投资收益                   | ❌ 隐藏 |
| `benefit`    | 福利     | 社保 / 公积金 / 期权                  | ❌ 隐藏 |
| `liability`  | 债务     | 借出 / 借入(与 `assets.type='receivable'` 对账) | ❌ 隐藏 |
| `other`      | 其它     | 兜底段                                | ❌ 隐藏 |
| `adjust`     | 余额调整 | D72 编辑期初余额时自动生成的平账流水   | ❌ 隐藏 |

> **UI 隐藏 + 自动 fallback** 模式(2026-10-14 P18 起):`investment` / `benefit` / `liability` / `other` / `adjust`
> 这几类分类在 `TransactionForm` 里**不显示分类选择器**,表单按当前账户段位自动 fallback 到对应内置分类。
> 之所以仍要存进 DB,是因为 `transactions.category_id` 是 **NOT NULL**,必须有值可填。

**索引**:无自定义(只有主键索引)。

**种子数据**:见 [`§ 6 种子数据`](#6-种子数据)。

---

## 2. `transactions` — 流水表

**文件**: `lib/core/database/tables/transactions.dart`

| 列(Dart)               | 列(SQLite)              | 类型       | 约束 / 默认               | 说明                                             |
| ----------------------- | ------------------------ | ---------- | ------------------------- | ------------------------------------------------ |
| `id`                    | `id`                     | `INTEGER`  | PK, autoIncrement         |                                                  |
| `amount`                | `amount`                 | `REAL`     | NOT NULL                  | 金额,单位:元(保留 2 位)                          |
| `type`                  | `type`                   | `TEXT`     | NOT NULL                  | 5 种值,见下表                                    |
| `categoryId`            | `category_id`            | `INTEGER`  | NOT NULL,FK → categories  | 分类                                            |
| `occurredAt`            | `occurred_at`            | `DATETIME` | NOT NULL                  | 流水发生时间(用于月度 / 日度分组)               |
| `note`                  | `note`                   | `TEXT`     | nullable                  | 备注                                            |
| `accountId`             | `account_id`             | `INTEGER`  | NOT NULL,FK → assets      | 源账户(流水必须挂靠到某账户)                    |
| `destinationAccountId`  | `destination_account_id` | `INTEGER`  | nullable,FK → assets      | 目标账户(调拨 / 投资投入的转入方)               |
| `createdAt`             | `created_at`             | `DATETIME` | default                   |                                                  |
| `updatedAt`             | `updated_at`             | `DATETIME` | default                   |                                                  |

**`type` 字段 5 种语义**:

| 值          | 语义                                     | accountId        | destinationAccountId | 备注                                    |
| ----------- | ---------------------------------------- | ---------------- | -------------------- | --------------------------------------- |
| `expense`   | 现金流出(cash_flow 段,如餐饮/交通/购物)  | 现金账户(source) | `null`               |                                         |
| `income`    | 现金流入(cash_flow 段,如工资/奖金)      | 现金账户(target) | `null`               | 也用于投资**收益**(单账户增长)          |
| `balance`   | 资产流转:调拨(双账户)/ 投资投入(双账户)  | 源账户           | nullable(调拨/投入填) | 公积金 / 期权等不计月度收支场景          |
| `lend_out`  | 借出(我是债权人)                        | 债务账户         | `null`               | D51 起独立 type,`balance += amount`     |
| `borrow_in` | 借入(我是负债方)                        | 债务账户         | `null`               | D51 起独立 type,`balance -= amount`     |

> **投资段映射**(`transaction_form.dart` `_type` getter):
> - 投入 / 调拨 → `type='balance'`(source → dest 双账户)
> - 收益 → `type='income'`(单账户增长,无 destination)
>
> **债务段映射**(D51):
> - 借出 → `type='lend_out'`,借入 → `type='borrow_in'`,调拨 → `type='balance'`

**汇总口径 —— 首页与报表用的是两套规则,别混**:

| 位置              | 口径                                                                                          | 实现                             |
| ----------------- | --------------------------------------------------------------------------------------------- | -------------------------------- |
| **首页 / 流水页** | `type == 'income'` → 收入;**其余全部** → 支出;再叠加"不计入汇总"排除集合                   | `monthSummaryProvider` / `_DaySection` |
| **报表(stats)**   | 收入 = `tx.type=='income' && cat.type=='income'`;支出 = `(tx.type=='expense' && cat.type=='expense')` ∪ `(tx.type=='balance' && cat.type=='liability')` | `statsSummaryProvider`(D62) |

> ⚠️ **两套口径结果会不一致**,这是已知状态(D62.4 注释里记录过同样现象)。
> 差异来源:
> - 首页把 `balance`(调拨)算进支出;报表只把 `cat.type=='liability'` 的调拨算进支出(即还款)
> - 首页不看 `cat.type`,只按 `tx.type` 二分;报表要求 `tx.type` 与 `cat.type` 双向对齐
> - 首页依赖 `isExcludedFromTotals` 排除集合;报表用独立的 `cat.type` 判断
>
> 改汇总逻辑时**两处都要看**,只改一处必然出现"首页和报表对不上"。


**"不计入汇总" ≠ "隐藏"(D18 原则,2026-10-16 D64.78 抽公共 helper)**:
- 规则实现在 `lib/core/utils/excluded_from_totals.dart`(`isExcludedFromTotals()` 纯函数 + `excludedFromTotalsIdsProvider` id 集合)
- 命中排除的记录:
  1. `category.type == 'investment'`(投资 record)
  2. `category.type == 'adjust'`(余额调整流水,D74 加)
  3. `account.includeInTransactions == false`(用户在资产页关了"计入流水")
- **这些记录在流水列表里照常显示**(可编辑 / 删除),只是不进月度与报表统计

**索引**:无自定义。

---

## 3. `assets` — 资产 / 账户表

**文件**: `lib/core/database/tables/assets.dart`(2026-10-12 P1 加)

| 列(Dart)                 | 列(SQLite)                   | 类型       | 约束 / 默认                       | 说明                                                    |
| ------------------------- | ----------------------------- | ---------- | --------------------------------- | ------------------------------------------------------- |
| `id`                      | `id`                          | `INTEGER`  | PK, autoIncrement                 |                                                         |
| `name`                    | `name`                        | `TEXT`     | NOT NULL,1-24 字符                | 账户名(如 "现金" / "招行信用卡" / "花呗")                |
| `type`                    | `type`                        | `TEXT`     | NOT NULL                          | 6 段 enum,见下                                          |
| `icon`                    | `icon`                        | `TEXT`     | default `'account_balance_wallet'`| Material Icon key                                       |
| `color`                   | `color`                       | `INTEGER`  | default `0xFF14B8A6`(teal)        | ARGB 32-bit                                             |
| `initialBalance`          | `initial_balance`             | `REAL`     | default `0.0`                     | 期初余额(持久化)                                       |
| `includeInTransactions`   | `include_in_transactions`     | `BOOLEAN`  | default `true`                    | 是否计入日常流水(D64.78 起**已生效**,见 §2 排除规则)  |
| `isDefault`               | `is_default`                  | `BOOLEAN`  | default `false`                   | cash_flow 段"日常流水默认账户"标记(P7,单例)            |
| `actAsCashFlow`           | `act_as_cash_flow`            | `BOOLEAN`  | default `false`                   | receivable 段"充当现金流"开关(D61)                    |
| `isLender`                | `is_lender`                   | `BOOLEAN`  | default `false`                   | receivable 段"借出/借入"标记(D64.58,schema v9 新增)    |
| `displayOrder`            | `display_order`               | `INTEGER`  | default `0`                       | 列表排序                                                |
| `createdAt`               | `created_at`                  | `DATETIME` | default                           |                                                         |
| `updatedAt`               | `updated_at`                  | `DATETIME` | default                           |                                                         |

> `is_lender` 在真实设备库里是**最后追加的一列**(v8→v9 迁移时 `addColumn` 追加),在 `updated_at` 之后。

> **`includeInTransactions` 的默认值不是恒 `true`**:
> - 表定义层 default = `true`(老数据迁移兼容,P6 时全部账户默认计入)
> - **新建账户时按段位推导**(`asset_form_page.dart`):`cash_flow` → `true`;其他段(investment / benefit / receivable / fixed_asset / other)→ `false`
> - 编辑已有账户时沿用原值
>
> 所以「非现金段账户默认不计入日常流水」是产品决策,不是 DB default。

**`type` 6 段 enum**(P6 从 4 段 → 6 段):

| 值            | UI label   | 语义                                                    |
| ------------- | ---------- | ------------------------------------------------------- |
| `cash_flow`   | 流动资金   | 银行卡 / 钱包 / 现金 / 微信支付(99% 场景)               |
| `investment`  | 投资       | 余额宝 / 基金 / 股票                                    |
| `benefit`     | 福利       | 社保 / 公积金 / 公司期权                                |
| `receivable`  | 债务       | 借出 / 借入 / 花呗 / 信用卡                             |
| `fixed_asset` | 不动产     | 房 / 车                                                 |
| `other`       | 其它       | 兜底                                                    |

> UI label 以 `AppSegment.labelFor()`(`lib/core/theme/app_colors.dart`)为唯一数据源:
> - `cash_flow` → **流动资金**(D64.40 从"现金流"改,避免跟"收支流水"混淆)
> - `receivable` → **债务**(D51 v2 从"负债"改,口语化)
>
> **DB enum 保持不变**(`cash_flow` / `receivable`),只改 UI 显示文案 —— 技术命名稳定,不要跟着改 DB 值。

**关键业务开关**:
- `isDefault`(P7):cash_flow 段"日常流水默认账户"标记,记一笔优先命中。**单例**:同时只 1 个 `isDefault=true`(由 `AssetRepository.setDefaultForCashFlow` 维护)。
- `actAsCashFlow`(D61):receivable 段"充当现金流"开关。
  - `true` = 可消费债务(花呗 / 白条 / 信用卡)→ 在记一笔 cash_flow 支出 picker 能选
  - `false` = 不可消费债务(车贷 / 房贷 / 借款)→ 只走 receivable 段调拨还款
  - 非 receivable `type` 恒为 `false`
- `isLender`(D64.58):receivable 段"债权人 / 负债方"标记。
  - `true` = 借出(我是债权人,余额为正,例如借给老王)
  - `false` = 借入(我是负债方,余额为负,例如花呗 / 车贷 / 房贷)
  - 非 receivable `type` 恒为 `false`(form 切 type 时清零)

**当前余额计算**:实时算,不存(见 `asset_repository.dart` `balanceDeltaByAssetId()`)。
```
currentBalance = initialBalance
               + Σ(type='income'     AND accountId = self) amount
               - Σ(type='expense'    AND accountId = self) amount
               - Σ(type='balance'    AND accountId = self) amount          # 源账户转出
               + Σ(type='balance'    AND destinationAccountId = self) amount # 目标账户转入
               + Σ(type='lend_out'   AND accountId = self) amount          # 借出:我是债权人
               - Σ(type='borrow_in'  AND accountId = self) amount          # 借入:我是负债方
```

**索引**:无自定义。

**种子数据**:见 [`§ 6 种子数据`](#6-种子数据),首次启动 3 个 cash_flow 默认账户(现金 / 银行卡 / 微信支付)。

---

## 4. `category_budgets` — 分类月度子额度表

**文件**: `lib/core/database/tables/category_budgets.dart`(commit 90 加)

| 列(Dart)   | 列(SQLite)  | 类型       | 约束 / 默认                  | 说明            |
| ----------- | ------------ | ---------- | ---------------------------- | --------------- |
| `id`        | `id`         | `INTEGER`  | PK, autoIncrement            |                 |
| `categoryId`| `category_id`| `INTEGER`  | NOT NULL,FK → categories     | 分类            |
| `year`      | `year`       | `INTEGER`  | NOT NULL                     | 年              |
| `month`     | `month`      | `INTEGER`  | NOT NULL                     | 月(1-12)        |
| `amount`    | `amount`     | `REAL`     | NOT NULL                     | 子额度(元)      |
| `createdAt` | `created_at` | `DATETIME` | default                      |                 |
| `updatedAt` | `updated_at` | `DATETIME` | default                      |                 |

**Unique Key**: `(category_id, year, month)` —— 同一分类同月只能有一条子额度(Drift `uniqueKeys` 配置)。
> SQLite 层落地为表约束 `UNIQUE ("category_id", "year", "month")`,**不生成独立索引**(SQLite 自动建 `sqlite_autoindex_*`)。

**业务语义**(P7 改):
- **总额度** = `monthlyBudget`,存 `SharedPreferences`(不在 DB)
- **子额度** = 本表(用户给具体分类分配)
- **共享剩余池** = 总额度 − Σ(本年本月所有子额度)
- 未配置分类共享共享池

---

## 5. `monthly_budgets` — 月度总额度历史表

**文件**: `lib/core/database/tables/monthly_budgets.dart`(2026-10-15 D64.21a 加,schema v7→v8)

| 列(Dart)  | 列(SQLite) | 类型       | 约束 / 默认 | 说明                        |
| ---------- | ----------- | ---------- | ----------- | --------------------------- |
| `id`       | `id`        | `INTEGER`  | PK, autoIncrement |                     |
| `year`     | `year`      | `INTEGER`  | NOT NULL    | 年                          |
| `month`    | `month`     | `INTEGER`  | NOT NULL    | 月(1-12)                    |
| `amount`   | `amount`    | `REAL`     | NOT NULL    | 月度总额度(元)              |
| `updatedAt`| `updated_at`| `DATETIME` | default     | 最后一次落库时间            |

> ⚠️ **本表没有 `createdAt`**,只有 `updatedAt`(upsert 语义,不需要创建时间)。

**Unique Key**: `(year, month)` —— 同一月只能有一条总额度(set 时按 `(year, month)` upsert)。

**与 `category_budgets` 的区别**:
| | `category_budgets` | `monthly_budgets` |
| - | - | - |
| 粒度 | 每个分类每月 | 每个月一个总额度 |
| 年数据量 | N×12 行 | 12 行/年 |
| 用途 | 分类子额度分配 | 报表"全年预算走势"数据源 |

**与 `SharedPreferences` 的关系**:
- `SharedPreferences` 单值 `monthly_budget` 保持不动,作为"当月快速读 + 离线 fallback"
- 本表作为历史档案,`MonthlyBudgetNotifier.set()` 时双写

**老用户升级路径**(v7→v8):
- `onUpgrade` 只 `createTable`,**不回填历史月份**(避免幻觉回填过去月份的假数据)
- 当月回填由 `MonthlyBudgetNotifier.init()` 启动时统一处理:读 SharedPreferences 单值,当月本表没记录则补 1 条

---

## 6. 种子数据

### 6.1 categories — 23 条(12 expense + 5 income + 6 隐藏)

**文件**: `lib/shared/constants/default_categories.dart`

#### 6.1.1 支出分类(12 条,`type = 'expense'`)

| name  | icon                | color token     | 实际色值    |
| ----- | ------------------- | --------------- | ----------- |
| 餐饮  | `restaurant`        | `food`          | warning 橙  |
| 交通  | `directions_bus`    | `transport`     | info 蓝     |
| 购物  | `shopping_bag`      | `shopping`      | `#EC4899` 粉|
| 居住  | `home`              | `housing`       | `#92400E` 棕|
| 通讯  | `phone_iphone`      | `telecom`       | `#06B6D4` 青|
| 医疗  | `medical_services`  | `medical`       | error 红    |
| 教育  | `school`            | `education`     | `#8B5CF6` 紫|
| 娱乐  | `movie`             | `entertainment` | success 绿  |
| 居家  | `chair`             | `home`          | `#D97706` 棕橙 |
| 美妆  | `spa`               | `beauty`        | `#F43F5E` 玫红 |
| 宠物  | `pets`              | `pet`           | `#FB923C` 浅橙 |
| 其他  | `more_horiz`        | `neutral`       | `#A1A1AA` 灰 |

> 颜色 token 全部来自 `AppCategory`(`lib/core/theme/app_colors.dart`),不硬编码在 seed 文件里。
> 兜底分类"其他"与"退款"共用中性灰 `neutral`。

#### 6.1.2 收入分类(5 条,`type = 'income'`)

| name | icon              | color token | 用途                     |
| ---- | ----------------- | ----------- | ------------------------ |
| 工资 | `payments`        | `salary`    | 主收入(金)               |
| 奖金 | `card_giftcard`   | `bonus`     | 年终 / 项目奖(亮金)      |
| 理财 | `savings`         | `invest`    | 利息 / 余额宝收益(绿)    |
| 兼职 | `work`            | `parttime`  | 副业(紫)                 |
| 退款 | `replay`          | `neutral`   | 退款(灰)                 |

#### 6.1.3 UI 隐藏分类(6 条,自动 fallback)

| name     | icon              | `type`      | color token | 用途                              |
| -------- | ----------------- | ----------- | ----------- | --------------------------------- |
| 投资投入 | `savings`         | `investment`| `invest`    | 投资段投入 / 调拨                 |
| 投资收益 | `trending_up`     | `investment`| `invest`    | 投资段收益                        |
| 福利     | `favorite`        | `benefit`   | `benefit`   | 福利段账户收支                    |
| 债务     | `request_quote`   | `liability` | `liability` | 债务段对账(借出 / 借入)           |
| 其它     | `category`        | `other`     | `other`     | 其它段账户收支                    |
| 余额调整 | `tune`            | `adjust`    | `other`     | D72 编辑期初余额时自动生成平账流水 |

> **合计 23 条**(12 + 5 + 6)。全部 `isSystem = true`(`CategoryRepository._toCompanion` 统一写死)。
>
> ⚠️ `余额调整` 的 icon `tune` **不在 `CategoryIcons.map` 里**(map 内无此 key),
> UI 取图标时走 `CategoryIcons.map[icon] ?? Icons.category_rounded` 兜底 → 实际显示为通用 category 图标。
> 该分类本身 UI 隐藏,只在资产详情 / 备份导出里出现,影响有限。

**seed 路径**(`lib/main.dart` 启动时按序执行):
| 顺序 | 调用 | 作用 |
| ---- | ---- | ---- |
| 1 | `seedDefaultsIfEmpty()` | 仅当 categories 表为空时,批量插入 expense + income + investment + benefit + liability + other(22 条) |
| 2 | `syncCategoryIcons()` | 老用户系统分类图标升级到 v2 语义化图标(幂等) |
| 3 | `syncCategoryColors()` | 老用户系统分类颜色同步到当前代码值(幂等) |
| 4 | `ensureInvestmentCategories()` | 幂等补 investment 2 条 |
| 5 | `ensureBenefitCategories()` | 幂等补 benefit 1 条 |
| 6 | `ensureReceivableCategories()` | 幂等补 liability 1 条 |
| 7 | `ensureOtherCategories()` | 幂等补 other 1 条 |
| 8 | `ensureBalanceAdjustCategory()` | 幂等补 adjust 1 条(D72 加) |

### 6.2 assets — 3 条(`type = 'cash_flow'`)

**文件**: `lib/core/database/seeds/default_assets.dart`

| name     | icon                     | color            | displayOrder | isDefault |
| -------- | ------------------------ | ---------------- | ------------ | --------- |
| 现金     | `payments`               | `gold`(`0xFFF5BC1F`) | 0        | **true**  |
| 银行卡   | `credit_card`            | `teal`(`0xFF14B8A6`) | 1        | false     |
| 微信支付 | `account_balance_wallet` | `teal`(`0xFF14B8A6`) | 2        | false     |

> 老设备升级到 schemaVersion=3 时(seed 时期)用 `seedDefaultsIfEmpty()` 兜底,避免重复 seed。
> 其它 5 段(investment / benefit / receivable / fixed_asset / other)不预置,user 主动创建。

---

## 7. 迁移历史(`schemaVersion`)

Drift `MigrationStrategy.onUpgrade` 按 `if (from < N)` 顺序串行跑:

| 版本 | 变更                                                                                              | 引入点                |
| ---- | ------------------------------------------------------------------------------------------------- | --------------------- |
| 1    | 初版:`categories` + `transactions`                                                                | P1 之前               |
| 2    | 新增 `category_budgets` 表                                                                        | commit 90(P7 月度预算) |
| 3    | 新增 `assets` 表 + `transactions.accountId` 改 NOT NULL + FK;首次启动 seed 3 个 cash_flow 默认账户   | commit 110(P1 资产)   |
| 4    | `assets.include_in_transactions` 列,默认 `true`                                                  | P6(4 段 → 6 段)        |
| 5    | `assets.is_default` 列,默认 `false`;老设备升级时把 displayOrder=0 的"现金"置 `true`              | P7                    |
| 6    | `transactions.destination_account_id` 列(nullable,FK 引用 assets)                                 | P8(投资场景)          |
| 7    | `assets.act_as_cash_flow` 列,默认 `false`                                                          | D61                   |
| 8    | 新增 `monthly_budgets` 表                                                                          | D64.21a               |
| 9    | `assets.is_lender` 列,默认 `false`                                                                 | D64.58                |

> **当前版本 9**(`lib/core/database/app_database.dart:38`)。
> 新版本时只需在该 onUpgrade 块追加 `if (from < N)` 分支 + `schemaVersion = N`。
>
> **注意**:加列统一用 `m.addColumn(表, 列)`,SQLite 会把新列追加到表末尾 —— 所以真实设备库里
> `is_lender` 在 `updated_at` 之后,`include_in_transactions` 在 `initial_balance` 之后。
> 新装设备(走 `onCreate` → `createAll()`)列顺序则跟 Dart 定义顺序一致。

### 7.1 迁移注意事项

- **加列必须给 default**:`withDefault(...)`,否则老库 `NOT NULL` 列无值会失败
- **改列类型 / 加约束** 需写 `customStatement` 重建表,drift 的 `addColumn` 不支持
- **`PRAGMA foreign_keys = ON` 目前无效**(见 §0.1),迁移期若需保护引用,靠业务代码保证
- 老设备升级时**不回填历史数据**(如 monthly_budgets 只补当月),避免幻觉数据

---

## 8. 清空数据

`AppDatabase.clearAllData()`(`lib/core/database/app_database.dart:142`):
```dart
Future<void> clearAllData() async {
  await delete(transactions).go();        // 全删流水
  await delete(categoryBudgets).go();     // 全删分类月度预算
  await (delete(categories)
        ..where((c) => c.isSystem.equals(false))).go();  // 只删用户分类
  await delete(assets).go();              // 全删资产(包括 seed 的 3 个 cash_flow)
}
```

- **保留**:系统预置分类(`isSystem=true`,共 23 条)
- **删除**:所有流水 / 分类月度预算 / 用户分类 / 全部资产

> ⚠️ **已知遗漏**:`monthly_budgets` **没有**被清空(本函数未覆盖该表)。
> 清空数据后月度总额度历史仍会保留,如需一并清空,得手动补 `await delete(monthlyBudgets).go();`。

> 删资产后 caller(UI 层)需主动调 `seedDefaultsIfEmpty()` 重 seed 默认 3 个现金账户,或者 user 自己建。
> D46 修:之前漏删 assets,user 反馈"清空所有数据"按钮实际没清空资产。

---

## 9. 关键代码路径

| 关注点                  | 文件                                                                          |
| ----------------------- | ----------------------------------------------------------------------------- |
| Schema 集中定义         | `lib/core/database/app_database.dart`                                        |
| 各表 Table class        | `lib/core/database/tables/*.dart`                                            |
| Repository 层(增删改查)| `lib/core/database/repositories/*.dart`                                      |
| 预置分类                | `lib/shared/constants/default_categories.dart`(`CategoryIcons` 也在此文件)  |
| 预置资产                | `lib/core/database/seeds/default_assets.dart`                                |
| 种子 / 幂等补种         | `lib/core/database/repositories/category_repository.dart`                    |
| 启动时 seed 编排        | `lib/main.dart`                                                              |
| 段位 label / 颜色 token | `lib/core/theme/app_colors.dart`(`AppSegment` / `AppCategory` / `AppBrand`)  |
| "不计入汇总"规则        | `lib/core/utils/excluded_from_totals.dart`                                   |
| 汇总 / 报表口径         | `lib/features/ledger/application/transactions_providers.dart` + `lib/features/stats/application/stats_providers.dart` |
| CSV 导出(7 列全中文)   | `lib/features/settings/data/csv_exporter.dart`                              |
| Drift 生成代码          | `lib/core/database/app_database.g.dart`(**勿手改**)                         |

---

## 10. 已知坑:D71.7 drift 时间戳单位错位

### 真相
- **drift 默认 `storeDateTimeValuesAsText = false`**(drift 2.35.2 `analysis/options.dart`)
- 这意味着 DateTimeColumn 内部存的是 **`INTEGER` Unix epoch seconds**(10 位),**不是** ms(13 位)
- 实际 SQL DEFAULT:`CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)`(只 cast,**没有** × 1000)
- drift 读写内部自动转换:`DateTime → seconds → INTEGER`,反之 `INTEGER → seconds → DateTime`,Dart 端始终是 `DateTime`

### 反面教材(踩过的坑)
- **app 装机显示"58792 年"**:某个 seed 脚本用 `int(dt.timestamp() * 1000)` 写 ms(13 位),drift 读出当成 seconds(1.79e12),又 × 1000 转 ms → `DateTime(58792 年 4 月)`。每个 `occurred_at` / `created_at` 都是 58792 年,流水列表 / 日期选择器全错。
- **污染源**:Python seed 脚本 `int(dt.timestamp() * 1000)`(ms)→ db 列实际期望 seconds(10 位)。drift 不做单位检查,默默 × 1000 当 ms 用 → 58792 年。

### 修法(seed 脚本必须写秒)
- **正确**:`int(dt.timestamp())` → seconds(10 位,匹配 drift 期望)
- **错误**:`int(dt.timestamp() * 1000)` → ms(13 位,drift 会错位 → 58792 年)
- **验证**:`sqlite3 db "SELECT datetime(MIN(created_at),'unixepoch') FROM transactions"` 必须是 2020+ 年(`unixepoch` 修饰符把 INTEGER 当 seconds 解读)

> ⚠️ **本机 `/tmp/gridly-*.sqlite` 这类 Python 脚本生成的库,DDL 里写的是 `* 1000` 的 ms 版本**,
> 与 app 真实 schema(设备库)不一致 —— 拿它们当 schema 参考会踩坑。**以设备真实库为准。**

### app 内部读写(无坑)
- `DateTime.now()` → drift 内部转 seconds 写 db
- drift 读出 → 自动 `seconds * 1000` 转回 DateTime
- Dart 端代码(`t.occurredAt.year` 等)永远是正常 DateTime,不需要 × 1000 / ÷ 1000
- **唯一例外**:seed 脚本 / 外部工具(直接 SQL INSERT)必须写 seconds,不能写 ms

### 适用范围
- 所有 gridly 1.X / 2.X 的 SQLite db(共用同一份 schema 概念)
- 任何用 drift + SQLite 的项目:先查 `analysis/options.dart:storeDateTimeValuesAsText` 默认值,再决定 seed 脚本单位
- 外部测试 / mock 工具:避免使用 `DateTime.now().millisecondsSinceEpoch`(13 位),改用 `DateTime.now().millisecondsSinceEpoch ~/ 1000`(10 位,drift 期望)

---

## 11. 对外数据交换格式

### 11.1 CSV 导出(D65.9,7 列全中文)

**文件**: `lib/features/settings/data/csv_exporter.dart`

- **UTF-8 BOM** 开头(`\uFEFF`),Excel 打开不乱码
- **7 列**:日期 / 类型 / 分类 / 金额 / 账户 / 目标账户 / 备注
- **类型列**:DB 5 个 enum → 中文 1:1 翻译(`收入` / `支出` / `调拨` / `借出` / `借入`)
- **金额**:`toStringAsFixed(2)` 纯数字(**不用** `Formatters.amount` —— 它带千分位逗号会让 CSV 错位)
- **账户 / 目标账户**:存账户名(人类可读),不是 id;目标账户为空时留空字符串
- **转义**:含 `,` `"` `\n` 的字段用 `"` 包裹,内部 `"` 双写
- **兜底**:未知 type 直接输出 DB 原值;未知分类 / 账户显示"未分类" / "未分类账户"
- **re-import**:目前项目**无** import 功能,故没做反向映射;若将来加,需补 `invert(map)`

### 11.2 数据库备份 / 还原(D68)

**文件**: `lib/features/settings/data/backup_service.dart`

- **备份**:`VACUUM INTO '<temp>'` —— 原子、压实、自动 checkpoint WAL(避免 `file.copy` 漏 `.sqlite-wal` 导致不一致)。需 SQLite ≥ 3.27.0 / 2019-02,Android API 21+ 设备都满足
- **还原**:`db.close()` → 复制覆盖 → `SystemNavigator.pop()` 强制退出(让 user 重开读到新 db;db 在线时不能直接覆盖,必须先 close 释放文件锁)

---

> **修订历史**:
> - 2026-10-15 初版(D64.8 同步归档):覆盖 schemaVersion 7 全量结构 + 22+3 种子数据
> - 2026-10-19 D71.7 补:把时间戳单位错位教训写进文档(秒 vs ms,seed 脚本必须写秒)
> - 2026-10-20 **全量重写**:对齐 `release/1.0` 分支真实代码 + 真实设备库(`user_version=9`)逐表核对
>   - schemaVersion 7 → **9**,4 张表 → **5 张表**(补 `monthly_budgets`)
>   - `assets` 补 `is_lender` 列(v9)
>   - `categories.type` 补齐 **7 种**语义(原文档只写了 expense / income)
>   - `transactions.type` 补齐 **5 种**(原文档只写了 3 种,漏了 `lend_out` / `borrow_in`)
>   - 种子数据 22 → **23 条**,并按 `default_categories.dart` 真实 icon / color token 重排
>   - **修正错误**:原 §5 声称外键是 "RESTRICT 约束 + `PRAGMA foreign_keys = ON` 强制"—— 实际 drift **不生成 SQL 级 FK**,真实库里 0 个 REFERENCES(新增 §0.1 专门说明)
>   - **修正错误**:原 §2 口径描述与 `stats_providers.dart` 实现不一致,已按 D62 实际规则重写
>   - 补 `includeInTransactions` 的真实生效位置(D64.78 `excluded_from_totals.dart`)
>   - 补 §8 `clearAllData` 漏删 `monthly_budgets` 的已知遗漏
>   - 补 §11 CSV 导出 / 备份还原格式
