# 局域网 Web 伴侣端规划

> **v0.5.5 草案** · 起稿 2026-10-12
> 状态:**待 user 拍板 3 个默认决策 + 推进 P1**
> 关联:[`ROADMAP.md`](ROADMAP.md) · [`DEV.md`](DEV.md)

---

## 目标

让用户能在**电脑浏览器**上查看与编辑 gridly 账本,**局域网同 WiFi** 即可使用,无需公网、无需云、无需账号体系。

---

## 适用范围(已锁定)

- **网络**:局域网同 WiFi(含手机热点)
- **用户**:单机自用,不引入多账户
- **协议**:裸 HTTP(不碰公网,不上 TLS)
- **端**:Android 主端 + 任意现代浏览器(电脑 / 平板)

---

## 默认决策(待 user 拍板)

| 决策 | 默认值 | 替代选项与影响 |
|---|---|---|
| **实时性** | 手动刷新(电脑改完手机下次打开 / 下拉刷新才看到) | WebSocket 反向推送(+3-5 天) |
| **锁屏** | MVP 不做后台(要求记账时屏幕亮着) | foreground service 常驻通知(+2-3 天 + 续航) |
| **认证** | 一次性 6 位配对码 + session cookie 7 天 | 无认证(同 WiFi 全开放)/ 长期 token |

不告知即按默认值走。

---

## 4 个 Phase 拆分

### ⭐ P1 · 最小可验证骨架(建议先做这一步)

**目标**:开开关后浏览器访问 `http://192.168.x.x:8123` 看到「gridly web v0.1 · 流水 N 条」。

| 项 | 内容 |
|---|---|
| **端口** | 8123(避开 80 / 8080 高占用) |
| **新依赖** | `shelf_plus`、`network_info_plus` |
| **新文件** | `lib/core/server/gridly_server.dart`<br>`lib/core/server/handlers/health_handler.dart`<br>`lib/features/settings/application/server_controller.dart` |
| **改文件** | `pubspec.yaml`<br>`android/app/src/main/AndroidManifest.xml`(加 `INTERNET` + `usesCleartextTraffic`)<br>`lib/features/settings/ui/settings_page.dart`(加「局域网服务」section)<br>`lib/app.dart`(路由注册) |
| **工作量** | **3-4 天** |
| **验收** | ① 开关开 → 显示 IP + 端口;② 同 WiFi 电脑访问 → 见 hello + 数据库 N 条 |

> **P1 是关键风险验证点** —— 在 Android 端起 HTTP server 这件事真能不能通(同 WiFi / Android 14 / 内网 cleartext),不验证就上 API 是赌博。

### P2 · REST API(流水 + 报表 + 分类 + 预算)

**目标**:浏览器能拉数据并新增 / 改 / 删流水,能拉月度汇总 + 报表。

**API 草图**:

```
GET    /api/health                    # 健康检查 + 数据库流水条数
GET    /api/ledgers                   # ?from&to&type&category&keyword&page
GET    /api/ledgers/:id
POST   /api/ledgers                   # body: amount/type/categoryId/note/date
PUT    /api/ledgers/:id
DELETE /api/ledgers/:id
GET    /api/categories
POST   /api/categories
PUT    /api/categories/:id
GET    /api/stats/monthly             # ?year&month
GET    /api/stats/categories          # ?from&to
GET    /api/stats/top                 # ?from&to&limit
GET    /api/budget                    # ?year&month
PUT    /api/budget
```

| 项 | 内容 |
|---|---|
| **新文件** | `lib/core/server/handlers/{ledgers,categories,stats,budget}_handler.dart`<br>`lib/core/server/auth.dart`(配对码校验 + cookie)<br>`lib/core/database/app_database.dart` repository 加 `toJson()` |
| **工作量** | **5-6 天** |

### P3 · Flutter Web 端(流水 + 记一笔 + 报表)

**目标**:浏览器能正常用 3 个核心页面,响应式适配桌面。

| 项 | 内容 |
|---|---|
| **清理** | `web/` 目录启用(目前 untracked,等 user 拍板是删 / 启用 / 内容覆盖) |
| **新文件** | `lib/core/web/`(web 适配层)+ `web/src/pages/` |
| **改文件** | 抽现有 `LedgerListTile` / `SaveBar` / `MonthlySummaryCard` / `MonthlyTrendChart` 成 web 安全版(不能引 `share_plus` / `flutter_markdown` 等 mobile-only 包) |
| **工作量** | **5-7 天** |

### P4 · Polish

网络异常 / 断 WiFi / IP 变化处理 + 千条流水分页性能 + 错误页(401 / 404 / 500) + 简单 README。

**3-4 天**。

---

## 工作量汇总

| 阶段 | 天 |
|---|---|
| P1 骨架 | 3-4 |
| P2 API | 5-6 |
| P3 Web | 5-7 |
| P4 polish | 3-4 |
| **合计 MVP** | **16-21 天(约 4-5 周单兵)** |

里程碑命名:**v0.5.5 · 局域网 Web 端**,插在路线图 v0.5.0(数据导出增强)和 v0.6.0(备份恢复)之间。

---

## 推进顺序

```
P1 (3-4 天)   →  UAT 验证 server 可达性 → 通过后进 P2
P2 (5-6 天)   →  UAT 用 curl 验 API     → 通过后进 P3
P3 (5-7 天)   →  UAT 浏览器里完整走     → 通过后进 P4
P4 (3-4 天)
```

不做大爆炸:每个 P 一个 feature branch + 多个小 commit,每个 P 结束你做 UAT 通过再开下一个。

---

## 钉死的子决策(待 user 拍板)

| 决策点 | 选项 | 推荐 |
|---|---|---|
| 端口 | 8123 / 8080 / 自定义 | **8123**(避开 80 / 8080 高占用) |
| 认证 | 一次性配对码 / 长期 token / 无 | **一次性配对码 6 位 + session cookie 7 天** |
| 自启时机 | 进 settings 时 / 开关切换时 | **开关切换**(不主动占资源) |
| 路由前缀 | `/api/` + `/`(静态) | 标准 |

---

## 关键风险

| # | 风险 | 缓解 |
|---|---|---|
| 1 | Android 后台限制锁屏杀 server(Android 8+) | 当前 MVP 接受;后续 P4 后再做 foreground service |
| 2 | 长开 WiFi + server 续航每小时掉 5-10% | 文档说建议插电;开关 OFF 即停 |
| 3 | 裸 HTTP 内网传输账本 | 文档说「LAN only / 不要连公共 WiFi」(家用 WiFi 没问题) |
| 4 | AGPL-3.0 | web 端代码也是 AGPL,无新增风险 |
| 5 | `web/` 目录 untracked | 待 user 拍板:删 / 启用 / 内容覆盖;P1 不影响 |
| 6 | 没做的话,Android 14 后台启动 HTTP server 需要 foreground service type `dataSync` | MVP 锁屏 kill 后需用浏览器重新进服务自检 |

---

## Open Questions(待 user 回答后开工 P1)

- [ ] 实时性默认(手动刷新)接受吗?
- [ ] 锁屏默认(MVP 不后台)接受吗?
- [ ] 认证默认(6 位配对码 + 7 天 cookie)接受吗?
- [ ] 端口默认 8123 接受吗?
- [ ] 是否要先做 P1 prototype 验证 Android HTTP server 可达性,再进 P2?

---

## Open Tasks(后续要补的内容)

- [ ] 配对码 UI 设计稿(scan QR 还是手输 6 位?)
- [ ] Web 端 UI 设计稿(响应式断点 + 复用 vs 重写组件清单)
- [ ] 鉴权流程图(开开关 → 浏览器扫码 → 6 位码配对 → 进主页)
- [ ] curl 示例全集(每个 API 一条示例)
- [ ] Android 14 后台启动 service 的具体兼容性测试报告
- [ ] 是否引入 `qr_flutter` / `mobile_scanner` 做扫码配对
- [ ] 文档:`docs/LAN_WEB_USAGE.md`(给自用的使用手册)还是并入主 README

---

## 历史决策

| 日期 | 决策 | 原因 |
|---|---|---|
| 2026-10-12 | 方案锁定为 A(局域网 + Flutter Web 复用) | 用户指定;自用单机同 WiFi;不需要云 |
| 2026-10-12 | 不动方案 B / C | A 已能满足;B/C 引入云依赖违反 gridly 本地优先哲学;AGPL 自建 server 强制开源无必要负担 |
| 2026-10-12 | 插入路线图 v0.5.5 位置 | 介于 v0.5.0 数据导出增强和 v0.6.0 备份恢复之间,功能上是「远程编辑」,属于导出 / 备份的补集 |
| 2026-10-12 | 文档放 `docs/LAN_WEB.md` | 沿用现有 docs/ 大写短名约定(ROADMAP / DEV / UI_UX) |
