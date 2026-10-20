---
name: gridly-migrate
description: |
  把其它记账 App 的旧数据(CSV / Excel)迁移进 gridly(格子记账),产出可直接导入 app 的
  gridly-migrated.sqlite,并生成一份 Markdown 报告列出无法迁移/降级迁移的数据。
  Use this skill when the user wants to migrate old ledger/accounting data into gridly,
  import a CSV or Excel bill export (Alipay/WeChat/随手记 etc) into gridly, or produce a
  gridly-compatible sqlite file from another bookkeeping app.
  触发词:迁移旧数据、导入账单、gridly 迁移、记账数据搬家、支付宝账单导入、
  微信账单导入、把旧的记账数据转到 gridly、migrate ledger data into gridly。
  不要用于:gridly 自身的数据库备份/还原(app 内「备份还原」功能即可)、
  修改 gridly 源码、从 gridly 导出数据。
descriptions:
  zh-Hans: "把其它记账 App 的旧数据(CSV/Excel)迁移进 gridly,产出可导入的 sqlite + 未迁移数据报告。"
displayNames:
  zh-Hans: "Gridly 数据迁移"
---

# gridly 数据迁移

把旧记账数据搬进 gridly。**产物是一个 sqlite 文件 + 一份报告**,不碰用户设备。

## 输入

- **源文件**:CSV 或 Excel(.xlsx)。其它格式(别的 sqlite / JSON / 图片账单)不在本 skill 范围 —— 遇到时明确告诉用户不支持,不要勉强。
- **可选配置**:`config.json`,用于修正自动识别不准的地方(见 `references/mapping-rules.md` §config)。

## 产出

| 文件 | 说明 |
|---|---|
| `gridly-migrated.sqlite` | gridly schemaVersion 9 的数据库,可被 app 直接导入 |
| `migration-report.md` | 迁移结果 + **无法迁移的数据清单** + 导入步骤 |

## 流程

### 1. 先看源数据,再决定怎么映射

```bash
head -30 <源文件>          # CSV:看表头在第几行、有哪些列
```

必须先搞清楚三件事,**不要跳过**:

1. **表头在第几行** —— 支付宝/微信导出的 CSV 开头有几行说明文字,表头不在第 1 行
2. **每列是什么语义** —— 日期 / 金额 / 收支柱 / 分类 / 账户 / 目标账户 / 备注 / 余额
3. **数据到哪行结束** —— 末尾通常是「共 N 笔记录」汇总行

列名因 App 而异,必须实际读表头,不能假设。语义判定表见 `references/mapping-rules.md` §1-2。

### 2. 跑迁移脚本

```bash
python3 <SKILL_DIR>/scripts/build_migrated_db.py \
  --source <源文件> \
  --out gridly-migrated.sqlite \
  --report migration-report.md \
  [--config config.json] \
  [--merge-into <已有的 gridly.sqlite>]
```

脚本只依赖 Python 标准库(xlsx 用内置 zipfile+xml 解析,**不需要** pandas/openpyxl)。

脚本会打印:表头行、识别到的列语义、写入统计、10 项自检结果。

> ⚠️ **自检陷阱**:0 行数据时所有自检项都会「通过」(没有悬空引用,因为根本没有行)。
> 所以**必须看「流水写入 N 笔」** —— N=0 说明全被跳过了,不能只看「自检全过」。

### 2.5 选模式:干净库 还是 合并进现有账本?

这是**最关键的一个决策**,先跟用户确认再跑。

gridly 1.X 的「备份还原」是**整库覆盖**(`db.close()` → 复制覆盖 `gridly.sqlite` → 退出 app),
所以:

| 模式 | 命令 | 结果 | 适用 |
|---|---|---|---|
| **合并**(默认推荐给"导进现有账本") | `--merge-into <用户现有的 gridly.sqlite>` | 保留用户原有全部数据,追加新导入的 | 用户说"导进我的 gridly" |
| **干净库** | 不加 `--merge-into` | 只有本次导入的数据 | 用户说"我要一个干净的库" / 还没有旧账本 |

> ⚠️ **干净库 + 还原 = 覆盖掉用户现有账本**。除非用户明确要"干净库",
> 否则优先用 `--merge-into`,并在交付时提醒"先在 app 里导出一次备份"。

`--merge-into` 的基线库从哪来:
- macOS:app 容器 `~/Library/Containers/cn.jinteng.gridly/Data/Documents/gridly.sqlite`
- Android:用 `adb pull` 拉 `app_flutter/gridly.sqlite`(见 `push_testdb.md`)

合并模式会自动:复用库里的已有分类和账户(不造重复)、按机构名匹配账户
(「招商银行(1234)」→ 已有的「工资卡(招商银行)」)、保留用户原有的 `is_default` 设置。


### 3. 检查识别结果,必要时用 config 修正

看脚本输出的「识别到的列语义」:

- `date` / `amount` **必须有**,缺了迁移质量会很差 → 用 `--config` 的 `columns` 显式指定
- 识别错了(比如把「交易对方」当成分类)→ 用 `--config` 覆盖
- 收/支方向判定错了 → 用 `--config` 的 `type_map` 补充
- **微信账单**没有「交易分类」列,分类来源是「商品」—— 脚本已内置识别 + 关键词归并,
  正常不用配;若仍报「分类为空」,用 `--config` 指定 `"category": "商品"`

`config.json` 格式见 `references/mapping-rules.md` 末节。

### 4. 读报告,处理「无法迁移」的数据

`migration-report.md` 的结构:

- **迁移成功明细**:每笔记了**映射依据**(哪个关键词命中哪个分类、收/支怎么转的 type)—— 方便逐条复核或推翻
- **新建的自定义分类**:哪些旧分类没命中系统 23 条,新建了什么,归到了哪个 type
- **降级迁移**:数据保留了但语义简化 —— 需要向用户说明
- **无法迁移**:完全没写入的行,附原始内容 —— 需要向用户说明,并建议人工补录
- **余额倒推差异**:期初余额倒推值异常大,通常意味着旧数据历史流水不完整 —— 需要用户确认

**不要自行猜测这些数据该怎么处理**,如实报告给用户,让用户决定。

> **转账类行默认不迁**:微信/支付宝的「不计收支」是账户间划转,但 CSV 通常**不披露对端账户**。
> gridly 的调拨必须 source/dest 成对,猜一个方向会凭空污染账户余额和月度汇总。
> 所以默认列入「无法迁移」,由用户决定补录方式。
> 确实想保留这条数据(降级成普通收支),用 `--config` 的 `"degrade_transfers": true`。

### 5. 交付

给用户:
- `gridly-migrated.sqlite` 的路径
- `migration-report.md` 的路径
- 报告里「无法迁移」和「降级迁移」的**摘要**(条数 + 代表性样本)
- 导入步骤(见下)

## 导入方式(告诉用户,不要代劳)

产物通过 app 内的「备份还原」导入:

1. 把 `gridly-migrated.sqlite` 传到手机
2. gridly → **我的** → **数据** → **备份还原** → **还原** → 选该文件
3. 确认后 app 自动退出,重新打开即可

> ⚠️ 还原会**覆盖** app 里现有数据。提醒用户先备份现有数据(app 内「备份」按钮)。

## 硬性约束(违反会导致 app 打不开或数据错乱)

| 约束 | 说明 |
|---|---|
| `PRAGMA user_version = 9` | 必须是 9,否则 app 触发 migration 建空表,数据全丢 |
| 时间戳是 **epoch 秒**(10 位) | 写成毫秒(13 位)→ app 显示「58792 年」 |
| 5 张表 + snake_case 列名 | 缺表/错列名 → drift 查询报错 |
| `transactions.account_id` NOT NULL | 每条流水必须挂账户 |
| `transactions.category_id` NOT NULL | 每条流水必须挂分类 |
| `amount` 为正 | 方向由 `type` 表达 |
| 引用完整 | drift **不生成 SQL 级 FK**,悬空引用不会被数据库拦,必须自己保证 |

完整契约见 `references/target-schema.md`。

## 常见坑

| 现象 | 原因 | 处理 |
|---|---|---|
| app 里日期显示 58792 年 | 时间戳写成毫秒 | 用 `int(dt.timestamp())`(秒) |
| app 里分类图标颜色不对 | 系统分类的 icon/color 没按当前代码写 | 跑迁移脚本即可(脚本内嵌最新种子数据) |
| 导入后数据看着对但余额不对 | 旧数据的「余额」是当前余额,不是期初余额 | 脚本会自动倒推;差异大时看报告的「余额倒推差异」段 |
| 投资/定投算进了月度支出 | 分类被归成 `expense` | 分类名含「投资/基金/理财/定投」应归 `cat.type='investment'`(脚本已处理) |
| 转账变成普通收入/支出 | 推不出目标账户 | 脚本降级处理并记入报告;若旧数据有「转入账户」列,用 `--config` 指定 `dest_account` |
| Excel 打开 CSV 乱码 | 缺 BOM | 脚本输出带 UTF-8 BOM |

## 校验产物(交付前跑一遍)

```bash
DB=gridly-migrated.sqlite
sqlite3 "$DB" "PRAGMA user_version;"                                    # 9
sqlite3 "$DB" "SELECT datetime(MAX(occurred_at),'unixepoch') FROM transactions;"  # 2020+ 年
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions t LEFT JOIN categories c ON t.category_id=c.id WHERE c.id IS NULL;"  # 0
sqlite3 "$DB" "SELECT COUNT(*) FROM transactions WHERE amount < 0;"     # 0
```

脚本内置了 10 项自检,**全过才算完成**。

## 参考

- `references/target-schema.md` — 目标 schema 契约(表结构、枚举、种子数据、自检清单)
- `references/mapping-rules.md` — 来源格式识别、分类/账户映射规则、config.json 格式
- `references/seed_data.json` — 系统预置分类/资产(脚本自动读取)

## 维护(改 gridly schema 时)

`references/seed_data.json` 由脚本从 gridly 源码生成,**不要手改**:

```bash
python3 <SKILL_DIR>/scripts/regenerate_seed.py \
  --repo <gridly 仓库路径> \
  --out <SKILL_DIR>/references/seed_data.json
```

gridly 的 DB schema 一改,这三处要同步:
1. `references/target-schema.md` — 目标 DDL / 枚举 / 自检清单
2. `references/seed_data.json` — 跑上面的脚本重新生成
3. `scripts/build_migrated_db.py` 的 `SCHEMA_VERSION` 常量

漏了会让迁移产物的 `user_version` 对不上,app 导入后触发 migration 把数据冲掉。

## Windows (win32) platform notes

脚本只依赖 Python 标准库,macOS / Linux / Windows 都能跑。Windows 下:

```powershell
# 查看源文件前 30 行(判断表头位置)
Get-Content <源文件> -TotalCount 30

# 跑迁移
python <SKILL_DIR>\scripts\build_migrated_db.py `
  --source <源文件> `
  --out gridly-migrated.sqlite `
  --report migration-report.md

# 校验产物
sqlite3 gridly-migrated.sqlite "PRAGMA user_version;"
```

注意:
- 路径用反斜杠或正斜杠都行,传给 `--source` 的参数加引号
- 脚本会自动探测源文件编码(UTF-8 / GB18030 / GBK / Big5),中文账单乱码时不用额外处理
- `sqlite3` CLI 在 Windows 上可能没装,此时可跳过手工校验步骤 —— 脚本内置的 10 项自检已覆盖同样的检查
