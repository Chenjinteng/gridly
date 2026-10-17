# 局域网 Web 伴侣端规划

> **v2.0.0 草案**(原 v0.5.5 起稿 2026-10-12,2026-10-17 升 2.0.0 因 LAN_WEB 作为主功能里程碑)
> 状态:**5 个 Open Questions 已拍板(2026-10-17)+ 推进 P1**
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

## 默认决策(2026-10-17 已拍板)

| 决策 | 选定值 | 替代选项与影响 |
|---|---|---|
| **版本号** | **2.0.0+**(原 v0.5.5 草案) | LAN_WEB 作为 2.0 阶段里程碑主功能 |
| **实时性** | 手动刷新(电脑改完手机下次打开 / 下拉刷新才看到) | WebSocket 反向推送(+3-5 天)— 未选 |
| **锁屏** | **foreground service 常驻通知** ⚠️ 覆盖默认 | MVP 不做后台 — 未选(原默认) |
| **认证** | 一次性 6 位配对码 + session cookie 7 天 | 无认证(同 WiFi 全开放)/ 长期 token — 未选 |

**P1 工作量更新**:foreground service 让 P1 从 3-4 天 → **5-7 天**(Android 14 `dataSync` type + 常驻通知 + 服务生命周期)。

---

## 4 个 Phase 拆分

### ⭐ P1 · 最小可验证骨架(建议先做这一步)

**目标**:开开关后浏览器访问 `http://192.168.x.x:8123` 看到「gridly web v0.1 · 流水 N 条」。

| 项 | 内容 |
|---|---|
| **端口** | 8123(避开 80 / 8080 高占用) |
| **新依赖** | `shelf_plus`、`network_info_plus`、`flutter_foreground_task`(foreground service + 常驻通知) |
| **新文件** | `lib/core/server/gridly_server.dart`<br>`lib/core/server/handlers/health_handler.dart`<br>`lib/features/settings/application/server_controller.dart`(开关 toggle + 启停 service)<br>`lib/core/server/lan_web_service.dart`(foreground service entry,Kotlin 端 + Dart isolate 桥) |
| **改文件** | `pubspec.yaml`<br>`android/app/src/main/AndroidManifest.xml`(加 `INTERNET` + `usesCleartextTraffic` + `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` + `<service>` 声明)<br>`android/app/src/main/kotlin/cn/jinteng/gridly/MainActivity.kt`(配 flutter_foreground_task callback)<br>`lib/features/settings/ui/settings_page.dart`(加「局域网服务」section)<br>`lib/app.dart`(路由注册) |
| **工作量** | **5-7 天**(原 3-4 天 + foreground service +2-3 天) |
| **验收** | ① 开关开 → 显示 IP + 端口 + 常驻通知;② 锁屏 server 仍活;④ 同 WiFi 电脑访问 → 见 hello + 数据库 N 条 |

> **P1 是关键风险验证点** —— 在 Android 端起 HTTP server 这件事真能不能通(同 WiFi / Android 14 / 内网 cleartext),不验证就上 API 是赌博。

### P2 · REST API(流水 + 报表 + 分类 + 预算)✅ 2026-10-17 完成

**目标**:浏览器能拉数据并新增 / 改 / 删流水,能拉月度汇总 + 报表。

**实际 API**(P2 commit 1-17 已落):

```
GET    /                                  # 健康检查 + db counts + uptime + serverTime
GET    /api/auth/code                     # 拿 6 位配对码
POST   /api/auth/pair                     # 配对 → 7 天 cookie
POST   /api/auth/logout                   # 注销 + clear cookie
GET    /api/auth/sessions                 # 列已配对设备(排除自己)
DELETE /api/auth/sessions/<token>         # 撤销某设备(非自己)
GET    /api/ledgers                       # ?from&to&type&category&keyword&page&pageSize
GET    /api/ledgers/<id>
POST   /api/ledgers                       # body: amount/type/categoryId/occurredAt/note/accountId
PUT    /api/ledgers/<id>                  # partial update
DELETE /api/ledgers/<id>
GET    /api/categories?type=expense       # type 可选过滤
POST   /api/categories
PUT    /api/categories/<id>
GET    /api/stats/monthly?year&month
GET    /api/stats/categories?from&to
GET    /api/stats/top?from&to&limit
GET    /api/budget?year&month
PUT    /api/budget                        # body: year/month/total/categoryBudgets[]
```

**配套 middleware**(P2 polish):
- `errorHandler()` — 任何 throw → 500 JSON 不漏 stack
- `catchAllHandler()` — 任何未匹配 → 404 JSON
- `bodySizeLimit(1MB)` — Content-Length > 1MB → 413
- `cors()` — OPTIONS 预检 204;响应 echo Origin(P3 web UI 跨源)
- `rateLimit(60/s per token)` — 滑窗,超限 → 429 + Retry-After
- `securityHeaders()` — X-Content-Type-Options / X-Frame-Options / Referrer-Policy / Cache-Control

**P2 自测**(46/46 pass,`flutter analyze` clean):
- 集成测试 6 + edge case 33 + 持久化 2 + 安全 header 3 + 限流 2
- 见 `test/lan_web/`
- 手工 smoke 脚本 `scripts/lan_web_smoke.sh`
- API 完整 curl 文档 `docs/LAN_WEB_API.md`

| 项 | 内容 |
|---|---|
| **新文件** | `lib/core/server/{auth,gridly_server,middleware}.dart`<br>`lib/core/server/handlers/{health,auth,ledgers,categories,stats,budget}_handler.dart`<br>`lib/core/server/handlers/json_helpers.dart`<br>`test/lan_web/{p2_integration_test,p2_edge_cases_test,p2_persistence_test}.dart`<br>`scripts/lan_web_smoke.sh` |
| **修改** | `lib/main.dart`(init port)`lib/features/settings/{ui,application}/`(配对码 / sessions UI)`lib/core/database/app_database.dart`(forTesting ctor)`pubspec.yaml`(+ http / shelf_plus / network_info_plus / flutter_foreground_task)`AndroidManifest.xml`(4 perms + service + cleartext)`docs/LAN_WEB_API.md` |
| **工作量** | 实际 16+ commit,跨多日(目标 5-6 天) |

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
| P1 骨架 | 5-7(原 3-4,foreground service +2-3) |
| P2 API | 5-6 |
| P3 Web | 5-7 |
| P4 polish | 3-4 |
| **合计 MVP** | **18-24 天(约 4.5-6 周单兵)** |

里程碑命名:**v2.0.0 · 局域网 Web 端**(原 v0.5.5,2026-10-17 升版),跨过 v0.5.0 / v0.6.0 / v0.7.0 几个中间里程碑。

---

## 推进顺序

```
P1 (5-7 天)   →  UAT 验证 server 可达性 + foreground service 后台运行 → 通过后进 P2
P2 (5-6 天)   →  UAT 用 curl 验 API                                  → 通过后进 P3
P3 (5-7 天)   →  UAT 浏览器里完整走                                  → 通过后进 P4
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
| 1 | Android 后台限制锁屏杀 server(Android 8+) | ✅ 2026-10-17 user 拍板:**P1 直接做**(foreground service `dataSync` type);不再延后 |
| 2 | 长开 WiFi + server 续航每小时掉 5-10% | 文档说建议插电;开关 OFF 即停;foreground service 常驻通知可一键关 |
| 3 | 裸 HTTP 内网传输账本 | 文档说「LAN only / 不要连公共 WiFi」(家用 WiFi 没问题) |
| 4 | AGPL-3.0 | web 端代码也是 AGPL,无新增风险 |
| 5 | `web/` 目录 untracked | 待 user 拍板:删 / 启用 / 内容覆盖;P3 时处理 |
| 6 | Android 14 后台启动 HTTP server 需要 foreground service type `dataSync` | ✅ 2026-10-17 P1 必做:AndroidManifest 加 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` permission + `<service android:foregroundServiceType="dataSync">` |

---

## Open Questions(2026-10-17 全部拍板 ✅)

- [x] 实时性默认(手动刷新)接受吗? — **是**
- [x] 锁屏默认(MVP 不后台)接受吗? — **否,改 foreground service 常驻**
- [x] 认证默认(6 位配对码 + 7 天 cookie)接受吗? — **是**
- [x] 端口默认 8123 接受吗? — **是**
- [x] 是否要先做 P1 prototype 验证 Android HTTP server 可达性,再进 P2? — **是**

历史决策见末尾「历史决策」表。

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
| 2026-10-17 | 升 v0.5.5 → **v2.0.0+** | LAN_WEB 作为里程碑主功能,跨过 v0.5.0 / v0.6.0 / v0.7.0 几个中间里程碑;`pubspec.yaml` 1.0.0+104 → 2.0.0+105 |
| 2026-10-17 | 锁屏后台:**foreground service 常驻**(覆盖默认) | user 决定 use foreground service,不等 P4 后再做;P1 直接做(`flutter_foreground_task` + AndroidManifest `dataSync` type) |
| 2026-10-17 | 实时性 / 认证 / 端口 / P1 prototype / 自启时机:全部按默认 | 文档默认值已合理,无 override 必要 |
