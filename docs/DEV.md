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