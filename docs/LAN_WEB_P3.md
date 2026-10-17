# LAN_WEB v2.0.0 P3 Web 伴侣端

> 局域网 Web 伴侣端的 Flutter Web 端。同 WiFi 设备浏览器访问 gridly 的 8123 端口,
> 配对后看流水 / 记一笔 / 管理已配对设备。

详细设计见 [`LAN_WEB.md`](LAN_WEB.md) · API 文档 [`LAN_WEB_API.md`](LAN_WEB_API.md)

---

## 架构

```
┌─────────────────────────────────────────────────────┐
│ macOS app(gridly 桌面版)                              │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │ shelf server 跑在 main isolate               │   │
│  │                                              │   │
│  │  GET /  → Flutter web build (build/web/)     │   │
│  │  GET /api/health                             │   │
│  │  GET/POST/DELETE /api/auth/*                 │   │
│  │  GET/POST/PUT/DELETE /api/ledgers            │   │
│  │  GET/POST/PUT /api/categories                │   │
│  │  GET /api/stats/*                            │   │
│  │  GET/PUT /api/budget                         │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  fg_service(Android only)keep-alive 保活进程       │
└─────────────────────────────────────────────────────┘
            ▲
            │ 同 WiFi / 同源
            ▼
┌─────────────────────────────────────────────────────┐
│ Chrome 浏览器 → http://<mac IP>:8123/                │
│                                                     │
│  Flutter Web Build                                  │
│  - lib/web_main.dart(独立 entry)                    │
│  - lib/web/web_app.dart(app 壳 + 路由)             │
│  - lib/web/log_in_page.dart(6 位配对码)            │
│  - lib/web/ledger_list_page.dart(流水 + 月度)      │
│  - lib/web/add_ledger_sheet.dart(记一笔 modal)     │
│  - lib/web/sessions_page.dart(配对设备管理)        │
│  - lib/web/api_client.dart(WebApiClient)            │
└─────────────────────────────────────────────────────┘
```

**关键决策**:
- **同源**:Web UI 和 API 在同一端口(8123),CORS 不需要,但中间件保留 CORS 兼容未来跨源
- **cookie 自动**:BrowserClient 自带 same-origin cookie 支持,POST /api/auth/pair 后 Set-Cookie 浏览器自动存
- **独立 web entry**:`lib/web_main.dart` 区别于 `lib/main.dart`(mobile),不调 fg_service / 不 seed
- **SPA fallback**:静态文件找不到 + 不像 flutter 资源 → 自己读 index.html 返(让 Flutter router 接管)
- **Material 3 跟 mobile 一致**:复用 mobile 的 AppBrand primary (#1A6CFF),颜色 token 对齐

---

## 实际页面

### 1. Log in 页(`log_in_page.dart`)
- 大号 monospace 6 位配对码输入(digits only,限长 6,autofocus)
- 设备名(可选,默认 'Web Browser')
- 「配对」FilledButton → POST /api/auth/pair
- 错误码中文化显示(errorContainer 红卡)
- 错误码:invalid_or_expired / invalid_code_format / rate_limited

### 2. Ledger list 页(`ledger_list_page.dart`)
- 月份选择器(上/下月切换,当月 disable 下月)
- 月度汇总卡片(收入 / 支出 / 结余 / 笔数,正负值颜色区分)
- 流水 ListView(每条:分类 icon + 名称 + note + ±金额 + 时间)
- 下拉刷新(RefreshIndicator)
- 错误视图 + 重试按钮
- 空态:本月还没有流水
- AppBar:设备按钮 → 配对设备管理,注销按钮 → POST /api/auth/logout
- FAB 记一笔 → showModalBottomSheet

### 3. Add ledger sheet(`add_ledger_sheet.dart`)
- SegmentedButton:type 切换(expense / income / balance)
- 切换 type 时自动重置 category(过滤该 type 的 cat 列表)
- 大号金额输入(¥ prefix,只允许 2 位小数)
- 分类 DropdownButtonFormField(色点 + 名称)
- 日期选择(默认 now)
- 备注(max 200 字,可选)
- 保存 → POST /api/ledgers → 关 modal + 回调刷新列表

### 4. Sessions 页(`sessions_page.dart`)
- GET /api/auth/sessions 列已配对设备(API 已排除自己)
- 每个设备:自动匹配 icon 的 CircleAvatar(看 label 字符串)+ label + 上次活跃 + 配对时间
- 右上删除按钮 → AlertDialog 二次确认 → DELETE /api/auth/sessions/<token>
- 撤销成功 snackbar 提示 + 刷新列表
- 空态:只有你一个设备配对
- 下拉刷新

---

## Dev 迭代流程

```bash
# 一次性:装 web platform(已 commit,以后不需)
flutter create --platforms=web .  # 之前已做

# 改 web 代码后重 build:
flutter build web --target=lib/web_main.dart --release

# 跑 macOS app(server 跑 main isolate)
flutter run -d macos

# Chrome 浏览器开:
http://localhost:8123/        # 或 192.168.x.x:8123 同 WiFi
```

> ⚠️ web 平台不能用 `dart:ffi`(sqlite3/drift 在 web 不可用)
> 所以 `lib/web/` 不能 import `app_database.dart` / `drift` / `sqlite3`
> 共享常量(版本号)抽到 `lib/core/server/version.dart` 独立文件

---

## 路由分发(同端口 SPA + API)

shelf_router 路由匹配优先级:

```
1. /api/health                  → JSON health
2. /api/auth/{code,pair,logout,sessions}
3. /api/ledgers, /api/categories, /api/stats, /api/budget
4. /api/<anything>              → 404 JSON
5. /<anything>                  → Flutter web static / SPA fallback(index.html)
```

- `/<anything>` catch-all:先查 build/web/ 静态文件;找不到 + 不是文件 + 不是 flutter 资源 → fallback 到 `index.html` 让 Flutter router 接管
- auth middleware 跳过非 `/api/*` 路径(静态文件 / SPA 不需要 cookie)
- 配对流程前:web 客户端无 cookie,只走 `/api/auth/*`;配对成功后所有受保护端点都自动带 cookie

---

## 已落地文件

| 文件 | 用途 |
|---|---|
| `web/index.html` | Flutter web HTML shell(改 title) |
| `web/favicon.png` + `web/icons/` | 图标 |
| `web/manifest.json` | PWA manifest |
| `lib/web_main.dart` | Web 端独立 entry(不调 fg_service / 不 seed) |
| `lib/web/web_app.dart` | App 壳 + LogInPage ↔ LedgerListPage 切换 |
| `lib/web/api_client.dart` | WebApiClient + ApiException |
| `lib/web/log_in_page.dart` | 6 位配对码输入 + 错误码中文化 |
| `lib/web/ledger_list_page.dart` | 流水 + 月度 + FAB 记一笔 |
| `lib/web/add_ledger_sheet.dart` | 记一笔 modal(type + category + amount + note + date) |
| `lib/web/sessions_page.dart` | 配对设备管理(list + revoke) |
| `lib/core/server/version.dart` | 共享版本常量(web 不能 import app_database) |

---

## 已知限制 / P4+ 待补

- **无实时推送**:web 端需要手动下拉刷新(滑窗 60/s 内 OK);P4+ 考虑 SSE / WebSocket
- **无 PWA 安装提示**:`manifest.json` 在了但没注册 service worker,P4+ 加
- **无 i18n**:`appLocalizations` 在 mobile 已经有,web 端暂用 hardcode 中文
- **无 light/dark theme 切换**:web 端只 light 模式,跟 mobile dark 模式不同
- **rate limit 60/s 全局**:没 per-IP 区分,所有同 token 共享,LAN 场景足够
- **无 Playwright E2E**:`scripts/lan_web_smoke.sh` curl 测 API,Playwright 测 web UI 待 P3 commit 8+
