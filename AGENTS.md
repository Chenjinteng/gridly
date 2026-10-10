# AGENTS.md

> 给 coding agent / AI 协作者看的工程总览。UI/UX 专项看 [`docs/UI_UX.md`](docs/UI_UX.md)。

---

## 项目概述

**gridly**(格子记账)是一个**本地优先**的 Flutter 跨端记账 App。

- **目标平台**:**Android 主交付**,macOS 仅开发调试,**iOS 永久搁置**(不装 CocoaPods / 不打 IPA)
- **技术栈**:Flutter 3.47.7 · Riverpod 2.x · Drift + SQLite · go_router · fl_chart · Material 3
- **数据**:本地 SQLite,无云端 BaaS / 后端
- **协议**:AGPL-3.0(强 copyleft,商用受限,详见 [`LICENSE`](LICENSE))

---

## 快速开始

```bash
# 拉依赖
flutter pub get

# 跑代码生成(Drift schema)
dart run build_runner build --delete-conflicting-outputs

# 检查
flutter analyze   # 必须 0 issue
flutter test      # 必须全过

# 跑起来(macOS 模拟器 / Android 设备)
flutter devices
flutter run -d <device-id>
```

模拟器数据库路径(macOS sandbox):

```
~/Library/Containers/cn.jinteng.gridly/Data/Documents/gridly.sqlite
```

数据迁移脚本在 `~/Documents/MinimaxWorkspace/temps/tmp_minimax_gridly_import_feishu.py`(一次性,从飞书 CSV 灌入)。

---

## 项目结构

```
gridly/
├── AGENTS.md                   # 本文件(AI 协作总览)
├── README.md                   # 用户面入口(品牌 / 平台 / 上手 / 协议)
├── LICENSE                     # AGPL-3.0
├── docs/
│   ├── ROADMAP.md              # 当前阶段 + 路线图 + 已知限制
│   ├── DEV.md                  # 目录结构 + 技术决策 + D 系列
│   ├── UI_UX.md                # UI/UX 工程师 AI 助手指令
│   └── design/                 # 设计稿源文件(theme.html 等)
├── lib/
│   ├── main.dart               # 入口(seed + sync)
│   ├── app.dart                # MaterialApp + 主题 + 路由
│   ├── core/                   # 跨 feature 基础设施
│   │   ├── theme/              # ★ 配色 / 字体 / 圆角 / 间距 / LOGO
│   │   ├── database/           # Drift schema + repository + providers
│   │   ├── router/             # go_router 配置
│   │   ├── settings/           # 持久化设置(主题 / 金额可见性)
│   │   ├── utils/              # Formatters / 预算 / refreshAllData helper
│   │   └── widgets/            # GridlyMark(LOGO)
│   └── features/               # 业务模块(按页面切分)
│       ├── splash/             # 启动屏
│       ├── shell/              # 5 Tab 容器
│       ├── home/               # 首页
│       ├── ledger/             # 流水
│       ├── add/                # 记一笔
│       ├── stats/              # 报表
│       └── settings/           # 我的
├── assets/                     # 静态资源(LOGO 等)
├── android/                     # Android 原生工程
├── ios/                        # iOS 原生工程(不维护)
├── macos/                      # macOS 原生工程(调试用)
├── test/                       # 单元测试
├── analysis_options.yaml       # lint 规则
└── pubspec.yaml                # 依赖声明
```

每个 feature 模块内部统一结构:

```
features/<name>/
├── application/      # providers / repository / 业务逻辑
├── data/             # 数据源(如有)
└── ui/               # 页面 + widgets
```

---

## 关键约定

### 颜色 / 视觉

- **业务代码严禁写死 hex 颜色绕过 `app_colors.dart`**(`AppBrand` / `AppCategory` / `AppSemantic`)
- 圆角统一走 `AppRadius.brXs/Sm/Md/Lg/Xl`,不允许用魔法数字
- 间距统一走 `AppSpacing.s1/s2/s3/s4`
- 设计稿源文件在 [`docs/design/theme.html`](docs/design/theme.html),**改 UI 前先读它**,别看图脑补
- **D16**:支出文字色 = `AppStatus.error`(红),违反 THEME.md 反红绿色盲原则,用户坚持警示感

### 状态管理(Riverpod)

- Provider 按 feature 拆分,放 `features/<name>/application/`
- 跨 feature 的工具放 `core/utils/`,避免反向依赖
  - 例:`refreshAllData(ref)` 在 `core/utils/refresh_providers.dart`,ledger 不能直接依赖 stats 的 provider
- StateNotifier + SharedPreferences 用于持久化设置(主题模式 / 金额可见性)

### 数据库(Drift)

- Schema 定义在 `core/database/app_database.dart`,改动后必须重跑 build_runner
- Repository 模式封装 DAO,**业务代码不直接调 DAO**
- 删 / 改流水后必须 `refreshAllData(ref)` 广谱刷新

### Git / Commit

- Commit message **中文**,格式:`<type>: <scope> 一句话说明`,type 用 `feat` / `fix` / `refactor` / `docs` / `polish` / `chore`
- 每个 commit 单一改动,不要混
- **Commit + push 后,同一条响应直接给 UAT 下一步命令**(用户一次明确要求),包括:
  - `git pull` + 设备相关命令
  - 预期效果
  - 报错速查表
- UAT 命令按改动类型不同:
  - `.dart` / `pubspec.yaml` 改 → `flutter run` 热重载(`r`)
  - schema 改 → `dart run build_runner build --delete-conflicting-outputs`
  - 仅 settings / volumes mount 改 → `flutter run` 自动重新挂载
- **跑通前不开始下个 phase**

### 文档组织

- **README 只放用户面内容**(品牌 / 平台 / 上手 / 协议),研发内容放 `docs/`
- 新增研发文档 → 放 `docs/` 下,README 的"研发文档"章节加链接
- 设计稿源文件(HTML)放 `docs/design/`,改 UI 前必读
- 不在 README 里堆路线图 / 已知限制 / 阶段进度(会膨胀)

---

## 已知约束

### 平台

- **iOS 端永久不做**:不安装 CocoaPods、不配置 iOS Simulator runtime、不打 IPA、不上架。`ios/` 目录保留工程骨架
- **macOS 仅供开发调试**:Flutter desktop simulator 跑通即可,不做 macOS 端发布
- **Android 是唯一主交付平台**

### 依赖

- **本机 Python 无 pandas / openpyxl / pyarrow**(venv 也无),不要擅自 `pip / brew install`
- 输出 xlsx → 用 stdlib `zipfile` + 手写 OOXML,Excel 可正常打开
- 聚合统计优先纯 stdlib(`json` / `csv` / `glob` / `collections`)
- 业务 Flutter 代码**不引入 flutter_slidable** 等滑动删除库(D24 决策,控制依赖)
- 临时脚本(`tmp_minimax_` 前缀)放 `~/Documents/MinimaxWorkspace/temps/`,不放 `/tmp` / `~/Downloads/` 散落

### 工具安装 / 跑通

- **用户自己装工具**(brew / Android Studio / Xcode),不要在用户机器上擅自 `pip / brew install`
- **本机权限门拦截 `rm` / `mv`**(移走已有文件 = removal 语义),包括 glob 形式。绕过办法:写清理脚本(`tmp_minimax_` 前缀)交付用户在终端跑,不要反复试变体
- **不要在 UAT 跑 `flutter run` / `flutter build` / `docker`** —— 用户在 UAT 机器上跑,本机只改代码 + commit + push
- Chart tarballs (`charts/*.tgz`) 设计上 gitignored,本机不下载,用户在 UAT 用 `helm pull`

### 视觉

- **支出文字色 = 红**(`AppStatus.error`),违反反红绿色盲原则(D16,用户坚持)
- 同一操作只保留一个 UI 入口(D21),AppBar 不放保存按钮,统一在 SaveBar
- 滑动删除手写实现,不引入第三方库

---

## 协作工作流

1. **理解需求**:先读 README + 相关 docs/ 章节 + UI/UX.md(如果是 UI 改动)
2. **定位代码**:用 `grep` / `glob` 找现有实现,优先复用而不是新建
3. **小步快跑**:每个改动一个 commit,中文 message,scope 准确
4. **验证 lint**:commit 前跑 `flutter analyze`,必须 0 issue
5. **同步 UAT**:`git commit` + `git push` 后,**同一条响应**给 UAT 命令 + 预期 + 速查
7. **少弹窗**:能用 inline 确认的不用弹窗,用户反复强调
8. **同一入口**:新增 UI 入口前先检查是否已存在,删重复

---

## 协议

- **AGPL-3.0**:任何商业使用(包括销售、付费服务、SaaS、企业内训)必须以 AGPL-3.0 开源全部衍生代码,网络服务端同样触发
- 个人 / 学习 / 非商业完全免费
- 商用授权单独洽谈
- 完整文本见 [`LICENSE`](LICENSE)

---

## 相关文件

- 用户面入口:[`README.md`](README.md)
- 当前阶段 + 路线图:[`docs/ROADMAP.md`](docs/ROADMAP.md)
- 关键技术决策 + D 系列:[`docs/DEV.md`](docs/DEV.md)
- UI/UX AI 助手指令:[`docs/UI_UX.md`](docs/UI_UX.md)
- 设计稿源文件:[`docs/design/`](docs/design/)