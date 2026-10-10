# 格子记账 · gridly

> **一格一账的本地优先记账工具** —— Flutter 3 · Riverpod · Drift · go_router

![status](https://img.shields.io/badge/version-0.2.0-blue)
![flutter](https://img.shields.io/badge/flutter-3.47-02569B)
![platform](https://img.shields.io/badge/platform-Android-success)
![platform](https://img.shields.io/badge/platform-macOS-informational)
![platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![license](https://img.shields.io/badge/license-AGPL--3.0-red)
![commits](https://img.shields.io/badge/commits-50-orange)

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

### v0.2.0 阶段 2 · 多账户(待开)

- 待做:多账户管理(银行卡 / 现金 / 支付宝 / 微信 等)
- 待做:流水绑定账户维度
- 待做:按账户统计余额

---

## 🛑 平台支持

| 平台 | 状态 |
|---|---|
| **Android** | ✅ 主交付平台,Material 3 |
| **macOS**(调试) | ✅ Flutter 模拟器,仅用于本地开发 |
| **iOS** | ❌ **暂时没有计划** —— 不安装 CocoaPods / Simulator runtime,工程骨架保留但不做 UAT、不做截图、不上架 |

---

## 🎨 品牌 & 设计规范

颜色集中在 [`lib/core/theme/app_colors.dart`](lib/core/theme/app_colors.dart),分类色在 `AppCategory` 类下定义。

- **主色**:Gold `#F5BC1F` / Teal `#14B8A6` / Ink `#0F1419`
- **文字色 vs 分类色**:正负数文字 = 红 / 金;分类 = 11 支出 + 4 收入 + 12 调色板(用于自定义分类)
- **支出色 = `AppStatus.error #EF4444`**(警示感强,违反 THEME.md 反红绿色盲原则,用户坚持 D16 设计决策)

**禁止** 在业务代码里写死 hex 颜色绕过 `app_colors.dart`。

---

## 🚀 快速启动

```bash
cd ~/Documents/Projects/gridly

# 拉依赖
flutter pub get

# 跑代码生成(Drift schema)
dart run build_runner build --delete-conflicting-outputs

# 跑起来(macOS 模拟器或 Android 真机 / 模拟器)
flutter devices
flutter run -d <device-id>
```

### 数据迁移(从飞书导入)

```bash
# 1. 关掉 gridly app 释放 db lock(Cmd+Q 完全退出)
# 2. 重跑脚本(覆盖 db,29 个自定义分类按 DJB2 hash 分散取色)
python3 ~/Documents/MinimaxWorkspace/temps/tmp_minimax_gridly_import_feishu.py
# 3. 重启 app(Drift 内存 cache 需重启才能读新 db)
flutter run -d macos
```

脚本一次性:把飞书 CSV 灌进 Drift 的 SQLite,跑前 app 必须退干净。

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
│   │   ├── utils/                           # Formatters / 预算
│   │   └── widgets/                         # GridlyMark(LOGO mark)
│   └── features/
│       ├── splash/                          # 启动屏(LOGO + 三色横条)
│       ├── shell/                           # 5 Tab 容器
│       ├── home/                            # 首页(LOGO + 产品名 + 月度汇总 + 预算)
│       ├── ledger/                          # 流水(查询筛选 dropdown + 按日分组)
│       ├── add/                             # 记一笔(选日期 + 计算器 + SaveBar)
│       ├── stats/                           # 报表(月份段 + 分类圆环 + Top 10 + 月度趋势)
│       └── settings/                        # 我的(主题 / 分类管理 / 隐私 / 预算 / 导出 / 关于)
├── assets/
│   └── images/logo/                         # GridlyMark + LOGO 横排 / 竖排
├── android/                                 # Android 原生工程
├── ios/                                     # iOS 原生工程(不维护)
├── pubspec.yaml
└── README.md
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

---

## 📌 路线图

- **v0.1.0** ✅ 完整可用(5 Tab + 流水 + 记一笔 + 报表 + 我的)
- **v0.2.0 阶段 1** ✅ 报表增强(Top 10 + 日均 + 分类色 + 流水筛选)
- **v0.2.0.x** ✅ polish 与体验优化(20+ 项,见上文)
- **v0.2.0 阶段 2** 🔜 多账户(账户维度 + 余额统计)
- **v0.3.0** 📋 预算精细化(分类预算 + 周预算 + 告警阈值)
- **v0.4.0** 📋 i18n(英文 + 简繁中文)
- **v0.5.0** 📋 数据导出增强(JSON / Excel)
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

---

## 📄 开源协议

**GNU Affero General Public License v3.0(AGPL-3.0)**

本项目采用 **AGPL-3.0** 协议发布 —— 强 copyleft + 网络服务端开源触发。

- ✅ **允许**:个人学习、非商业使用、二次开发并开源
- ⚠️ **商用受限**:任何商业使用(包括但不限于销售、付费服务、SaaS 提供、企业内训)都必须以 AGPL-3.0 开源全部衍生代码,网络服务端同样触发
- ❌ **禁止**:闭源商用、私有化分销、转授权闭源衍生作品

完整文本见 [`LICENSE`](LICENSE)。如需商业授权,请联系作者单独洽谈。

```
Copyright (C) 2026 Chenjinteng
```