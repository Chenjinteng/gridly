# 开发路线图

> 研发阶段元信息 —— 仅给 contributor / 维护者看。
> README 只放用户面内容,链接回这里。

---

## 📋 当前阶段

### v0.1.0 · 完整可用 ✅

- ✅ 工程骨架 + Drift/SQLite + Riverpod Provider 体系
- ✅ 5 Tab(首页 / 流水 / 记一笔 / 报表 / 我的)
- ✅ 流水(按日分组 + 月度汇总卡)
- ✅ 记一笔(类型切换 + 表达式计算器 + 分类选择 + 备注 + **可选日期**)
- ✅ 报表(分类圆环 / 月度趋势 / Top 10 / 月度汇总卡)
- ✅ 我的(预算 + 分类管理 + 关于 + 主题切换 + CSV 导出 + 清空数据)
- ✅ 17 个语义化 Material Icons
- ✅ 自定义分类(增 / 改 / 删,30+ 图标 + 16 色可选)
- ✅ 预算告警(月度预算 + 进度条 + 状态颜色)
- ✅ Material 3 + Light/Dark 双主题 + 16×16 格子纸背景
- ✅ LOGO 套装(GridlyMark 2×2 + -8° 旋转 + 横排 + 竖排)
- ✅ 千分位逗号(intl `NumberFormat`)
- ✅ 月度汇总 Excel 工作表风格(顶部 sheet title + 金色下边 + 大数字 + 收入支出 cell)

### v0.2.0 阶段 1 · 报表增强 ✅

- ✅ 报表 Top 10(固定 10 行 + 不足留白 + 不可滚动)
- ✅ 日均支出
- ✅ 预算文案"还剩 ¥xxxx"
- ✅ 分类色差异化(支付宝语义色风格 — 餐饮橙 / 交通蓝 / 通讯青 / 教育紫 ...)
- ✅ 趋势图去除网格线
- ✅ 流水页加查询筛选(类型 / 月份 / 分类 / 关键字)

### v0.2.0.x · polish 与体验优化 ✅

- ✅ 流水筛选改 3 个 dropdown 弹层(类型 / 月份 / 分类)+ 分类多选(OR)+ 一键清空按钮
- ✅ 报表月份选择合并到"本月"段内嵌 chevron(去掉独立 dropdown 按钮)
- ✅ 月份 sheet 加"回到本月"快捷按钮
- ✅ 趋势图 tooltip 浮点尾数修复(`25420.7600000002` → `25,420.76`)
- ✅ 启动屏 LOGO 统一用 GridlyMark widget(不再用 Stack + Positioned 简化版)
- ✅ 首页极简化(删"最近 5 条流水",LOGO + 产品名居中 + 月度汇总 + 预算垂直居中)
- ✅ 月度汇总金额可一键隐藏(防偷窥 / 截图分享)
- ✅ 预算卡金额也支持隐藏(状态文字简化成百分比)
- ✅ 设置页加"显示金额"持久化开关(SharedPreferences)
- ✅ 记一笔支持选过去日期(适配一周一记场景)
- ✅ 流水 sheet 点"全部"重置真修(`_AllPicked` sentinel 严格区分 dismiss / 全部 / 选具体)
- ✅ 系统预置分类 color 启动时同步到代码最新值(`syncCategoryColors()`)
- ✅ 分类图标扩充到 30+ 个(按餐饮 / 交通 / 购物 / 居住 / 通讯 / 医疗 / 教育 / 娱乐 / 美妆 / 健身旅行 / 收入 分组)
- ✅ 分类颜色选项扩充到 16 个(12 调色板 + 4 高频语义色)
- ✅ 滑动删除改两段式(滑开按钮 → 手动点,避免一划即删的生硬)
- ✅ AGPL-3.0 开源协议(强 copyleft,商业使用受限)
- ✅ README 拆分:研发内容(本文档 / DEV.md)从 README 移走

### v0.3.0 · 分类预算精细化 ✅(2026-10-12 完成)

预算从单总额度 + 首页进度条,扩展到按分类子额度分配 + 共享剩余池 + 多圈超额圆环 + 全屏配置路由。详细见 [`DEV.md`](DEV.md) D27-D30。

- ✅ 月度预算总额度(SharedPreferences) + 分类子额度(Drift `CategoryBudgets` 表)
- ✅ 共享剩余池 = 总额度 − 已配置分类子额度总和(未配置分类共享)
- ✅ BudgetSheet UI:总额度输入 + 分类预算列表(按需添加)+ 共享池提示 + 三档超额色
- ✅ 自绘 `_AmountDialog` 入金额(ColorOS 风格 teal icon + 大字号 + 自绘按钮)
- ✅ stats 本月维度加预算 widget:圆环 + 双行图例 + 多圈超额(`AnimatedOverBudgetChart`)
- ✅ 圆环 viewport-aware 触发入场(滚到再开始,2000ms aquaIn)
- ✅ 数字加载动画(TweenAnimationBuilder 0 → 实际)
- ✅ 4 阶色阶:< 80% teal / 80-100% warning 黄 / > 100% error 红(分类预算);超额 1-2x / 2-3x / 3x+ 4 阶递进(主圆环)
- ✅ 月度预算改全屏路由(`/settings/budget`,不再弹 sheet 解决掉帧)
- ✅ `_pendingDeletions: Set<int>` 跟踪显式 X 删除,保存时真删 DB(修 X 删除不生效 bug)
- ✅ 共享池说明行(已分配 X · 共享池 Y),不展示重复"剩余/总额度"中段
- ✅ push 子页过渡 360ms(slide-up 24px + fade 前 30% 完成,消除背景残影)

### v0.2.0 阶段 2 · 多账户 ✅(2026-10-14 完成)

基础 P0-P3 阶段:
- ✅ 6 段账户类型 enum(`cash_flow` / `investment` / `benefit` / `receivable` / `fixed_asset` / `other`)
- ✅ `assets` 表(Drift)+ `AssetRepository`(CRUD + 排序 + 默认账户)
- ✅ 流水绑定账户维度(`transactions.accountId` NOT NULL,FK → assets)
- ✅ 资产页(`/assets`)+ 资产汇总卡(总资产 + 6 段余额)
- ✅ 实时余额计算(`assetBalancesProvider` = `initialBalance` + 流水净增量)
- ✅ 现金调拨(单 accountId,不算月度收支)
- ✅ 资产 `includeInTransactions` 开关(true / false)
- ✅ 默认账户 `isDefault`(cash_flow 段"日常流水默认账户"标记)

v0.3.5 增量(见下):投资场景三段拆分、调拨方向修正、6 段色重做、流水 tile 重构、余额校验、source/dest 双账户 chip、不计入流水 chip 等。

---

### v0.3.5 · 资产 + 收支重构 ✅(2026-10-15 完成)

**目标**:投资 record 走完整 schema(投入/收益/调拨三段)+ listTile 视觉重构 + 6 段色 token 化 + 报表口径只算 cash_flow 收支 + 还款虚拟分类入支出饼图 + Top 10 include 现金→债务调拨 + range_summary 加同比上月/去年提示 + 本年维度同比去年整年 + 报表支出口径放宽含现金→债务调拨(跟首页对齐) + 报表加 4 张卡(类别对比/周几支出/储蓄率/支付账户) + viewport-aware 入场动画 + 柱状图 tap 选柱虚线 + BarChart 抽到共享 AnimatedBarChart widget(图表库雏形) + ChartCard 容器 + PieChartCard 圆环+图例 wrapper + 5 个 widget 应用 ChartCard + top_expenses DefaultTabController 上提 + maxY + niceInterval 算法下沉到共享 AnimatedBarChart(修 2 个柱状图 Y 轴顶部小数 label 跟 0 重叠 bug) + 去储蓄率卡(跟 RangeSummary 重复) + 支付账户按 index 取固定 6 色 palette(原 asset.color 全同色看不出区别) + 支付账户恢复 viewport-aware 圆环动画(跟本月预算对齐) + range_summary footer 左对齐加当月储蓄率(跟同比提示共用一行) + 3 张柱状图合并成"消费趋势"tabbed 模块(每日 / 类别 / 周几) + 2 张环形图合并成"支出分析"tabbed 模块(分类 / 账户,原 D64.11 名"支付分析",D64.16 user UAT 改名) + 支出分析 tab body 抽 PieChartContent 去嵌套 chart 修 overflow + 支出分析 tab body 改 IntrinsicHeight 自适应高度(少 item 留白从 68dp 降到 44dp) + 支出分析 tab body 回退 SizedBox(220) 修 IntrinsicHeight 红屏 + 支出分析 legend 紧凑(vertical:2 + fontSize:12) + 可滚动(>8 项 SingleChildScrollView,圆环仍 take(8) 视觉清爽) + 日期选择器默认不能选未来日期(lastDate 默认 today + 右箭头在 lastDate 月份禁用) + raw MaterialPageRoute 页面加 PopScope 修 Android 返回键退出 app(advanced_filter_page / asset_form_page,D64.18 兜底 D64.20 改 go_router 真修) + 全量 back 键路径审计无遗漏(D64.19 覆盖 4 tab 主页 / go_router pushed / raw Navigator pushed / showModalBottomSheet / showDialog 5 类入口)+ D64.20 back 键真修:raw Navigator.push → context.push(go_router 路线)+ 删 PopScope + showModalBottomSheet 加 useRootNavigator: false(ledger pickers / CSV export),根因是 raw push 页面在 shell sub-navigator 上 go_router._findCurrentNavigator 找不到 → back 键退 app + D64.21 全年消费趋势:schema v7→v8 加 monthly_budgets 表(总额度按月历史)+ MonthlyBudgetNotifier 双写 SharedPrefs + 表 + 新 budgetHistoryProvider + AnimatedBarChart 支持负轴(D64.21c,结余 / 预算可能负)+ consumption_trend 加 range-aware 切换本年 3 tab(收支 / 结余 / 预算,跟本月 3 tab 每日 / 类别 / 周几 不同)+ D64.22 全年 3 tab X 轴稀疏化到 1 / 6 / 12 月 + D64.23 收支 tab 双柱改细柱(barWidth 8 → 5,跟月度每日同款)+ D64.24 预算 tab 增加当月实际支出双柱对比(预算 teal + 实支红,看超支)+ D64.25 新增全年 12 月储蓄率走势 tab(储蓄 = (income - expense) / income,百分比走势,负值用 D64.21c 负轴)+ D64.26 撤回 D64.25 储蓄 tab(消费趋势恢复 3 tab,储蓄 tab 太挤+折线图比离散柱更合适走独立模块)+ D64.27 新增 AnimatedLineChart 共享 widget(422 行,镜像 AnimatedBarChart API,跟共享 BarChart 同设计思路)+ 储蓄走势折线图模块(stats_page 末尾,本年专属,12 月储蓄率走势,节点色正/负区分)+ D64.28 新增按资产 6 段分析模块(本年专属,cash_flow / investment / benefit / receivable / fixed_asset / other 6 段分布,可视化跟 SavingsTrend 并列)+ D64.29 修储蓄走势 Y 轴整数 label + nice interval(AnimatedLineChart 加 nice interval 镜像 AnimatedBarChart D64.21c,加 axisLabelBuilder 回调默认回落 Formatters.amount,SavingsTrend 传 v.toStringAsFixed(0) 整数百分比,chart height 220→260)+ D64.30 修 BudgetOverviewChart 月份跟随(statsWindowProvider 联动 statsCustomMonthProvider,provider 分二:当月 SharedPreferences 单值,其它月 monthly_budgets 表,title 跟月份变 '本月预算' / 'X 年 X 月 预算')。+ D64.26 撤回 D64.25 储蓄 tab(消费趋势恢复 3 tab,储蓄 tab 太挤+折线图比离散柱更合适走独立模块)+ D64.27 新增 AnimatedLineChart 共享 widget(422 行,镜像 AnimatedBarChart API,跟共享 BarChart 同设计思路)+ 储蓄走势折线图模块(stats_page 末尾,本年专属,12 月储蓄率走势,节点色正/负区分)+ D64.28 新增按资产 6 段分析模块(本年专属,cash_flow / investment / benefit / receivable / fixed_asset / other 6 段分布,可视化跟 SavingsTrend 并列)+ D64.29 修储蓄走势 Y 轴整数 label + nice interval(AnimatedLineChart 加 nice interval 镜像 AnimatedBarChart D64.21c,加 axisLabelBuilder 回调默认回落 Formatters.amount,SavingsTrend 传 v.toStringAsFixed(0) 整数百分比,chart height 220→260)+ D64.30 修 BudgetOverviewChart 月份跟随(statsWindowProvider 联动 statsCustomMonthProvider,provider 分二:当月 SharedPreferences 单值,其它月 monthly_budgets 表,title 跟月份变 '本月预算' / 'X 年 X 月 预算')+ D64.32 净资产卡重排(标题'总资产'→'净资产',5 段真资产在前 → 白色横线 → 债务末尾 → 白色横线 → '总资产' 小字备注,口径切到'我实际拥有 vs 含 receivable 总额')+ D64.33 雷达图 6 维 → 5 维(摘出 receivable,跟净资产卡 5 段真资产统一语义)+ D64.34 雷达图 trailing 删'正负值都反映'(5 维后 cash_flow 不再有花呗欠款导致的负值,文案语义不成立)+ D64.35 seed 调 receivable 净负(花呗 initial -8000 + 还花呗减半 + 借给老王 ⇗+12000,实测 receivable 总和 = -¥1,392,跟净资产卡'差额 = 我净欠的金额'语义一致)+ D64.36 净资产卡口径 v3:总资产 = 5 段真资产 sum(不含 receivable),末尾小字显示;负债 = max(0, -receivable);净资产 = 总资产 - 负债,大字显示 + D64.37 删除'按资产 6 段分析'模块(95%+ 走现金,6 柱条 4 柱是 0,user 选 A 方案直接删)+ D64.38 雷达图 5 角 label 加百分比 + 改 2 行布局(分母 = 5 段真资产 sum,跟净资产卡"总资产"口径一致)+ D64.39 储蓄走势触摸关闭 fl_chart 内置触摸(消除双重触摸路径,无 `tooltipItems/touchedSpots` 异常 + 虚线对齐 todo)+ D64.40 cash_flow 段 UI label "现金流" → "流动资金"(中心 `AppSegment.labelFor` 改 1 处 + 删 2 个重复 switch + 直接硬编码 3 处 + 注释统一)+ D64.41 资产 tile chip 行 Row→Wrap 修 71px 溢出(标准 Flutter 水平溢出→多行解法)+ D64.42 抽 `SwipeToActions` 共享 widget,资产 tile 复用流水滑动交互(`_SwipeToDelete` 私有 → public,跨 tile 类型统一滑动操作)+ D64.43 资产 tile 改 2 列布局 + 主题黑底色(`ListTile` → 自绘 `Row + Wraps`,内联 title/subtitle 紧凑;底色 ink,跟总览卡一致;滑动按钮高度不再被 trailing padding 拉高)+ D64.43.2 logo 56×56 大方块全占左边(跟流水卡片布局统一,占满 tile 高度 ~64px,asset 标识突出)。共 111 个 commit,详细设计决策见 [`DEV.md`](DEV.md) D32-D64.43.2。

#### 1. 投资 record 三段拆分(`transaction_form.dart`)

- ✅ 投入(_intent='input')→ DB `type='balance'` + 双账户(source=cash → dest=investment)
- ✅ 收益(_intent='output')→ DB `type='income'` + 单账户(只 accountId,无 destinationAccountId)
- ✅ 调拨(_intent='transfer')→ DB `type='balance'` + 双账户(任意 ↔ 任意,不限 type)
- ✅ 5 个 getter 拆分:`_type` / `_needsDualAccount` / `_needsCategory` / `_accountTypeFilter` / `_destinationTypeFilter`
- ✅ 投资分类不强制选(UI 隐藏,但 DB NOT NULL 字段需填,见 D32)
- ✅ 6 段资产类型 + 6 段资产分类 seed 投资 2 类('投资投入' / '投资收益',cat.type='investment')

#### 2. 关键 bug 修复

- ✅ **`balanceDeltaByAssetId` 调拨方向反 + dest 漏处理**(D33)
  - 修:balance 流水拆 source / dest 两次 group by
  - source `delta -= sum`(转出),dest `delta += sum`(转入)
  - 之前 source 累加 sum(用户看到的"中国银行转出 1000 但反 +1000"现象)
- ✅ **转出超额无校验**(D34)
  - save() 前 fetch source.cash_flow 余额,超过阻断
  - 投资账户 source 不校验(市值波动,user 自负责)
- ✅ **`_typeLabel` 漏 4 段翻译**(cash_flow / investment / benefit / receivable / fixed_asset / other 全 6 段)
- ✅ **投资 record 挂"餐饮"分类**(D32 cat fallback 用 `投资投入` / `投资收益` 替代 `_firstCategoryId`)

#### 3. 流水 tile 视觉重构(`transaction_tile.dart`)

- ✅ **去掉 inline `分类名 · 备注` 方案,改 2×2 矩阵布局**
  - 第 1 行:分类名(15sp w500)+ 金额(16sp w600)+ [不计入流水] chip
  - 第 2 行:备注(12sp onSurfaceVariant)+ 资产 chip(11sp onSurfaceVariant)
  - 高度统一,2 行(主体 + 辅助)
- ✅ **`_AccountBadge` 接受 `destinationAccountId`**(D36)
  - 投资 record 投入 / 调拨 → 显示 `[source chip] → [dest chip]`,中间 → 符号(AppGray.g400)
  - 现金 / 投资收益(单账户)→ 维持 1 chip
- ✅ **流水金额色 + 资产 chip 统一用段色**(D38)
  - 抽 `AppSegment.colorFor(asset.type)` 集中 6 段色查询
  - 流水页 + 资产页 + chip 全用同 token,跨页视觉一致
- ✅ **不计入流水 chip**:`cat.type='investment'` 或 `source.includeInTransactions=false` 显示
  - 跟 gridly 现有 `_TileChip` 风格一致(半透明 alpha 0.12 + 无边框 + 6px 圆角)
  - 跟 monthSummary / _DaySection 汇总过滤规则同步
- ✅ **去掉 `_AccountBadge` 内部 `Flexible` 嵌套**(被外层 `Expanded` 压成 0)
  - 改 `mainAxisSize.min` + `ConstrainedBox(maxWidth: 100)` 解决

#### 4. 6 段色 token 化(`app_colors.dart` + `asset_summary_card.dart` + `asset_tile.dart`)

- ✅ 新增 `AppSegment` token,集中 6 段色查询
- ✅ 6 段新色(拉大色相距离,避免撞色):
  - `cash_flow` 现金流 → `#0EA5E9` 亮蓝
  - `investment` 投资 → `#A855F7` 紫
  - `benefit` 福利 → `#EC4899` 粉
  - `receivable` 债权 → `#F59E0B` 橙
  - `fixed_asset` 不动产 → `#06B6D4` 青
  - `other` 其它 → `#71717A` 灰
- ✅ 流水金额色 + 资产 icon 色 + 资产汇总 chip 全部统一 token
- ✅ 删除 `asset_summary_card` / `asset_tile` 重复 switch

#### 5. 汇总过滤规则

- ✅ **monthSummary + _DaySection 排除**:
  - 投资 record(cat.type='investment')→ 永远不计入(投资本质资产内部流转)
  - source asset `includeInTransactions=false` → 不计入(user 在资产页关了开关)
  - 跟 tile [不计入流水] chip 同步规则
- ✅ 投资 record 仍在流水列表显示(可管理)但默认不计入月度 / 日结

#### 6. 弹层 + 流水 Picker polish

- ✅ 流水页 `_TypeRow` / `_MonthFilter` / `_CategoryFilter` 改 `DraggableScrollableSheet` 极值配置(`max=initial, min=0.0, snapSizes [0.0, X]`)
- ✅ 高级筛选 inline 展开 cap 240px(避免 8 项分类第 8 项切 5px 不可点)
- ✅ 切 cash_flow 支出 ↔ 收入 toggle 不再清空 `_accountId`(同 context 切,账户类型不变)
- ✅ 投资场景 toggle 跨段(input ↔ output ↔ transfer)仍清账户(避免残留 source/dest 错位)

#### 7. 已知遗留(下次清理)

- ⚠️ **ListTile + DecoratedBox 嵌套老异常**(跟 P18 无关,资产 / 分类管理页 ListTile 套了 DecoratedBox 导致 selectedColor 不可见)
  - 解决:`Material` 包 ListTile 或移除中间层 background color
  - 暂时放着,不影响功能
- ⚠️ **历史错数据**(用户在 P18 之前测试录入的流水,balanceDelta 错方向)
  - 解决:用户在资产页改 initialBalance 兜底
  - 不加自动数据迁移(测试数据由 user 自行处理)

---

## 📌 路线图

- **v0.1.0** ✅ 完整可用(5 Tab + 流水 + 记一笔 + 报表 + 我的)
- **v0.2.0 阶段 1** ✅ 报表增强(Top 10 + 日均 + 分类色 + 流水筛选)
- **v0.2.0.x** ✅ polish 与体验优化(20+ 项,见上文)
- **v0.3.0** ✅ 分类预算精细化(2026-10-12 完成,见上文)
- **v0.2.0 阶段 2** ✅ 多账户(2026-10-14 完成,见上文)
- **v0.3.5** ✅ 资产 + 收支重构(2026-10-15 完成,37 commits,见上文)
- **v0.4.0** 📋 i18n(英文 + 简繁中文)
- **v0.5.0** 📋 数据导出增强(JSON / Excel)
- **v0.5.5** 📋 局域网 Web 伴侣端(见 [`LAN_WEB.md`](LAN_WEB.md))
- **v0.6.0** 📋 备份 / 恢复(本地 + WebDAV)
- **v0.7.0** 📋 主题 dark 模式细节优化 + 深色 LOGO mark
- **v1.0.0** 📋 Android Play Store 上架准备(截图 / 描述 / 隐私政策 / 签名)

---

## ⚠️ 已知限制

- **iOS 端不做** —— 不安装 CocoaPods、不配置 iOS Simulator runtime、不打 IPA、不上架。工程骨架保留(`ios/` 目录),后续有需要再启动
- **macOS 仅供开发** —— Flutter desktop simulator 跑通即可,不做 macOS 端发布
- **Intel Mac** —— Flutter 3.x 还支持,4.x 之后会强制 Apple Silicon
- **第三方依赖无 pandas/openpyxl** —— Python 数据迁移脚本纯 stdlib(sqlite3 + csv)
- **Sheets "全部" 与 dismiss 区分** —— 用 `_AllPicked` + `_SheetDismissed` 两个 sentinel 严格分开"用户选了全部"(reset 默认值)和"用户 dismiss"(放弃)
- **金额可见性** —— 月度汇总 / 预算 / 收入 / 支出 / 日均的数字都受 `amountVisibilityProvider` 控制,设置页统一开关
- **滑动删除的视觉局限** —— 底层 Material 与 tile 同形状,完全打开时露出的 76px 区域是 Material 的"中间矩形 + 右圆角",Material 的左圆角被滑过去的 tile 几何上覆盖(无法完全避免)