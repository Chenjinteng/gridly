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

### v0.2.0 阶段 2 · 多账户(待开)

- 待做:多账户管理(银行卡 / 现金 / 支付宝 / 微信 等)
- 待做:流水绑定账户维度
- 待做:按账户统计余额

---

## 📌 路线图

- **v0.1.0** ✅ 完整可用(5 Tab + 流水 + 记一笔 + 报表 + 我的)
- **v0.2.0 阶段 1** ✅ 报表增强(Top 10 + 日均 + 分类色 + 流水筛选)
- **v0.2.0.x** ✅ polish 与体验优化(20+ 项,见上文)
- **v0.3.0** ✅ 分类预算精细化(2026-10-12 完成,见上文)
- **v0.2.0 阶段 2** 🔜 多账户(账户维度 + 余额统计)
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