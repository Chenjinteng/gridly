# LAN_WEB P4 — React web app 完整闭环

(2026-10-17)

## 背景

P3 跑的 Flutter web (commits 1-13),但用户实测 web UI 不行,主要是表格录入 UX 差。
2026-10-17 user 拍板:换 React 重写 web,设计 A (Navy Classic) 拍板,表格样式 + 设计拍板的 demo 拍 A。

## 决策

| 决策 | 选项 | 取舍 |
|---|---|---|
| 框架 | Flutter web / React / Vue | **React** — CanvasKit 慢、DataTable 太基础、cell 编辑/键盘导航要重做 |
| 路由 | React Router v6 | 简单 SPA 3 页够用 |
| 表格 | TanStack Table v8 | 排序/筛选/虚拟化一行套完,bundle 73KB gzip |
| 构建 | Vite 5 | 比 webpack 快 10x,天然 ESM |
| 后端 | 不动现有 20 个 REST endpoint | React 消费现有 API,加 `/api/assets` 一个新端点 |
| 设计 | 3 套候选 demo (A/B/C) | 拍 **A · Navy Classic** (#1E3A8A + macOS 字体) |

## 实施

### P4 commit 1: 脚手架 + 设计 demo (512dfcb)
- `web-react/` 目录:Vite + React 18 + TypeScript + TanStack Table
- `src/demos/{A,B,C,DemoLayout}.tsx` 3 套配色 demo,`?demo=a/b/c` 切换
- 拍板 A,设计 token 抽到 `src/theme.ts`
- 删 `src/demos/` (拍板后不再需要)

### P4 commit 2-4: 真实 web app (9ce8c16)
- `src/api/client.ts` — 20+ 个 REST endpoint 类型化 client (cookie auth)
- `src/App.tsx` — 路由 + auth gate (`/api/ledgers?limit=1` 探测 401,不用 listSessions 因为那是 public)
- `src/components/TopBar.tsx` — 顶部栏
- `src/components/TypeChip.tsx` — 类型 chip
- `src/components/AddTransactionModal.tsx` — 记一笔 (3 段 type + 分类下拉 + 账户下拉 + 调拨转入账户 + 金额 + 备注 + 日期)
- `src/pages/Login.tsx` — 6 位配对码 + device name + device icon picker (5 个 emoji)
- `src/pages/Ledger.tsx` — 摘要 3 卡 + 月份/类型筛选 + 搜索 + TanStack Table (排序/hover)
- `src/pages/Sessions.tsx` — 已配对设备列表 + revoke (相对时间格式化)

### P4 commit 5: React 打包进 .app (this)
- `web-react/vite-env.d.ts` — Vite type ref
- Xcode `Bundle Web Assets` phase 改路径:`$SRCROOT/../web-react/dist/` → `.app/Contents/Resources/web/`
- `scripts/dev_run_macos.sh` 重写:支持 `--build-web` 重 build React,默认 release,自动 export `GRIDLY_DEV_AUTOSTART=1`
- 删 `scripts/build_web_for_macos.sh` (Flutter web 专用,废弃)
- 删 `scripts/lan_web_smoke.sh` (过时)

### 后端补:
- `lib/core/server/handlers/assets_handler.dart` — `GET /api/assets` 列出账户(按 displayOrder)
- `lib/core/server/handlers/ledgers_handler.dart` — `GET /api/ledgers` 加 LEFT JOIN categories + assets,响应包 `categoryName` + `accountName`

## 端到端验证(2026-10-17 14:11 实测)

```
1. flutter build macos --debug
   - Bundle Web Assets phase 跑:[lan_web/bundle] copying web-react/dist/ -> .app/Resources/web/
   - 236K React 静态资源进 .app

2. GRIDLY_DEV_AUTOSTART=1 build/macos/Build/Products/Debug/gridly.app/Contents/MacOS/gridly
   - 启 server 在 8123
   - [lan_web] webDir walk-up script → .app Resources: .../gridly.app/Contents/Resources/web

3. curl http://localhost:8123/api/health
   → {"name":"gridly web","version":"2.0.0","build":135,"phase":"P2 API ready","transactions":2}

4. Chrome http://localhost:8123/
   - React app 加载 (200 OK, 368 bytes index.html)
   - JS 加载 (200 OK, 235KB bundle)
   - 表格显示 2 行真实数据
   - 摘要:支出 ¥38.50 / 收入 ¥12,000.00 / 结余 ¥11,961.50
```

## 一条命令闭环

```bash
./scripts/dev_run_macos.sh --build-web
```

自动:
1. `cd web-react && npm run build` (Vite 出 dist/)
2. `flutter run -d macos` (Xcode build 触发 Bundle Web Assets phase 拷进 .app)
3. 启 .app + `GRIDLY_DEV_AUTOSTART=1` (跳过 UI toggle,server 自动起)

Chrome 开 `http://localhost:8123/` + 6 位配对码登录即可。

## Bundle 对比

| 产物 | 大小 | 备注 |
|---|---|---|
| Flutter web 之前 (P3) | 2.7MB main.dart.js + 3MB canvaskit + assets | CanvasKit 慢,DataTable 简陋 |
| React web (P4) | 236K 总 (235K JS + 0.37K HTML) | 73KB gzip,加载 10x 快 |
| 减小 | -98% (-5.5MB → 236K) | |

## 已知限制(P5+)

1. **未做**:
   - in-line cell edit (现在要改数据先点 ledger 没实现)
   - 批量录入 (现在一行 POST,Phase 1 简化)
   - dark mode
   - 撤销 配对 UI 测试 (代码写了但未实测)
   - 调拨 (transfer) 流水类型测试 (mobile app 用 same 字段,但 web 端没造数据测)
2. **APK 路径**:
   - APK 构建不跑 `flutter build web` 也不跑 `npm run build`,所以 React web 不进 APK
   - APK 大小不变
3. **mobile app 路径**:
   - lib/web_main.dart + lib/web/* 还在(untracked,Flutter web 入口)
   - 删不删都行,反正 flutter run -d macos 不读它

## 文件树

```
gridly/
├── web-react/                  # React web (新)
│   ├── src/
│   │   ├── api/client.ts       # 20+ endpoint client
│   │   ├── components/         # TopBar, TypeChip, AddTransactionModal
│   │   ├── pages/              # Login, Ledger, Sessions
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   ├── theme.ts            # 设计 A 色 token
│   │   └── vite-env.d.ts
│   ├── package.json
│   ├── tsconfig.json
│   ├── vite.config.ts
│   └── dist/                   # vite build 产物(committed? no, gitignored)
├── lib/                        # Flutter mobile (unchanged)
├── docs/LAN_WEB_P4.md          # 本文件
└── scripts/dev_run_macos.sh    # 一条命令闭环
```