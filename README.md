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

## 📚 研发文档

研发阶段元信息(当前进度 / 路线图 / 已知限制 / 目录结构 / 技术决策 / 设计规范)单独维护:

- 📌 **[`docs/ROADMAP.md`](docs/ROADMAP.md)** —— 当前阶段 + 路线图 + 已知限制
- 🛠️ **[`docs/DEV.md`](docs/DEV.md)** —— 目录结构 + 关键技术决策 + D 系列设计记录
- 🤖 **[`docs/UI_UX.md`](docs/UI_UX.md)** —— UI/UX 工程师助手指令(交互 / 动画 / 无障碍原则)
- 🎨 **[`docs/design/`](docs/design/)** —— 设计稿源文件(视觉系统 + LOGO + 圆角 / 间距 / 配色)

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