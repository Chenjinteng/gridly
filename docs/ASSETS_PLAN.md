# 资产 + 收支重构规划

> **v0.3.5 草案** · 起稿 2026-10-12
> 状态:**待 user 完整 UAT 通过,按 P1 → P5 顺序推进**
> 关联:[`ROADMAP.md`](ROADMAP.md) · [`DEV.md`](DEV.md) · [`LAN_WEB.md`](LAN_WEB.md)

---

## 目标

把"资产"从 stats placeholder 升级成完整功能:管理账户、流水挂靠、收支同比、雷达图分布。同时把 stats 视角从 3 段简化成 2 段(收入结构简单,不需要独立视角)。

---

## 适用范围(已锁定)

- **资产结构**:两层(大类 4 段 enum + name free text),不建二级分类表
- **流水 type**:`expense` / `income` / `balance` 三选一,`balance` 走"动资产但不动月度收支"语义
- **accountId 必填** + FK 引用 Assets.id,预置 3 个账户兜底
- **StatsView**:`收支` / `资产` 2 段(原 3 段简化)
- **不引入新依赖**

---

## 关键决策(默认方案,无 user 拍板)

| 决策点 | 方案 | 理由 |
|---|---|---|
| 资产大类 | enum 4 段(`cash_flow` / `fixed_asset` / `liability` / `other`) | 4 大类覆盖 99% 场景,user 反馈"二级分类很烦" |
| 资产账户名 | free text(name 字段) | 招行/微信/公积金/期权账户直接打字,灵活 |
| 流水 type | 3 种 `expense` / `income` / `balance` | balance 用于公积金月供/期权/外借,不影响月度收支 |
| accountId 必填 | `NOT NULL` + FK 引用 Assets.id | 数据完整性,无空账户流水 |
| 预置账户 | 现金 / 银行卡 / 微信支付(全 `cash_flow`) | 兜底,老数据迁移统一指向"现金" |
| currentBalance 策略 | **不存盘,读时计算** + 内存 cache | 数据一致性强,无 balance 漂移 |
| StatsView 段数 | 3 段 → 2 段(`收支` / `资产`) | 收入结构简单,不需要独立视角 |
| 同比 | 月度汇总 3 个数(收入/支出/结余)各加箭头 + 百分比 | 不做更久(避免历史归档复杂度) |
| 雷达图 | fl_chart RadarChart 4 维(按大类) | 维度固定,数值差异大时备选 min radius / log scale |
| 收支公式 | 月度汇总 **排除 `balance`**,只算 expense + income | balance 走"动资产但不动月度收支"语义 |

---

## 数据公式

### 资产余额
```
balance(asset) = initialBalance
                - sum(expense 流水 amount)
                + sum(income 流水 amount)
                + sum(balance 流水 amount)   // 正负自定,正入负出
```

### 月度收支
```
monthly_expense  = sum(流水 amount WHERE type='expense' AND month=current)
monthly_income   = sum(流水 amount WHERE type='income'  AND month=current)
monthly_balance  = monthly_income - monthly_expense
```

`type='balance'` 流水:**不影响** monthly_expense / monthly_income,但**影响**对应资产的 currentBalance。

### 同比
```
expense_yoy = (monthly_expense_curr - monthly_expense_prev) / monthly_expense_prev
income_yoy  = (monthly_income_curr  - monthly_income_prev)  / monthly_income_prev
balance_yoy = (monthly_balance_curr - monthly_balance_prev) / monthly_balance_prev
```

---

## 6 个 P 阶段路线图

### ⭐ P1 · 数据层重构(2-3 天) — 推荐先做

**目标**:Assets 表 + transactions 改造 + 预置账户 + 老数据迁移,跑通"查 currentBalance"。

| 项 | 内容 |
|---|---|
| 新文件 | `lib/core/database/tables/assets.dart`<br>`lib/core/database/repositories/asset_repository.dart`<br>`lib/core/database/seeds/default_assets.dart`(3 个预置)<br>`lib/core/utils/asset_balance_provider.dart`(实时计算 currentBalance + 内存 cache) |
| 改文件 | `lib/core/database/app_database.dart`(`schemaVersion: 3` + `onUpgrade` createTable + transactions.accountId NOT NULL + FK)<br>`lib/core/database/tables/transactions.dart`(`type` 改宽 text 接受 'balance',`accountId` NOT NULL + FK) |
| 数据迁移 | `onUpgrade(from: 2, to: 3)`:<br>1. CREATE TABLE assets + 预置 3 行<br>2. UPDATE transactions SET accountId = (SELECT id FROM assets WHERE name='现金') WHERE accountId IS NULL<br>3. 校验所有 transactions.accountId NOT NULL |
| Repository API | `byType(String type)` / `byId(int id)` / `upsert(...)` / `delete(...)` / `toJson()` |
| Provider | `assetsProvider`(List<Asset>)+ `assetBalanceProvider(int id)`(实时算 balance)+ `assetsTotalByTypeProvider` |
| 工作量 | **2-3 天** |
| 验收 | ① schemaVersion 2→3 migration 跑通;② 预置 3 账户;③ 老流水 accountId 全部回填到"现金";④ 加几条 type='balance' 流水,资产 currentBalance 正确变化 |

> **P1 是关键风险点** — schemaVersion 3 迁移是破坏性变更,老用户升级不能崩。onUpgrade 失败兜底要严谨,加 dry-run 单元测试。

### P2 · 我的页资产 section(1-2 天)

**目标**:能在"我的"看到总资产 + 4 大类汇总,新增/编辑/删除账户。

| 项 | 内容 |
|---|---|
| 新文件 | `lib/features/settings/ui/assets_management_page.dart`(全屏路由,类比 budgetManagementPage)<br>`lib/features/settings/ui/widgets/asset_form_sheet.dart`(增/改账户 sheet)<br>`lib/features/settings/ui/widgets/asset_tile.dart`(资产列表 tile)<br>`lib/features/settings/ui/widgets/asset_summary_card.dart`(总资产 + 4 大类小汇总) |
| 改文件 | `lib/features/settings/ui/settings_page.dart`(加"资产" section 在"预算"和"数据"之间) |
| 路由 | `/settings/assets` 全屏 push(slide-up 24px + fade 360ms 跟其他子页一致) |
| 工作量 | **1-2 天** |
| 验收 | ① "我的"看到总资产 + 4 大类;② 新增/编辑/删除账户,实时反映到 stats 资产页;③ 删除账户时如已被流水引用,提示"先改引用" |

### P3 · 流水改造(1-2 天)

**目标**:流水 add/edit 加资产选择(必填)+ type 切换三选一(含 balance)。

| 项 | 内容 |
|---|---|
| 改文件 | `lib/features/add/ui/transaction_form.dart`(加资产选择器 + type toggle)<br>`lib/features/add/ui/widgets/transaction_form.dart`(选资产 chip + 余额徽章)<br>`lib/features/ledger/ui/widgets/transaction_tile.dart`(小角标显示资产 icon)<br>`lib/features/ledger/ui/widgets/ledger_filter_sheet.dart`(加"资产"筛选维度) |
| 业务规则 | add 流水中:type='balance' 时不计入"已花"或"收入",仅算资产余额变动(加 input 提示文案) |
| 兜底 | 没建账户前不允许保存流水(显示"请先在'我的'创建账户"提示) |
| 工作量 | **1-2 天** |
| 验收 | ① add 流水强制选资产;② type 三选一切换正常;③ balance 流水不在月度汇总出现,但影响对应资产余额 |

### P4 · 资产分布 + 雷达图(2-3 天)

**目标**:stats 资产视角完整(总资产 + 4 大类卡片 + 4 维雷达图),viewport-aware 触发。

| 项 | 内容 |
|---|---|
| 新文件 | `lib/features/stats/ui/widgets/assets_overview_chart.dart`(总资产 + 4 大类卡片,跟 `BudgetOverviewChart` 同款风格)<br>`lib/features/stats/ui/widgets/assets_radar.dart`(fl_chart RadarChart,4 维) |
| 改文件 | `lib/features/stats/ui/stats_page.dart`(移除 `_AssetsPlaceholder`,assets 视角用 `AssetsOverviewChart` + `AssetsRadar`) |
| 动画 | 跟 `BudgetOverviewChart` 一致:viewport-aware 触发(滚到再开始)+ 2000ms aquaIn 阻尼 |
| 雷达图维度 | 4 维:现金流 / 不动产 / 负债 / 其他,每维数值 = 该大类 currentBalance 总和(负债取绝对值) |
| 工作量 | **2-3 天** |
| 验收 | ① stats 资产视角不再 placeholder;② 总资产数跟"我的"资产页一致;③ 雷达图 4 维清晰;④ 滚到时动画流畅 |

### P5 · 收支重构 + 同比(1 天)

**目标**:stats 简化为 2 段(收支 / 资产),月度汇总加同比箭头,删 IncomePie + incomeByCategoryProvider。

| 项 | 内容 |
|---|---|
| 改文件 | `lib/features/stats/application/stats_providers.dart`(删 `incomeByCategoryProvider`,加 `monthlyYoYProvider`)<br>`lib/features/stats/ui/stats_page.dart`(`_CompactViewSegmented` 2 段,删 `StatsView.income`)<br>`lib/features/stats/ui/widgets/income_pie.dart`(**整个文件删掉**)<br>`lib/features/stats/ui/widgets/monthly_summary.dart`(同比箭头 + 百分比) |
| 同比 UI | 3 个数(收入/支出/结余)右侧 ▲▼ 箭头 + 百分比;零除边界:上月 0 改用绝对值 ± |
| 工作量 | **1 天** |
| 验收 | ① AppBar 2 段(收支/资产);② 月度汇总 3 个数带同比;③ `IncomePie` 文件已删,grep 确认无引用 |

### ⏸ 6 · 备份/恢复兼容(LAN_WEB 协同)

- 等 P1 跑通后,`AssetRepository.toJson()` + `TransactionRepository.toJson()` 配套给 LAN_WEB P2 API 用
- 不在 P1-P5 范围,LAN_WEB P2 阶段再做

---

## 工作量汇总

| 阶段 | 天 |
|---|---|
| P1 数据层 | 2-3 |
| P2 我的页资产 | 1-2 |
| P3 流水改造 | 1-2 |
| P4 资产分布 + 雷达 | 2-3 |
| P5 收支重构 + 同比 | 1 |
| **合计 MVP** | **7-11 天(约 1.5-2 周单兵)** |

里程碑命名:**v0.3.5 · 资产 + 收支重构**,插在 v0.3.0(分类预算)和 v0.2.0 阶段 2(多账户)之间——逻辑上 v0.3.5 是 v0.3.0 之后的多账户前置。

---

## 推进顺序

```
P1 (2-3 天)   →  UAT 验证 migration + 余额计算 → 通过后进 P2
P2 (1-2 天)   →  UAT 验证 CRUD + 总资产显示 → 通过后进 P3
P3 (1-2 天)   →  UAT 验证 流水 + 余额联动 → 通过后进 P4
P4 (2-3 天)   →  UAT 验证 雷达图 + 资产视角 → 通过后进 P5
P5 (1 天)     →  UAT 验证 2 段 segmented + 同比
```

不做大爆炸:每个 P 一个 feature branch + 多个小 commit,每个 P 结束你做 UAT 通过再开下一个。

---

## 关键风险

| # | 风险 | 缓解 |
|---|---|---|
| 1 | schemaVersion 2→3 migration 失败导致老用户升级崩 | onUpgrade 失败兜底(accountId 默认指向"现金"+ 提示用户);先在 dev DB 完整跑一遍 |
| 2 | `type='balance'` 流水误算月度汇总 | 多处校验(`monthlySummary` provider 加 `WHERE type != 'balance'`);单元测试覆盖 3 种 type 组合 |
| 3 | `accountId NOT NULL` 破坏老数据 | migration 时 UPDATE 所有 NULL 指向"现金"id;失败不让用户进 app(直接报错给 user 提示) |
| 4 | 雷达图 fl_chart 4 维数值差异大 | 加 min radius(0.05),数值 log scale 备选;先做线性 scale,数据多再调 |
| 5 | 资产 currentBalance 实时计算性能 | 内存 cache(`AssetBalanceProvider`),transactions 改动时 invalidate;正常 < 1000 条流水无感 |
| 6 | 删除账户时如已被流水引用 | FK constraint 阻止删除(参考分类管理)+ 提示"先把这些流水改到其他账户" |
| 7 | 删 `IncomePie` 后其他 widget 引用 | 全文 grep 确认无引用(类似 commit 99 删 `_AmountDialog` 的流程) |

---

## Open Questions(开工前 user 拍板)

- [ ] 资产 type 4 段 OK?(`cash_flow` / `fixed_asset` / `liability` / `other`)— 或者你想用 5 段 / 6 段?
- [ ] 预置账户 3 个 OK?(现金 / 银行卡 / 微信支付)— 或者想加 4-5 个?
- [ ] 同比范围只用"本月 vs 上月"OK?— 或者想加"本年 vs 去年"?
- [ ] 雷达图 4 维 OK?— 或者想加"总资产"中心点?
- [ ] `type='balance'` 的"动资产但不动月度收支"语义 OK?— 跟你的"公积金"用法一致吗?
- [ ] 路线图顺序 P1→P5 OK?— 或者想先做 P3 流水改造(P3 完成后用户就能立刻体验)?

---

## 历史决策

| 日期 | 决策 | 原因 |
|---|---|---|
| 2026-10-12 | 起稿 v0.3.5 规划 | stats 资产 placeholder 闲置,收入端也未规划;user 明确"先规划" + 财务领域不熟,需工程师给完整建议 |
| 2026-10-12 | 资产 type 4 段方案 | user 反馈"二级分类很烦",简化成 enum;4 段覆盖 99% 场景 |
| 2026-10-12 | 流水加 `balance` type | 公积金/期权/外借等"动资产但不算日常收支"的需求 |
| 2026-10-12 | 收支合并 stats 视角 | 收入结构简单(工资/兼职/外快),不需要 Top 10;改 2 段 + 同比 |
| 2026-10-12 | 文档放 `docs/ASSETS_PLAN.md` | 沿用 docs/ 大写短名约定 + 草案格式跟 LAN_WEB.md 保持一致 |
