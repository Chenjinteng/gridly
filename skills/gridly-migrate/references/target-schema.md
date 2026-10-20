# gridly 目标 Schema 契约（迁移必须严格对齐）

> 目标:`gridly-migrated.sqlite` 产物必须能被 gridly app 直接导入并正常打开。
> 基线:`release/1.0` 分支,`schemaVersion = 9`,`PRAGMA user_version = 9`。
> 权威来源:`~/Documents/Projects/gridly-1.X/docs/SCHEMA.md` + 真实设备库 DDL。

---

## 1. 硬性要求（违反则 app 打不开或数据错乱）

| 项 | 要求 | 违反后果 |
|---|---|---|
| `PRAGMA user_version` | **必须 = 9** | app 触发 migration 从 0 跑,建出空表,用户数据全丢 |
| 表数量 | **5 张**,名字与列名**逐字符一致** | drift 找不到表 → 崩溃 |
| 列名 | **snake_case**(drift 自动转:`categoryId`→`category_id`) | 列不存在 → 查询报错 |
| 时间戳单位 | **Unix epoch 秒**(10 位),不是毫秒(13 位) | 毫秒 → app 显示「58792 年」 |
| `created_at`/`updated_at` | 存在则写值,不存在则**不要**自己加 | 多了列 drift 不认识 |
| `amount` | `REAL`,**正数**,方向由 `type` 表达 | 负数 → 余额算错 |
| `transactions.account_id` | **NOT NULL** | 每条流水必须挂一个资产 |
| `transactions.category_id` | **NOT NULL** | 每条流水必须挂一个分类 |

> **时间戳单位是最高频的坑**:drift 读 `INTEGER` 时当 seconds,再 `× 1000` 转 ms。
> 写毫秒 → `1791907200000` 被当 seconds → 读出 58792 年。
> 验证:`sqlite3 db "SELECT datetime(MAX(created_at),'unixepoch') FROM transactions"` 必须返回 2020+ 年。

---

## 2. 目标 DDL（照抄,勿改）

```sql
CREATE TABLE "categories" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "icon" TEXT NOT NULL,
  "color" INTEGER NOT NULL,
  "type" TEXT NOT NULL,
  "is_system" INTEGER NOT NULL DEFAULT 0 CHECK ("is_system" IN (0, 1)),
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
);

CREATE TABLE "assets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "icon" TEXT NOT NULL DEFAULT 'account_balance_wallet',
  "color" INTEGER NOT NULL DEFAULT 4279548070,
  "initial_balance" REAL NOT NULL DEFAULT 0.0,
  "include_in_transactions" INTEGER NOT NULL DEFAULT 1 CHECK ("include_in_transactions" IN (0, 1)),
  "is_default" INTEGER NOT NULL DEFAULT 0 CHECK ("is_default" IN (0, 1)),
  "act_as_cash_flow" INTEGER NOT NULL DEFAULT 0 CHECK ("act_as_cash_flow" IN (0, 1)),
  "is_lender" INTEGER NOT NULL DEFAULT 0 CHECK ("is_lender" IN (0, 1)),
  "display_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
);

CREATE TABLE "transactions" (
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

CREATE TABLE "category_budgets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "category_id" INTEGER NOT NULL,
  "year" INTEGER NOT NULL,
  "month" INTEGER NOT NULL,
  "amount" REAL NOT NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  UNIQUE ("category_id", "year", "month")
);

CREATE TABLE "monthly_budgets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "year" INTEGER NOT NULL,
  "month" INTEGER NOT NULL,
  "amount" REAL NOT NULL,
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  UNIQUE ("year", "month")
);
```

> **无 `FOREIGN KEY` 子句** —— drift 的 `.references()` 只在 Dart 层校验,不生成 SQL 级 FK。
> 所以 `PRAGMA foreign_keys` 开不开都无所谓,但 **引用完整性必须由迁移脚本自己保证**
> (每个 `category_id` / `account_id` 都要指向真实存在的行)。

---

## 3. 枚举值全集（超出即为非法数据）

### 3.1 `transactions.type` — 5 值

| 值 | 语义 | account_id | destination_account_id |
|---|---|---|---|
| `expense` | 现金流出 | 源账户 | NULL |
| `income` | 现金流入 | 目标账户 | NULL |
| `balance` | 资产流转(调拨/投资投入) | 源账户 | 转入账户(可 NULL) |
| `lend_out` | 借出(我是债权人) | 债务账户 | NULL |
| `borrow_in` | 借入(我是负债方) | 债务账户 | NULL |

> 迁移旧数据时,旧库的「转账 / 转出 / 转入」→ `balance` + 双账户。
> **没有明确配对的转账不要硬凑**,列入报告。

### 3.2 `categories.type` — 7 值

| 值 | 用途 |
|---|---|
| `expense` | 支出分类(可被用户看到) |
| `income` | 收入分类(可被用户看到) |
| `investment` | 投资段(UI 隐藏,自动 fallback) |
| `benefit` | 福利段(UI 隐藏) |
| `liability` | 债务段(UI 隐藏) |
| `other` | 其它段(UI 隐藏) |
| `adjust` | 余额调整(D72,UI 隐藏) |

### 3.3 `assets.type` — 6 值

| 值 | UI label | 语义 |
|---|---|---|
| `cash_flow` | 流动资金 | 银行卡 / 钱包 / 现金 / 微信支付 |
| `investment` | 投资 | 余额宝 / 基金 / 股票 |
| `benefit` | 福利 | 社保 / 公积金 |
| `receivable` | 债务 | 借出 / 借入 / 花呗 / 信用卡 |
| `fixed_asset` | 不动产 | 房 / 车 |
| `other` | 其它 | 兜底 |

---

## 4. 系统预置分类（23 条,`is_system = 1`）

迁移产物**必须包含**这 23 条系统分类 —— app 启动时 `ensureXxxCategories()` 靠 name 幂等匹配补种,
但种子已存在时不会更新 icon/color,所以**要按这份表原样写入**,否则用户在 app 里看到的图标颜色不对。

### 4.1 expense(12 条)

| name | icon | color(ARGB 十进制) | 十六进制 |
|---|---|---|---|
| 餐饮 | `restaurant` | 4279544313 | `0xFFFF9800` (warning) |
| 交通 | `directions_bus` | 4278190081 | `0xFF2196F3` (info) |
| 购物 | `shopping_bag` | 4291359721 | `0xFFEC4899` |
| 居住 | `home` | 4293691406 | `0xFF92400E` |
| 通讯 | `phone_iphone` | 4286346836 | `0xFF06B6D4` |
| 医疗 | `medical_services` | 4294901760 | `0xFFEF4444` (error) |
| 教育 | `school` | 4287180758 | `0xFF8B5CF6` |
| 娱乐 | `movie` | 4279205083 | `0xFF22C55E` (success) |
| 居家 | `chair` | 4293726470 | `0xFFD97706` |
| 美妆 | `spa` | 4290309214 | `0xFFF43F5E` |
| 宠物 | `pets` | 4292133948 | `0xFFFB923C` |
| 其他 | `more_horiz` | 4292364890 | `0xFFA1A1AA` (neutral) |

> ⚠️ 上表颜色为**按 `AppCategory` token 推导的近似值**,实际以 app 真实库为准。
> 迁移脚本运行时**必须从参考源读取真实值**,不要硬编码这列。
> 权威查询:
> ```bash
> sqlite3 "$HOME/Library/Containers/cn.jinteng.gridly/Data/Documents/gridly.sqlite" \
>   "SELECT name,icon,color,type,sort_order FROM categories WHERE is_system=1 ORDER BY type,sort_order;"
> ```

### 4.2 income(5 条)

| name | icon | color |
|---|---|---|
| 工资 | `payments` | `0xFFF5BC1F` (gold) |
| 奖金 | `card_giftcard` | `0xFFFFC107` |
| 理财 | `savings` | `0xFF22C55E` (success) |
| 兼职 | `work` | `0xFFA855F7` |
| 退款 | `replay` | `0xFFA1A1AA` (neutral) |

### 4.3 UI 隐藏(6 条)

| name | icon | type | color |
|---|---|---|---|
| 投资投入 | `savings` | `investment` | `0xFF22C55E` |
| 投资收益 | `trending_up` | `investment` | `0xFF22C55E` |
| 福利 | `favorite` | `benefit` | `0xFFEC4899` |
| 债务 | `request_quote` | `liability` | `0xFFEF4444` |
| 其它 | `category` | `other` | `0xFF71717A` |
| 余额调整 | `tune` | `adjust` | `0xFF71717A` |

> `余额调整` 的 icon `tune` **不在 `CategoryIcons.map` 里**,app 里会 fallback 成 `category` 图标。
> 这是已知现象,迁移照抄 `tune` 即可。

### 4.4 系统预置资产(3 条)

app 首次启动 seed 3 个 cash_flow 账户。**迁移产物必须包含**,否则 app 里"现金"默认账户缺失。

| name | icon | color | display_order | is_default |
|---|---|---|---|---|
| 现金 | `payments` | `0xFFF5BC1F` | 0 | **1** |
| 银行卡 | `credit_card` | `0xFF14B8A6` | 1 | 0 |
| 微信支付 | `account_balance_wallet` | `0xFF14B8A6` | 2 | 0 |

---

## 5. 语义映射速查（旧数据 → gridly）

### 5.1 分类映射

旧数据分类 → gridly `categories`:
1. **名称命中系统 23 条** → 复用该系统分类(id 指向它),`is_system = 1`
2. **未命中** → 新建自定义分类,`is_system = 0`
   - `type` 按旧分类语义判定:支出类 → `expense`,收入类 → `income`
   - `color` 从 `AppCategory.hashPalette` 12 色轮转取(见 `app_colors.dart`)
   - `icon` 从 `CategoryIcons.map` 里挑语义相近的;挑不到用 `more_horiz`
   - `sort_order` 给递增值

### 5.2 资产映射

旧数据账户/账户组 → gridly `assets`:
- 旧库只有「账户名 + 余额」,无段位 → 归 `cash_flow`,余额放 `initial_balance`
- 旧库标了「信用卡 / 花呗 / 欠款」→ `receivable`,`act_as_cash_flow = 1`(可消费),`is_lender = 0`(借入)
- 旧库标了「借给别人 / 应收」→ `receivable`,`is_lender = 1`(借出)
- 旧库标了「基金 / 股票 / 余额宝」→ `investment`
- 旧库标了「公积金 / 社保」→ `benefit`
- 余额为负的账户 → 说明是负债,考虑 `receivable` + `is_lender = 0`
- `include_in_transactions`:cash_flow 默认 1,其它段默认 0(对齐 app 建账户时的推导规则)

> **余额语义**:gridly 的 `initial_balance` 是**期初余额**,
> `currentBalance = initial_balance + Σ(income) - Σ(expense) - Σ(balance 源) + Σ(balance 目标)`。
> 若旧库给的是**当前余额**而非期初余额,直接填 `initial_balance` 会重复计算 —— 见 `references/mapping-rules.md`。

### 5.3 流水映射

| 旧数据形态 | gridly 写入 |
|---|---|
| 支出行 | `type='expense'`, `amount=abs(值)`, `account_id`=账户, `category_id`=支出分类 |
| 收入行 | `type='income'`, `amount=abs(值)`, `account_id`=账户, `category_id`=收入分类 |
| 转账行(有源和目标) | `type='balance'`, `amount=abs(值)`, `account_id`=源, `destination_account_id`=目标 |
| 转账行(只有一端) | 列入报告,不硬凑 |
| 金额带符号(负=支出) | 取 abs,用符号推 type |
| 余额型账户无流水 | 用 `initial_balance` 承载,不造流水 |

### 5.4 汇总口径提醒(决定哪些流水该进月度统计)

app 里有**两套**汇总口径,改数据时要知道:

- **首页/流水页**(`monthSummaryProvider`):`type == 'income'` → 收入,**其余全部** → 支出;再叠加排除集合
- **报表**(`statsSummaryProvider`):收入 = `tx.type=='income' && cat.type=='income'`;支出 = `(tx.type=='expense' && cat.type=='expense')` ∪ `(tx.type=='balance' && cat.type=='liability')`

**排除集合**(`core/utils/excluded_from_totals.dart`):
`cat.type=='investment'` / `cat.type=='adjust'` / `account.include_in_transactions == 0` 的记录不计入汇总,
但**在流水列表里照常显示**(可编辑可删除)—— 这是产品原则,不是 bug。

> 迁移时若旧数据有「投资」类记录,把它归到 `cat.type='investment'` 即可自动不计入月度汇总。
> 归到 `expense` 则会被算进支出。

---

## 6. 产物自检清单

生成 `gridly-migrated.sqlite` 后必须逐项验证:

```bash
DB=gridly-migrated.sqlite

# ① user_version 必须是 9
sqlite3 "$DB" "PRAGMA user_version;"          # → 9

# ② 5 张表都在
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
# → assets / categories / category_budgets / monthly_budgets / transactions (+ sqlite_sequence)

# ③ 时间戳是秒不是毫秒
sqlite3 "$DB" "SELECT datetime(MAX(occurred_at),'unixepoch') FROM transactions;"
# → 必须是 2020+ 年,不是 58792 年

# ④ 没有悬空引用(FK 不会自动拦,必须自己查)
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions t LEFT JOIN categories c ON t.category_id=c.id WHERE c.id IS NULL;"
# → 0
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions t LEFT JOIN assets a ON t.account_id=a.id WHERE a.id IS NULL;"
# → 0
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions t LEFT JOIN assets a ON t.destination_account_id=a.id WHERE t.destination_account_id IS NOT NULL AND a.id IS NULL;"
# → 0

# ⑤ 金额无负数
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions WHERE amount < 0;"   # → 0

# ⑥ type 全在枚举内
sqlite3 "$DB" "SELECT DISTINCT type FROM transactions;"
# → 只能是 expense/income/balance/lend_out/borrow_in

# ⑦ 系统分类 23 条 + 系统资产 3 条
sqlite3 "$DB" "SELECT COUNT(*) FROM categories WHERE is_system=1;"   # → 23
sqlite3 "$DB" "SELECT COUNT(*) FROM assets WHERE name IN ('现金','银行卡','微信支付');"  # → 3

# ⑧ 每个 cash_flow 账户最多 1 个 is_default
sqlite3 "$DB" "SELECT COUNT(*) FROM (SELECT account_id FROM assets WHERE is_default=1 GROUP BY account_id HAVING COUNT(*)>1);"  # → 0
```
