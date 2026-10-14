# 工程参考

> 给 contributor / 协作者看的工程文档,README 只放用户面内容,链接回这里。

---

## 📦 目录结构

```
gridly/
├── lib/
│   ├── main.dart                            # 入口(seed + sync)
│   ├── app.dart                             # MaterialApp + 主题 + 路由
│   ├── core/
│   │   ├── theme/                           # ★ 配色 / 字体 / 圆角 / 间距 / ThemeData / LOGO 背景
│   │   ├── database/                        # Drift schema + repository
│   │   ├── router/                          # go_router
│   │   ├── settings/                        # 金额可见性等持久化设置
│   │   ├── utils/                           # Formatters / 预算 / refreshAllData helper
│   │   └── widgets/                         # GridlyMark(LOGO mark)
│   └── features/
│       ├── splash/                          # 启动屏(LOGO + 三色横条)
│       ├── shell/                           # 5 Tab 容器
│       ├── home/                            # 首页(LOGO + 产品名 + 月度汇总 + 预算)
│       ├── ledger/                          # 流水(查询筛选 dropdown + 按日分组 + 滑动删除)
│       ├── add/                             # 记一笔(选日期 + 计算器 + SaveBar)
│       ├── stats/                           # 报表(月份段 + 分类圆环 + Top 10 + 月度趋势)
│       └── settings/                        # 我的(主题 / 分类管理 / 隐私 / 预算 / 导出 / 关于)
├── assets/
│   └── images/logo/                         # GridlyMark + LOGO 横排 / 竖排
├── docs/                                    # 研发文档(ROADMAP + 本文件)
├── android/                                 # Android 原生工程
├── ios/                                     # iOS 原生工程(不维护)
├── pubspec.yaml
├── LICENSE                                  # AGPL-3.0 完整协议文本
└── README.md                                # 用户面入口
```

---

## 🎯 关键技术决策

| 维度 | 选型 | 理由 |
|---|---|---|
| 跨端框架 | Flutter 3.47 | 一套代码多端,Material 3 统一 |
| 状态管理 | Riverpod 2.x | 编译期安全 / 易测试 |
| 数据库 | Drift + SQLite | 本地优先,隐私敏感 |
| 路由 | go_router | 官方推荐,支持深链 |
| 图表 | fl_chart | 风格自由 |
| 持久化设置 | shared_preferences | 主题模式 + 金额可见性 |
| 隐私政策 | flutter_markdown | 关于页内嵌 Markdown 渲染 |
| 数据迁移 | Python stdlib | sqlite3 + csv,无第三方依赖 |
| 滑动删除 | 手写 Stack + Transform.translate | 不引入 flutter_slidable,避免新增依赖 |

---

## 🔑 设计决策记录(关键 D 系列)

| ID | 决策 | 原因 |
|---|---|---|
| D1-D15 | 历史决策 | 见早期 commit message |
| D16 | 支出文字色 teal → 红(`AppStatus.error`) | 警示感强,违反 THEME.md §3.5 反红绿色盲原则,用户坚持 |
| D17 | Top 10 改用 `Column`(非 ListView) | 固定 10 行 50px,不可滚动 |
| D18 | `Formatters.amount` 用 intl `NumberFormat('#,##0.00')` | 千分位 + 两位小数 |
| D19 | 数据迁移用 Python stdlib | 不依赖 pandas/openpyxl(本机环境约束) |
| D20 | GridlyMark 严格按 design.html `.logo3` CSS 复刻 | 2×2 + -8° 旋转 + 6.67% gap + 16.67% 圆角 |
| D21 | AppBar `actions` 留空,保存按钮统一在 SaveBar | 单一入口原则(同操作不重复) |
| D22 | 飞书导入一次性脚本(非功能) | 辅助历史数据迁移,非"做飞书导入"产品功能 |
| D23 | 流水删除三段迭代:长按 → 一划即删 → 两段式 | 反复修正的体验路径 |
| D24 | 滑动删除手写不引入 flutter_slidable | 控制依赖,Stack + AnimationController 够用 |
| D25 | `refreshAllData` helper 放 `lib/core/utils/` | 避免 ledger 模块反向依赖 stats 模块 |
| D26 | `amountVisibilityProvider` StateNotifier + SharedPreferences | 月度汇总 + 预算共用一个开关 |
| D27 | 月度预算分层持久化 | 总额度(SharedPreferences)+ 分类子额度(Drift `CategoryBudgets` 表,`schemaVersion: 2` + `onUpgrade` createTable) |
| D28 | 共享剩余池 = 总额度 − 已配置分类子额度总和 | 未配置分类共享这个池,UI 单独显示「已分配 X · 共享池 Y」 |
| D29 | `AnimatedOverBudgetChart` 接受 `value = 圈数` 而非占比 | multi-turn 圆环支持:`totalTurns > 1` 时 painter 累加 360° × totalTurns,实现转多圈 |
| D30 | push 子页过渡 360ms + fade `Interval(0.0, 0.3)` | 消除 480ms 全程 fade 透明度渐变时看到的"背景残影"——fade 前 30% 时间(108ms)就完成,后段时间只跑 slide 保留 aquaIn 重量感 |
| D31 | `_pendingDeletions: Set<int>` 跟踪显式 X 删除 | 修"`_pendingBudgets.remove` 后保存时该 catId 不进 toDelete 列表 → DB 不删"bug,`Set` 显式跟踪 + 保存时优先遍历 |
| D32 | 投资 record DB 分类 fallback 用 `'投资投入'` / `'投资收益'` 替代 `_firstCategoryId()` | 投资 record 走 DB schema `categoryId NOT NULL` 但 UI 隐藏分类选择器,不能 fallback 到 cash_flow 第一个分类(餐桌)导致投资 record 挂"餐饮"显示在流水里。seed 投资 2 类(cat.type='investment')+ transaction_form.dart `_firstCategoryId` 按 `_intent` 选名字 |
| D33 | `balanceDeltaByAssetId` 调拨流水拆 source / dest 两次 group by | 之前只按 `transactions.accountId` group by → 调拨 source 累加 sum(应 -=)+ destinationAccountId 完全没处理(dest 余额永远是 initialBalance)。修:balance 流水按 source(accountId) / dest(destinationAccountId)分别 group,source `delta -= sum`,dest `delta += sum`。现象:用户"中国银行转出 1000 但反 +1000,应该 -1000" |
| D34 | 转出类流水 `save()` 前 fetch source.cash_flow 余额校验 | 之前无校验,转出 1000 但账户只有 2.25 也保存成功。修:`_save()` 前 `repo.byId(_accountId!)` 拿 source asset,若 type='cash_flow' 校验 currentBalance ≥ 转出金额,不足阻断(banner)。投资账户 source 不校验(市值波动,user 自负责) |
| D35 | 投资 record 走 type='income' 单账户(无 destinationAccountId) | 收益本质账户自身增长,没有 source→dest 流向。投资收益 schema:DB `type='income'` + `accountId only` + `destinationAccountId=null`,跟 cash_flow 收入区分(投资 cat vs 现金 cat)。无 DB migration,复用现有 schema |
| D36 | `_AccountBadge` 接受 `destinationAccountId` 显示 source → dest 双账户 | 投资 record 投入 / 调拨是 source→dest 流向,只显示 1 个账户 user 不知道钱去哪。抽 `_SingleChip` 组件 + 中间 `Icons.arrow_forward_rounded` 11px AppGray.g400 箭头,`source/dest` chip 各 maxWidth=60 紧凑布局 |
| D37 | 流水 tile 改 2×2 矩阵布局(分类名+金额 / 备注+资产账号) | 之前 `[分类名] + [if 备注: SizedBox + 备注] + [账户 badge]` 单 Column,有无备注 tile 高度差 ~16px 不齐。改 Row 1(主体:`Expanded(分类名) + [chip?] + 金额`)+ Row 2(辅助:`Expanded(备注) + 资产 chip`),始终 2 行,高度统一。`crossAxisAlignment.center`(不是 baseline,不然 1sp 字体差抖动)。第 1 行加 `不计入流水` chip 占位 |
| D38 | 抽 `AppSegment` token 集中 6 段色查询 | 流水金额色 + `_AccountBadge` icon 色 + 资产汇总 chip 之前散落 3 处 switch / 重复写 `colorFor(type)`,改 1 处其它 2 处不跟变。`AppSegment.colorFor('cash_flow')` 统一查询 |
| D39 | 6 段色新方案(拉大色相距离) | 旧 cash_flow teal / investment gold / benefit 绿 / receivable 橙 / fixed_asset info 蓝 / other 灰,色相堆 green-yellow 区密集,撞色 + gold 跟"收入黄"重复。改:亮蓝 / 紫 / 粉 / 橙 / 青 / 灰,hue 分散。`AppBrand.gold #F5BC1F` 仍保留给 income semantic 色(支出红 / 收入黄语义不动) |
| D40 | 流水金额色 + 资产 icon 统一用 `AppSegment.colorFor(asset.type)` | 跨页视觉一致:流水页金额 + 资产 chip + 我的页资产汇总 3 处全部跟 record/accountId 对应段色。区别支出 / 收入靠 prefix 符号(`-¥555` vs `+¥100`)+ 分类色块(餐饮橙 / 工资金)。cash_flow 段所有 record 金额色 = `#0EA5E9` 亮蓝(包括支出红之前是分开的,现在统一蓝) |
| D41 | tile chip / monthSummary / `_DaySection` 同步 `isExcludeFromTotals` 规则 | 单一 source of truth 决定"是否计入汇总":`cat.type='investment'` OR `source.includeInTransactions=false`。3 处复用同一规则,避免漏改某处导致 UI 与汇总不一致。tile chip 是 user 视觉信号,monthSummary / `_DaySection` 是计算逻辑 |
| D42 | 投资记录"调拨 tip"判断从 `_type == 'balance'` 改 `_intent == 'transfer'` | P3 commit 原条件 `_type == 'balance'` 在 P18 前成立(只有 cash_flow 调拨 type='balance');P18 大改后投资"投入"(`_intent='input'`)和"调拨"(`_intent='transfer'`)都存 `type='balance'`,导致"投入"段被误显"调拨:动资产,不算月度收支"tip 误导成调拨。改用 `_intent='transfer'` 后,投入/收益段隐藏 tip,cash_flow 调拨跟投资调拨仍正常显示 |
| D43 | 福利 + 债权 段适配(跟投资同 pattern:2 段 + UI 隐藏 cat + fallback) | 福利段 1 cat(粉)/ 债权段原本 2 cat(股份期权 + 负债借贷)让 user 主动选 → user 推翻要求简化到 1 cat"负债"(同 AppCategory.liability #EF4444)。原因:1 段 1 内置 cat 优先(简化学),picker 选 2 cat 区分"股份期权 / 负债借贷"对 user 复杂度高、视觉 bug 多。DB enum 保留 'receivable' / 'benefit',UI 全走"负债" / "福利"单 label |
| D44 | toggle 切时不重置 cat(`_isReceivableContext` 例外) | D43 推翻后,`_actionRow` 需要在 receivable 段显示 1 cat(负债)chip,不能因为切 toggle 被清掉。在 toggle onChanged 加 `if (!_isReceivableContext) _categoryId = null` |
| D45 | `_actionRow` 查 cat 从 `allCategoriesProvider` 全表查(不依赖 `_intent` 维度) | 之前用 `categoriesByTypeProvider(_intent)` 只查"现金支出"cat,收不到多 context cat(投资/福利/债权)。改全表查,multi-context cat 视觉 chip 都能找到 |
| D46 | "清空所有数据"按钮实际清空 assets + UI 同步刷新 | 之前 `clearAllData()` 只清 transactions / categories / accounts,assets 表残存;`_confirmClearData` 也没 refresh,UI 看到老数据。修:`AppDatabase.clearAllData()` 加 `delete(assets).go()`,`_confirmClearData` 加 `refreshAllData(ref)`,alert / banner 文案补"资产"。D46 后 assets 表真清空,user 自建,不自动 seed 默认 3 账户 |
| D47 | 6 段 chip 颜色图标统一走 AppSegment(跨 3 页一致) | 之前 4 widget(报表 / 资产页 / 总览卡 / 新增账户)各自硬编码 icon / color / label,3 页不一致:报表用老色 `AppBrand.teal / gold / success / warning / info / g600`,资产页 label 走硬编码 `typeLabels` map,总览卡 `_TypeRow` 硬编码 icon + label,新增账户 `_TypeRadioList` 硬编码 `_options` 三元组 + `_colorFor` switch。`AppSegment` 扩 `labelFor / iconFor`,4 widget 全切,删硬编码。改一处生效全部 |
| D48 | 资产 icon picker 扩 47 个 icon + 8 组分组 | user 要丰富图标(支付品牌 / 加密 / 银行 / 票务)。加 13 个 brand letter chip(支付宝 支/微信 微/Google Pay G/ePay e + Bitcoin ₿/Ethereum Ξ/USDT ₮ + 招商 招/工行 工/建行 建/农行 农/中行 中)+ 1 个 Material apple icon(Apple Pay,避免空字母)+ 8 个 Material 票务(card_giftcard/confirmation_number/theater_comedy/restaurant/redeem/flight/train/local_activity)。`AssetTile.brandIcons` map + `BrandIconSpec` 公开类 + `renderIcon(key)` 统一入口(form picker + asset tile leading)。form picker 改 8 组分组 + 11px 小 label,避免 47 个 Wrap 滚动太长 |
| D48 v2 | 银行 5 家 → 1 家银联 + icon picker 扁平化(去分组 / 去子 label) | user 反馈两件事:(1) 银行太多反而要考虑更多,只留 1 家"银联 / UnionPay"(letter chip "银" + `#E21836` 银联红),其它 5 家(招/工/建/农/中)删除(2) "图标也不需要分类,不用指导用户,用户想用什么图标用什么图标"。删 `_iconSections (label, keys[])` 8 组结构,改回 `_iconKeys` 扁平 Wrap,43 个 icon 不分类不引导。系统不替用户决定选哪个,user 自由挑。 |
| D49 | 余额校验扩到所有非负债段(投资 / 福利 / 不动产 / 其它) | user 反馈"记一笔投资的页面,如果是调拨的话,如果原投资帐户的金额不够但也能转,这也是一个 bug"+ 原则"所有的记一笔的动作如果是从已有的资产进行扣款的话,都要进行校验,除了负债之后,其它的不能出现负数"。修:`_save()` 余额校验条件 `sourceAsset.type == 'cash_flow'` → `sourceAsset.type != 'receivable'`。P18 D34 当时故意放过 investment(考虑市值波动 user 自负责),user UAT 推翻 —— 任何扣款不允许出负数,"市值波动"是另一维度。负债 (receivable) 仍不校验:语义是"我欠的",扣到更负代表"我多欠了" |
| D50 | 调拨 source / dest 账户互斥(excludeId) | user 反馈:"如果是调拨的话,转出选了 A 账号,转入在选择时就不能再出现 A 账号提供可选,不然就乱套了"。修:`_AccountPickerSheet` 加 `excludeId` 参数,source picker 传 `_destinationAccountId`、dest picker 传 `_accountId`。过滤逻辑 `where` 同时按 `accountTypeFilter` + `excludeId` 双向过滤。选时排除比选时 disable 干净,user 只看到"还能选的"。影响:调拨场景(投资 / 福利 / 不动产 / 其它调拨) source ≠ dest,避免"自转" + 双重扣款 bug |
| D51 | 负债段 toggle 改 借出/借入 2 段(替换支出/收入)+ balance 算法扩 lend_out/borrow_in | user 截图:"记一笔(负债)页用 支出/收入 语义错,借出是债权人(正数),借入是负债方(负数)"。4 个决策:始终存正数按段区分方向(借出 += amount / 借入 -= amount,balance = Σ lend − Σ borrow);不增加交易对手字段(走备注);还款走调拨(负债 → 现金);借入方还款开放 现金 → 负债 调拨。实施:① `assetRepository.balanceDeltaByAssetId` 扩 2 个查询(lendOutSum += amount, borrowInSum -= amount)② `TypeToggle.receivableSegments` 2 段(借出 #F59E0B 橙 / 借入 #EF4444 红)③ `_toggleSegments` / `_type` / `_needsDualAccount` / `initState._intent` 适配 receivable ④ `AmountDisplay` 颜色 + transaction_tile 不显示 ± prefix。调拨方向限制:负债 can only interact with cash_flow(D50 source≠dest 互斥仍适用) |
| D51 v2 | 4 个 UAT 修复:加 3rd 调拨段 + 借出/借入 符号反转 + 流水类型 label + "负债" 改"债务" | user UAT 4 个反馈:(1) 调拨应该在负债页直接进(3rd 段) (2) 借出显示 - / 借入显示 +(ledger 走"现金流向"语义,asset 走"债务方向"语义,双视角相反) (3) 流水 tile 类型 label 应该显示"借出"/"借入"(不是 cat.name "债务") (4) "负债" label 改"债务"(口语更直观)。实施:① `TypeToggle.receivableSegments` 加 'transfer' 第 3 段(#FFEAA7 浅金,跟 cash_flow 调拨一致)② `transaction_form._type` 加 receivable transfer → 'balance' 映射③ `_needsDualAccount` 改 transfer=true④ `_destinationTypeFilter` 改 receivable transfer = 'cash_flow'(债务↔现金)⑤ `transaction_tile` 借出=-/借入=+,加 `_displayLabelFor` 改走 transaction.type⑥ 6 处 UI label "负债"/"债权" → "债务" 统一,DB enum 'receivable' 保留 |
| D51 v3 | 债务调拨不限类型 + 记一笔页标题改"债务" | user UAT 2 个反馈:(1) "债务的调拨的话,我认为转入转出都能选择现金流和债务账号" — 之前 v2 调拨 dest 限定 'cash_flow' 太死,实际场景多个债务账户之间也可调拨 (2) "记一笔(负债) 这里应该是(债务)" — D51 v2 改 6 处 UI label 漏了这一处。实施:① `_accountTypeFilter` / `_destinationTypeFilter` receivable transfer 改返回 null(不限),借出/借入仍走 caller 默认 'receivable' ② `_appBarTitle` case 'receivable' 改 "记一笔(债务)" |
| D51 v4 | 修 v3 bug:source picker 仍被 widget.accountTypeFilter 覆盖 | user UAT 反馈 v3 修了 dest picker 但源 picker 还是只显示 债务。根因:`_openAccountPicker` 用 `_accountTypeFilter ?? widget.accountTypeFilter` fallback,即便 `_accountTypeFilter` 返 null 也会被 `widget.accountTypeFilter='receivable'` 覆盖。修:`_openAccountPicker` 显式短路 — `_isReceivableContext && _intent == 'transfer'` 时 filter 直接 null,不走 `??` fallback。`_openDestinationAccountPicker` 已经走 `_destinationTypeFilter` 没 bug |
| D52 | 修 _AccountPickerSheet 滑到底 RenderFlex overflow | user 反馈"popup 往下滑到底的时候,好像有机会出现 overflow"。报错 RenderFlex height=42.2 OVERFLOWING。根因:DraggableScrollableSheet snap 到 minChildSize=0.0 时可用高度 ~0,Column 非 Expanded 子项(handle 24 + header 38 + divider 1 = 63)总高 > 42.2 → overflow。修:用 LayoutBuilder 拿当前可用高度,够装下 header block(71 = 63 + 8 buffer)才显示;sheet 接近 0 时全隐藏,ListView(Expanded)接管,自然 dismiss |
| D48 v2 | 银行 5 家 → 1 家银联 + icon picker 扁平化(去分组 / 去子 label) | user 反馈两件事:(1) 银行太多反而要考虑更多,只留 1 家"银联 / UnionPay"(letter chip "银" + `#E21836` 银联红),其它 5 家(招/工/建/农/中)删除(2) "图标也不需要分类,不用指导用户,用户想用什么图标用什么图标"。删 `_iconSections (label, keys[])` 8 组结构,改回 `_iconKeys` 扁平 Wrap,43 个 icon 不分类不引导。系统不替用户决定选哪个,user 自由挑。 |