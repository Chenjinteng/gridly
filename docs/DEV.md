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