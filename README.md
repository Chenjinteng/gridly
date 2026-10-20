# 格子记账 · gridly

> **一格一账的本地优先记账工具** —— Flutter 3 · Riverpod · Drift · go_router

![status](https://img.shields.io/badge/version-1.0.2-blue)
![flutter](https://img.shields.io/badge/flutter-3.47-02569B)
![platform](https://img.shields.io/badge/platform-Android-success)
![platform](https://img.shields.io/badge/platform-macOS-informational)
![platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![license](https://img.shields.io/badge/license-AGPL--3.0-red)
![commits](https://img.shields.io/badge/commits-700%2B-orange)

---

## 🛑 平台支持

| 平台 | 状态 |
|---|---|
| **Android** | ✅ 主交付平台,Material 3 |
| **macOS**(调试) | ✅ Flutter 模拟器,仅用于本地开发 |
| **iOS** | ❌ **暂时没有计划** —— 不安装 CocoaPods / Simulator runtime,工程骨架保留但不做 UAT、不做截图、不上架 |

---

## ✨ 功能一览

底部 4 个 Tab + 中间「记一笔」按钮,覆盖完整的日常记账闭环。

| 模块 | 能做什么 |
|---|---|
| **首页** | 月度汇总(收入 / 支出 / 结余)、月度预算进度、日均支出、金额一键隐藏(防偷窥) |
| **流水** | 按日分组(当天最新记的排最前)、类型 / 月份 / 分类 / 关键字筛选、左滑删除、每天一个小结 |
| **记一笔** | 支出 / 收入 / 调拨 / 借出 / 借入、分类 + 账户 + 备注 + 日期、金额实时校验(不会扣成负数) |
| **报表** | 消费趋势、支出分析(分类 / 账户两个圆环)、Top 10、同比、储蓄走势、资产配置、资产雷达、预算概览、债务与投资看板 |
| **我的** | 主题、预算、资产、CSV 导出、备份还原、分类管理、显示金额开关 |

**资产分 6 段**:流动资金 / 投资 / 福利 / 债务 / 不动产 / 其它。每段独立配色,流水页和资产页用的是同一套色,跨页对得上。

**数据全在本地**:SQLite(Drift),没有云端、没有账号、没有埋点。备份就是导出一个 `.sqlite` 文件,还原就是选回这个文件;流水也能导出 CSV 对账。

---

## 🎨 品牌 & 设计规范

颜色集中在 [`lib/core/theme/app_colors.dart`](lib/core/theme/app_colors.dart),分类色在 `AppCategory` 类下定义,资产段色在 `AppSegment` 类下定义。

- **主色**:Gold `#F5BC1F` / Teal `#14B8A6` / Ink `#0F1419`
- **收支语义色**:正 = Teal `#14B8A6` / 负 = `AppStatus.error` `#EF4444`,**所有主题恒定** —— 切到粉色主题,小结、汇总卡、流水预览的绿 / 红也不变
- **支出色 = `AppStatus.error #EF4444`**(警示感强,违反 THEME.md 反红绿色盲原则,用户坚持 D16 设计决策)
- **资产 6 段色**:`AppSegment` 统一定义,流水 / 资产 / 报表三处共用同一 token
- **主题组合**:白天 / 夜晚 × 默认品牌色 / 粉色,共 4 种

**禁止** 在业务代码里写死 hex 颜色绕过 `app_colors.dart`。

---

## 🚀 快速启动

```bash
# 1.0.x 维护线(Android 发布走这条)
cd ~/Documents/Projects/gridly-1.X

# 2.0 开发线(WIP,feature/lan-web-p1 分支)
# cd ~/Documents/Projects/gridly

# 拉依赖
flutter pub get

# 跑代码生成(Drift schema)
dart run build_runner build --delete-conflicting-outputs

# 跑起来(macOS 模拟器或 Android 真机 / 模拟器)
flutter devices
flutter run -d <device-id>
```

### 旧数据迁移(从别的记账 App 搬进来)

用 [`skills/gridly-migrate/`](skills/gridly-migrate/) —— 纯 Python 标准库脚本,读支付宝 / 微信 / 随手记等导出的 CSV / Excel,产出可直接导入的 `gridly-migrated.sqlite` + 一份「哪些数据没迁过来」的报告。安装与用法见 [`skills/README.md`](skills/README.md)。

---

## 📚 研发文档

研发阶段元信息(当前进度 / 路线图 / 已知限制 / 目录结构 / 技术决策 / 设计规范)单独维护:

- 📌 **[`docs/ROADMAP.md`](docs/ROADMAP.md)** —— 当前阶段 + 路线图 + 已知限制
- 🛠️ **[`docs/DEV.md`](docs/DEV.md)** —— 目录结构 + 关键技术决策 + D 系列设计记录
- 🤖 **[`docs/UI_UX.md`](docs/UI_UX.md)** —— UI/UX 工程师助手指令(交互 / 动画 / 无障碍原则)
- 🗄️ **[`docs/SCHEMA.md`](docs/SCHEMA.md)** —— SQLite 表结构 + 迁移历史(schema v9)
- 🔧 **[`docs/REFACTOR_D64.md`](docs/REFACTOR_D64.md)** —— 2026-10-16 D64 code review + 重构归档(13 commit / 24 finding / 排查指引)
- 🏗️ **[`docs/ASSETS_PLAN.md`](docs/ASSETS_PLAN.md)** —— 资产段体系设计
- 🌐 **[`docs/LAN_WEB.md`](docs/LAN_WEB.md)** —— 局域网 Web 伴侣端方案(2.0 线)
- 🎨 **[`docs/design/`](docs/design/)** —— 设计稿源文件(视觉系统 + LOGO + 圆角 / 间距 / 配色)
- 📦 **[`skills/`](skills/)** —— 可分发的 AI skills(当前:`gridly-migrate`,把其它记账 App 的旧数据迁进 gridly)

> README 只放用户面内容(品牌 / 平台支持 / 上手指南 / 协议),避免信息膨胀。

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
