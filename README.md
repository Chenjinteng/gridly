# 格子记账 · gridly

> **一格一账的本地优先记账工具** —— Flutter 3 · Riverpod · Drift · go_router

![status](https://img.shields.io/badge/version-0.2.0-blue)
![flutter](https://img.shields.io/badge/flutter-3.47-02569B)
![platform](https://img.shields.io/badge/platform-Android-success)
![platform](https://img.shields.io/badge/platform-macOS-informational)
![platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![license](https://img.shields.io/badge/license-MIT-green)

---

## 📋 当前阶段

**v0.2.0 阶段 1(报表增强)✅ 完成**

### v0.1.0 · 完整可用

- ✅ 工程骨架 + Drift/SQLite + Riverpod Provider 体系
- ✅ 5 Tab 首页(首页 / 流水 / 记一笔 / 报表 / 我的)
- ✅ 流水(按日分组 + 筛选查询)
- ✅ 记一笔(类型切换 + 表达式计算器 + 分类选择 + 备注 + **可选日期**)
- ✅ 报表(分类圆环 / 月度趋势 / Top 10 / 月度汇总卡)
- ✅ 我的(预算 + 分类管理 + 关于 + 主题切换 + CSV 导出 + 清空数据)
- ✅ 17 个语义化 Material 图标
- ✅ 自定义分类(增 / 改 / 删,30+ 图标 + 16 色可选)
- ✅ 预算告警(月度预算 + 进度条 + 状态颜色)
- ✅ Material 3 + Light/Dark 双主题 + 16×16 格子纸背景
- ✅ LOGO 套装(GridlyMark 2×2 + 横排 + 竖排)
- ✅ 千分位逗号(intl)
- ✅ 月度汇总 Excel 工作表风格

### v0.2.0 阶段 1 · 报表增强

- ✅ 报表 Top 10(固定 10 行 + 不足留白 + 不可滚动)
- ✅ 日均支出
- ✅ 预算文案改为"还剩 ¥xxxx"
- ✅ 分类色差异化(支付宝语义色风格 — 餐饮橙 / 交通蓝 / 通讯青 / 教育紫 ...)
- ✅ 趋势图去除网格线
- ✅ 流水页加查询筛选(类型 / 月份 / 分类 / 关键字)

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

- 主色:Gold `#F5BC1F` / Teal `#14B8A6` / Ink `#0F1419`
- 文字色 vs 分类色:正负数文字 = 红/金;分类 = 11 支出 + 4 收入 + 12 调色板
- 支出色 = `AppStatus.error #EF4444`(警示感,D16 设计决策,违反 THEME.md 反红绿色盲原则,用户坚持)

**禁止** 在业务代码里写死 hex 颜色绕过 `app_colors.dart`。

---

## 🚀 快速启动

```bash
cd ~/Documents/Projects/gridly

# 拉依赖
flutter pub get

# 跑代码生成(Drift schema)
dart run build_runner build --delete-conflicting-outputs

# 跑起来(Android 真机或模拟器)
flutter devices
flutter run -d <device-id>
```

### 数据迁移(从飞书导入)

见 [`~/Documents/MinimaxWorkspace/temps/tmp_minimax_gridly_import_feishu.py`](../MinimaxWorkspace/temps/tmp_minimax_gridly_import_feishu.py)
—— 一次性脚本,把飞书 CSV 灌进 Drift 的 SQLite。

⚠️ 跑前要求:关掉 gridly app 释放 db lock。

---

## 📦 目录结构

```
gridly/
├── lib/
│   ├── main.dart                       # 入口(seed + sync)
│   ├── app.dart                        # MaterialApp + 主题 + 路由
│   ├── core/
│   │   ├── theme/                      # ★ 配色 / 字体 / 圆角 / 间距 / ThemeData
│   │   ├── database/                   # Drift schema + repository
│   │   ├── router/                     # go_router
│   │   └── utils/                      # Formatters
│   └── features/
│       ├── splash/                     # 启动屏
│       ├── shell/                      # 5 Tab 容器
│       ├── home/                       # 首页(月度汇总 + 预算 + 最近流水)
│       ├── ledger/                     # 流水(查询筛选 + 按日分组)
│       ├── add/                        # 记一笔(选日期 + 计算器)
│       ├── stats/                      # 报表(分类圆环 + 月度趋势 + Top 10)
│       └── settings/                   # 我的(预算 / 分类管理 / 主题 / 关于 / 导出)
├── assets/
│   └── images/logo/                    # GridlyMark + LOGO 横排/竖排
├── android/                            # Android 原生工程
├── ios/                                # iOS 原生工程(不维护)
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
| 隐私政策 | flutter_markdown | 关于页内嵌 Markdown 渲染 |

---

## 📌 路线图

- **v0.1.0** ✅ 完整可用(5 Tab + 流水 + 记一笔 + 报表 + 我的)
- **v0.2.0 阶段 1** ✅ 报表增强(Top 10 + 日均 + 分类色 + 流水筛选)
- **v0.2.0 阶段 2** 🔜 多账户(账户维度 + 余额统计)
- **v0.3.0** 📋 预算精细化(分类预算 + 周预算)
- **v0.4.0** 📋 i18n(英文 + 简繁中文)
- **v0.5.0** 📋 数据导出增强(JSON / Excel)
- **v0.6.0** 📋 备份 / 恢复(本地 + WebDAV)
- **v1.0.0** 📋 Android Play Store 上架准备(截图 / 描述 / 隐私政策 / 签名)

---

## ⚠️ 已知限制

- **iOS 端不做** —— 不安装 CocoaPods、不配置 iOS Simulator runtime、不打 IPA、不上架。工程骨架保留(`ios/` 目录),后续有需要再启动
- **macOS 仅供开发** —— Flutter desktop simulator 跑通即可,不做 macOS 端发布
- **Intel Mac** —— Flutter 3.x 还支持,4.x 之后会强制 Apple Silicon
- **第三方依赖无 pandas/openpyxl** —— Python 数据迁移脚本纯 stdlib(sqlite3 + csv)