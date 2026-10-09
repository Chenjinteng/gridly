# 格子记账 · gridly

> **一格一账的本地优先记账工具** —— Flutter 3 · Riverpod · Drift · go_router

## 📋 当前阶段

**P0 · 工程骨架**(本版本)

- ✅ Flutter 3.47 工程初始化
- ✅ 主题系统(配色 / 字体 / 圆角 / 间距)直接落地 `lib/core/theme/`
- ✅ 路由(`go_router`)+ 5 Tab + 启动屏
- ✅ Riverpod ProviderScope 入口
- ✅ Light / Dark 双 ThemeData

**P0 没做**(后续 P1+ 推进):

- 数据库表 / Drift schema(P1)
- 流水 / 记一笔 / 报表真实页面(P1 / P2)
- 飞书导入(P3)
- 完整 iOS 端(Xcode simulator runtime + CocoaPods 还没装)
- 主题切换 UI / i18n / 深链

## 🎨 品牌 & 设计规范

**必读:** [`design/THEME.md`](../../Documents/References/记账App/design/THEME.md)

所有颜色 / 字体 / 圆角 / 间距 / "格子"主题的应用,都来自 THEME.md。**禁止** 写死 hex 颜色绕过 `lib/core/theme/`。

## 🚀 快速启动

```bash
cd ~/Documents/Projects/gridly

# 拉依赖
flutter pub get

# 跑代码生成(Drift / Riverpod,P0 阶段无 .g.dart 也要先跑)
dart run build_runner build --delete-conflicting-outputs

# 列设备(确认真机 / 模拟器 / Web)
flutter devices

# 跑起来(替换 <device-id> 为上一步输出)
flutter run -d <device-id>
```

## 📦 目录结构

```
gridly/
├── lib/
│   ├── main.dart                       # 入口
│   ├── app.dart                        # MaterialApp + 主题 + 路由
│   ├── core/
│   │   ├── theme/                      # ★ 配色 / 字体 / 圆角 / 间距 / ThemeData
│   │   │   ├── app_colors.dart
│   │   │   ├── app_typography.dart
│   │   │   ├── app_spacing.dart
│   │   │   ├── app_radius.dart
│   │   │   └── app_theme.dart
│   │   └── router/
│   │       └── app_router.dart
│   └── features/
│       ├── splash/                     # 启动屏
│       ├── shell/                      # 5 Tab 容器
│       ├── home/                       # 首页
│       ├── ledger/                     # 流水
│       ├── add/                        # 记一笔
│       ├── stats/                      # 报表
│       └── settings/                   # 我的
├── assets/
│   └── images/logo/                    # LOGO 套装
├── android/                            # Android 原生工程
├── ios/                                # iOS 原生工程(暂未配置)
├── pubspec.yaml
└── README.md
```

## 🎯 关键技术决策

| 维度 | 选型 | 理由 |
|---|---|---|
| 跨端框架 | Flutter 3.47 | 一套代码双端,iOS 可模拟器开发 |
| 状态管理 | Riverpod 2.x | 编译期安全 / 易测试 |
| 数据库 | Drift + SQLite | 本地优先,隐私敏感 |
| 路由 | go_router | 官方推荐,支持深链 |
| 图表 | fl_chart(P2 启用) | 风格自由 |

完整选型见 [TECH_STACK.md](../../Documents/References/记账App/TECH_STACK.md)。

## 📌 路线图

- **P0** ✅ 工程骨架(本版)
- **P1** 数据库 + 记一笔 + 流水列表 + 设置
- **P2** 报表(分类饼图 / 月度趋势)
- **P3** CSV 导出 / 飞书智能表格导入
- **P4** 主题切换 UI / i18n / 深链
- **P5** 性能优化 / 无障碍
- **P6** 应用商店上架准备(截图 / 描述 / 隐私政策)
- **P7** 发布(Android Play Store / iOS App Store)

## ⚠️ 已知限制

- iOS 端暂不可用:`flutter doctor` 报 CocoaPods / iOS Simulator 红叉,本次只跑 Android
- Intel Mac 警告:Flutter 3.x 还在支持,但 4.x 之后会强制 Apple Silicon
- 启动屏 LOGO 用 Container 画三色方块占位,P1 替换为正式 LOGO PNG 资源
