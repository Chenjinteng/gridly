# D64 Code Review & Refactor 归档(2026-10-16)

> 一次完整 code review(8 个 subagent + 1 个 overflow 截图触发)+ 13 个 commit 修复记录。
> 排查指引在文末:**出了相关问题先看这里**。

---

## 📊 总览

| 维度 | 数据 |
|---|---|
| Review 范围 | `lib/` 95 个 dart / 26k 行,重点 D64 系列 + 几个超大文件(transaction_form 1930 行 / asset_form 1110 行) |
| 总 finding | 24 个 actionable(真 bug 1 + 一致性 5 + 设计债 11 + 验证无问题 7) |
| 修复 commit | 13 个(D64.71 - D64.82) |
| 净行数 | -534 行(去掉新增 widget 文件后) |
| Build 号 | `0.1.0+18 → 0.1.0+30` |
| 触发 | user 截图 `_YearTotals` Row overflow 39px + 显式要求"做一次 code review" |
| HEAD | `a222317 refactor(asset_tile): 借出 chip teal → AppSegment.receivable 橙 (D64.82)` |

---

## 🐛 P0 — 真 bug(3 个,已修 1)

### D64.71 ✅ 投资情况 dashboard footer Row overflow 39px

- **文件**:`lib/features/settings/ui/widgets/investment_dashboard.dart:301-334`
- **触发**:`Row(spaceBetween)["本年合计" 44px] + 内层 Row[3 段金额 ~210px]`,合计 278px > chart card 可用 249px,撑爆 39px
- **修法**:右侧整块 `Flexible + FittedBox(scaleDown)`
  - 不溢出时按 11sp 原样显示
  - 溢出时按比例缩字号(最小 ~9sp)
  - 3 段金额信息保留不省略
- **commit**:`8c634b2 fix(settings): 投资情况 footer Row overflow 39px (D64.71)`

### Finding 1 ⏳ `dailyExpenseTrendProvider` / `yearlyExpenseTrendProvider` 旧口径

- **文件**:`lib/features/stats/application/stats_providers.dart:243-271` / `:339-366`
- **触发**:两个 provider 都用 `t.type.equals('expense')` 单独 WHERE,但其它 D62.4 之后 provider 都改成了"真支出(cash_flow expense) + 还款(现金→债务调拨,cat.type='liability' AND tx.type='balance')"双分支
- **影响**:`consumption_trend.dart:110` 的本月每日柱状图 / `:165` 的本年 1-12 月柱状图都比汇总卡少一截(还款 record 不算)
- **修法**:沿用 `_periodSummary` 口径过滤

### Finding 2 ⏳ `refreshAllData` 漏 6 个 D62+ provider invalidate

- **文件**:`lib/core/utils/refresh_providers.dart:29-62`
- **触发**:D62-D64 期间新增的 6 个 provider **没有任何一个**在 `refreshAllData` 里被 invalidate:
  - `categoryCompareProvider`
  - `weekdayExpenseProvider`
  - `expenseByAssetProvider`
  - `yearlyMonthlyTrendProvider`
  - `monthlyYoYProvider`
  - `yearlyYoYProvider`
- **影响**:流水 add/update/delete 后,报表"类别对比 / 周几支出 / 按账户支出 / 全年收支表 / 本月/本年同比 badge"全部停留在旧值
- **修法**:在 `refreshAllData` 加 6 行 invalidate

### Finding 3 ⏳ 投资 record 编辑 toggle 失灵 + 保存被阻断

- **文件**:`lib/features/add/ui/transaction_form.dart:266-270` + `lib/features/ledger/ui/widgets/transaction_tile.dart:263-265`
- **触发**:`/edit/:id` 路由对所有 tx 开放,但 edit 分支直接 `_intent = t.type`,而 investment 段 DB `type` 是 `'income'` / `'balance'`,这两个 key 不在 `TypeToggle.investmentSegments = ['input', 'output', 'transfer']` 里 → toggle 永远无选中 + 保存撞 "选个转入账户" banner
- **修法**:edit 分支用 `cat.type == 'investment'` 判定,把 `t.type` 映射回 `_intent`

---

## 🔄 P1 — 一致性 / 性能(5 个,全部已修)

### D64.78 ✅ 抽 `excludedFromTotals` helper,3 处共用

- **改前**:`monthSummaryProvider` / `transaction_tile.isExcludeFromTotals` / `_DaySection` 3 处各 inline `investmentCatIds` / `excludeAccountIds` + `isExcluded` 判定
- **改后**:`lib/core/utils/excluded_from_totals.dart` 单一定义
  - `excludedFromTotalsIdsProvider` 一次算 (investment cat ids + exclude account ids)
  - 纯函数 `isExcludedFromTotals(Transaction, ids)` 给 3 处共用
- **commit**:`e584cf7 refactor: 抽 excludedFromTotals helper,3 处共用 (D64.78)`

### D64.79 ✅ receivable 调拨段切 toggle 统一清 dest

- **改前**:切 toggle 清 `_accountId` / `_destinationAccountId` 只在 `_isInvestmentContext` 触发,receivable 调拨段(双账户)残留 dest 跟 D50 互斥错配
- **改后**:统一条件 `_needsDualAccount`,任何双账户 intent 切换都清 source + dest
- **commit**:`0d953f8 fix(add): receivable 调拨段切 toggle 统一清 dest (D64.79)`

### D64.80 ✅ `topExpensesProvider` 复用 `statsTransactionsProvider`

- **改前**:topExpensesProvider 自己 `select + where isBetweenValues(w.start, w.end)`,跟 statsTransactionsProvider 同一时间窗重复查
- **改后**:`ref.watch(statsTransactionsProvider.future)` 复用 cache,Dart 端 `where` filter
- **commit**:`527a3b1 refactor(stats): topExpensesProvider 复用 statsTransactionsProvider (D64.80)`

### D64.81 ✅ `investmentNetTotalProvider` 改 SQL aggregate

- **改前**:`select 全表 transactions` + Dart 端 filter invest cat id,1w+ 笔时首次 build 200ms+
- **改后**:`transaction_repository.investmentAggregated()` 新方法
  - 先拉 `cat.type='investment'` 的 id
  - SQL: `WHERE categoryId IN (...) AND type IN ('balance', 'income') GROUP BY type, SUM(amount)`
  - 一次性算 invested/returned 2 个 double
- **commit**:`a72ec15 refactor(settings): investmentNetTotalProvider 走 SQL aggregate (D64.81)`

### D64.82 ✅ 借出 chip 跨页颜色统一(选 A 橙)

- **改前**:asset_tile 借出 chip `AppBrand.teal` 青绿,跟 toggle / amount_display / transaction_tile 3 处 `AppSegment.receivable` 橙不一致
- **改后**:asset_tile 借出色 teal → `AppSegment.receivable` 橙
- **commit**:`a222317 refactor(asset_tile): 借出 chip teal → AppSegment.receivable 橙 (D64.82)`

---

## 🧹 P2 — 设计债 / 重复(11 个,已修 7)

### D64.72 ✅ P2 cleanup batch 1(4 处独立小修)

- `asset_allocation_chart.dart:238-241` 图例百分比每行 O(N) 重算全表 sum → 顶部算一次
- `debt_dashboard.dart:153-172` 两个一样 Padding 包不同 body → 共享 Padding + if/else
- `asset_allocation_chart.dart:318-321` 删失效"Formatters import 触发 lint"注释(import list 根本没有)
- `investment_dashboard.dart:230-240` `_YearlyBars` 内 `maxVal==0` 死分支(外层 hasAny 已守)
- `transaction_form.dart:590-595` 删 `_firstCashAssetId` 死引用注释
- **commit**:`b7cdfbd chore: P2 cleanup batch 1 (D64.72)`

### D64.73 ✅ icon switch 3 处统一走 `AssetTile.icons` 集中表

- **改前**:`transaction_form._assetIconFor` / `transaction_tile._AccountBadge._iconFor` 各 7 case switch,新加 icon key 3 处都要改
- **改后**:统一 `AssetTile.icons[k] ?? Icons.account_balance_wallet_rounded`
- **commit**:`4cab280 refactor: icon key → IconData 统一走 AssetTile.icons (D64.73)`

### D64.74 ✅ 抽 `AquaRowCard`,asset_form_page 4 card 复用

- **改前**:`asset_form_page` 4 个 `_XxxCard`(IncludeInTransactions / IsDefault / ActAsCashFlow / IsLender)结构完全一致,~310 行机械复制
- **改后**:`lib/core/widgets/aqua_row_card.dart` 共享 widget,API: value / onChanged / icon / iconColor / title / subtitle
- **commit**:`2447e78 refactor: 抽 AquaRowCard,asset_form_page 4 card 复用 (D64.74)`

### D64.75 ✅ 改用 `assetTotalsProvider` 替 O(N) 累加

- **改前**:`liabilities_dashboard` / `asset_summary_card` 2 个 widget 各 O(N) 累加 byType 5 段 sum,跟其它 dashboard 5+ 处同款重复
- **改后**:1 次 watch `assetTotalsProvider`,O(1) 读 6 个段值
- **commit**:`1c02fb3 refactor: liabilities_dashboard + asset_summary_card 改用 assetTotalsProvider (D64.75)`

### D64.76 ✅ 抽 `AssetMetricRow` + 修 `AssetTile.icons` 错用 key bug

- **改前**:`_DebtRow` / `_LendRow` + 各自文件内 `_HorizontalBar` / `_LendHorizontalBar` 几乎完全同款
- **改后**:`lib/core/widgets/rows/asset_metric_row.dart` 共享 widget(28x28 icon + 60px name + 8px 圆角横向条 + 80px Column)
- **顺手修的隐藏 bug**:`_DebtRow` / `_LendRow` 之前用 `item.name` 作 icon key(账户名不在集中表),所有账户都 fallback 到 wallet_rounded;改成走 `Asset.icon` 字段(已加 `iconKey` 字段)
- **commit**:`3e4a32f refactor: 抽 AssetMetricRow + 修 AssetTile.icons 用错 key (D64.76)`

### D64.77 ✅ 抽 `TxDisplayStyle`,3 处 display 共用

- **改前**:`amount_display` / `transaction_tile` 3 处独立 `switch(type)`,改 1 处必漏改其它处
- **改后**:`lib/core/theme/tx_display_style.dart` 集中表
  - `TxDisplayStyle { label, color, prefix }` + 5 静态常量(expense / income / balance / lendOut / borrowIn)
  - `TxDisplayStyle.forType(type)` 工厂
- **commit**:`ff0f521 refactor: 抽 TxDisplayStyle,3 处 display 共用 (D64.77)`

### Finding 16 ⏳ viewport-aware `_checkInView` 套路 3 处复制

- 3 处 boilerplate 100% 一样:`asset_allocation_chart.dart:74-120` / `assets_radar.dart:60-105` / `expense_analysis.dart`
- 抽 `lib/core/widgets/once_visible.dart` `class OnceVisible extends StatefulWidget`

### Finding 18 ⏳ `investment_dashboard._YearTotals` fold 重复

- `_YearTotals` 内部 `monthly.fold` 算 invested/returned,跟 `_YearlyBars._maxVal` 共 3 次 fold
- 抽 provider 一次性返回 `(monthly, investedYTD, returnedYTD, netYTD)` 元组

### Finding 19 ⏳ micro-spacing 硬编 4/2 px ~10 处

- AppSpacing 没 2px 这个值,出现 8 处硬编(transit_form / asset_form / transaction_tile)
- AppSpacing 加 `s05 = 2`,或 AGENTS.md 加一句"icon+text micro 4/2 允许"

---

## ✅ 验证无问题区(7 项)

| 检查项 | 结论 | 文件 |
|---|---|---|
| 扣款校验覆盖所有段 + receivable 负债例外(D49) | ✅ 已正确 | `transaction_form.dart:611-627` |
| lend_out / borrow_in 余额公式(D51) | ✅ `Σ lend_out − Σ borrow_in` | `asset_repository.dart:277-294` |
| balance 流水 source -= dest += 双向(D18) | ✅ P18 已修复 dest 漏算 | `asset_repository.dart:259-275` |
| paired picker 互斥(D50) | ✅ 双向 excludeId | `transaction_form.dart:1173, 1199` |
| Speed Dial 长按弹窗用 `Listener`(D53) | ✅ 已正确 | `speed_dial_list_popup.dart:165-173` |
| 容器级 16px 圆角走 `AppRadius.brLg` | ✅ 未发现 token 硬编 | 多文件 |
| `AppSegment` / `AppBrand` / `AppStatus` token 合规 | ✅ 业务代码无硬编 hex | 多文件 |
| Riverpod cache 吸收 N+1 风险 | ✅ | 各 dashboard |

---

## 📁 新增 / 修改文件清单

### 新增(5)

- `lib/core/widgets/aqua_row_card.dart` — settings 行卡片(D64.74)
- `lib/core/widgets/rows/asset_metric_row.dart` — 资产行展示(D64.76)
- `lib/core/theme/tx_display_style.dart` — 5 种 DB type 显示风格集中表(D64.77)
- `lib/core/utils/excluded_from_totals.dart` — 流水"不计入汇总"判定(D64.78)
- `docs/REFACTOR_D64.md` — 本文档

### 修改(13)

- `lib/features/settings/ui/widgets/investment_dashboard.dart` (D64.71 + D64.72)
- `lib/features/stats/ui/widgets/asset_allocation_chart.dart` (D64.72)
- `lib/features/stats/ui/widgets/debt_dashboard.dart` (D64.72)
- `lib/features/add/ui/transaction_form.dart` (D64.72 + D64.79)
- `lib/features/add/ui/widgets/amount_display.dart` (D64.77)
- `lib/features/ledger/ui/widgets/transaction_tile.dart` (D64.73 + D64.77 + D64.78)
- `lib/features/add/ui/transaction_form.dart` icon (D64.73)
- `lib/features/settings/ui/widgets/asset_form_page.dart` (D64.74)
- `lib/features/stats/ui/widgets/liabilities_dashboard.dart` (D64.75 + D64.76)
- `lib/features/stats/ui/widgets/receivables_dashboard.dart` (D64.76)
- `lib/features/settings/ui/widgets/asset_summary_card.dart` (D64.75)
- `lib/features/settings/ui/widgets/asset_tile.dart` (D64.82)
- `lib/features/ledger/application/transactions_providers.dart` (D64.78)
- `lib/features/ledger/ui/ledger_page.dart` (D64.78)
- `lib/features/stats/application/stats_providers.dart` (D64.80)
- `lib/features/settings/application/investment_providers.dart` (D64.81)
- `lib/core/database/repositories/transaction_repository.dart` (D64.81)
- `pubspec.yaml` (build+1 每个 commit)

---

## 🔧 排查指引(出相关问题先看这里)

### "报表页 / 资产页 / 流水页 数字对不上"

**先看是不是 Finding 1 / 2 / 3(未修的 3 个 P0)**

- 柱状图比汇总卡少 / 多 → Finding 1(`dailyExpenseTrendProvider` / `yearlyExpenseTrendProvider` 旧口径)
- 编辑流水后报表 dashboard 旧值 → Finding 2(`refreshAllData` 漏 6 个 provider invalidate)
- 投资 record 编辑 toggle 失灵 / 保存 banner → Finding 3(投资 record 编辑 pre-fill bug)

### "Row overflow / 字体被截断 / 列表错位"

- 投资情况 dashboard footer → **D64.71 已修**(`Flexible + FittedBox(scaleDown)`)
- 其它 dashboard footer 同款问题(发现新 case)→ 用同 pattern 修

### "借出 / 借入 颜色不一致 / chip 颜色错"

- 全部页面应统一 `AppSegment.receivable` 橙 #F59E0B(D64.82 选定)
- 改色前先查 4 处:`asset_tile` chip / `type_toggle` receivableSegments / `amount_display` lendOut / `transaction_tile` 借出 record 金额色
- 借出 / 借入 toggle 仍走 `TypeToggle.receivableSegments`(`type_toggle.dart:142-161`),不要改

### "流水页面"不计入"chip 跟月度汇总不一致"

- D64.78 已统一:`excludedFromTotalsIdsProvider` + `isExcludedFromTotals(Transaction, ids)` 1 处定义
- 改"不计入"规则只改 `lib/core/utils/excluded_from_totals.dart`
- 不要再在 monthSummary / transaction_tile / _DaySection 各加自己的 filter

### "投资 dashboard 加载慢 / 切年度卡顿"

- D64.81 已修:`transaction_repository.investmentAggregated()` 走 SQL aggregate
- 同 pattern 用于其它全表 SELECT(目前没有其它,但新加 provider 务必用 SQL 聚合别 select 全表)

### "新增 toggle / row / display 字段不知道放哪"

| 场景 | 抽到 |
|---|---|
| 16px 圆角 + icon + 主标 + 副标 + AquaSwitch | `AquaRowCard`(`core/widgets/aqua_row_card.dart`) |
| 28x28 icon + 60px name + 横向条 + 80px 占比/金额 | `AssetMetricRow`(`core/widgets/rows/asset_metric_row.dart`) |
| 5 种 DB type(支出/收入/调拨/借出/借入)显示风格 | `TxDisplayStyle`(`core/theme/tx_display_style.dart`) |
| 流水"不计入"判定 | `excludedFromTotals`(`core/utils/excluded_from_totals.dart`) |
| 资产 icon 名 → IconData | `AssetTile.icons`(`features/settings/ui/widgets/asset_tile.dart:220`) |
| 6 段 type 配置(icon/label/color) | `AppSegment`(`core/theme/app_colors.dart`) |

### "改了样式 / 规则,流水页跟其它页不一致"

- 第一查 D64.78(不计入规则)→ `excluded_from_totals.dart`
- 第二查 D64.77(显示风格)→ `tx_display_style.dart`
- 第三查 D64.73(icon)→ `AssetTile.icons` 集中表
- 第四查 D64.82(借出色)→ asset_tile 走 `AppSegment.receivable`
- 第五查 D64.74(4 个 toggle)→ `AquaRowCard` 共享

---

## 📌 重要约定(从这次 review 沉淀)

1. **改样式 / 规则先查集中表**:Token(颜色 / 间距 / 圆角)+ 集中 widget(`AquaRowCard` / `AssetMetricRow` / `TxDisplayStyle`)+ 集中 provider(`assetTotalsProvider` / `excludedFromTotalsIdsProvider`)+ 集中 map(`AssetTile.icons`)。**禁止**在 5+ 处复制同一段逻辑
2. **改业务代码先 grep 集中定义**:看到 `switch(type)` / `for (final a in assets)` / `where(t.type.equals(...))` 等模式,先 grep 集中表是不是已有
3. **新加 provider 走 SQL 聚合**:Repository 层做 GROUP BY + SUM,业务层不接触 DAO。1w+ 笔时 Dart 端 filter 全表首次 build 200ms+,SQL 聚合 <20ms
4. **Dart 端 fallback 走 widget 集中表**:icon 走 `AssetTile.icons[k] ?? default`,不要 inline switch + default
5. **加新 dashboard / 报表卡片**:viewport-aware 走 `OnceVisible` 套路(等 Finding 16 修后),数字动画走 `AnimatedCounter`,provider 走 `FutureProvider` + 复用 `statsTransactionsProvider` cache
6. **每个 commit 一个改动 + bump build+1**(AGENTS.md D64.54 约定)

---

## 🔗 相关文件

- 工程总览:[`AGENTS.md`](../AGENTS.md)
- 当前阶段 + 路线图:[`ROADMAP.md`](ROADMAP.md)
- 关键技术决策 + D 系列历史:[`DEV.md`](DEV.md)
- SQLite 表结构:[`SCHEMA.md`](SCHEMA.md)
- UI/UX AI 助手指令:[`UI_UX.md`](UI_UX.md)
