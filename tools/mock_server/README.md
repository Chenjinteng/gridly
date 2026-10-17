# gridly LAN_WEB mock server

> 让 React web (web-react/) 在 Vite dev 模式下能脱离 Flutter app 独立跑通。

## 为什么需要这个

LAN_WEB P4 (v2.1.0) 把 web UI 拆出去做 React (Vite + TanStack Table),但 web 端的 REST endpoint 是 Flutter app 起的 shelf_plus server (8123 端口)。每次改 web 都要:

1. macOS 上 `flutter run -d macos`
2. 等 5-10 秒启动,GridlyServer 起来
3. 配对 (6 位码) → 才能用
4. 改 React → Vite HMR 实时刷新,但 base url 还是 `:8123`

这套流程 dev iteration 慢。Mock server 用 Python stdlib 起一个 in-memory 替代:

- 启动 1 秒,无 Dart 编译等待
- 启动自带 1 个 active session,浏览器直接访问,无需配对
- 默认配对码 `123456` 不过期(生产是 5 分钟),dev 反复测试不被踢

## 启动方式

```bash
# 默认 0.0.0.0:8123 (跟真 server 同端口,web 端不用改 base url)
python3 tools/mock_server/server.py

# 改端口
python3 tools/mock_server/server.py --port 8200
```

启动后 console 会打印:
```
[mock_server] gridly LAN_WEB mock server listening on http://0.0.0.0:8123
[mock_server] default pairing code: 123456
[mock_server] default session token: 7e51f3b3...
[mock_server] (cookie: gridly_session=7e51f3b3...)
[mock_server] seed: 22 cats / 3 assets / 30 ledgers / 1 sessions
```

## 用法

### 配合 Vite dev (web-react)

`web-react/vite.config.ts` 已经配好 proxy:`/api/*` → `http://localhost:8123`。

```bash
# Terminal 1
python3 tools/mock_server/server.py

# Terminal 2
cd web-react && npm run dev
```

浏览器开 `http://localhost:5173`,直接看到 Ledger 页面(mock server 自带 session,跳过配对)。

### 直接 curl

```bash
# 健康检查(暴露 default token + pairing code)
curl http://localhost:8123/api/health | jq

# 用 default session token 查流水
curl -H "Cookie: gridly_session=7e51f3b3..." http://localhost:8123/api/ledgers | jq
```

或者更简单:
```bash
# 配对(返新 session + Set-Cookie)
curl -i -X POST -H "Content-Type: application/json" \
  -d '{"code":"123456","label":"curl test"}' \
  http://localhost:8123/api/auth/pair
```

## seed 数据

| 资源 | 数量 | 备注 |
|---|---|---|
| Categories | 22 | 12 expense + 5 income + 2 investment + 1 benefit + 1 receivable(债务) + 1 other,跟 Dart `DefaultCategories` 完全对齐 |
| Assets | 3 | 现金 / 银行卡 / 微信支付 (cash_flow 段) |
| Ledgers | 30 | 过去 180 天随机分布:18 expense + 6 income + 6 balance(调拨) |
| Sessions | 1 | "Mock Device",启动即 active,token 每次启动新生成,启动日志打印 |
| Monthly budget | 1 | 当前月 5000 + 餐饮 1500 + 交通 500 |

随机 seed 固定为 42,保证每次重启 demo 数据一致(方便截图对比)。

## 跟真 server 的差异

| 项 | 真 server (Flutter shelf_plus) | mock server |
|---|---|---|
| 数据持久化 | SQLite + SharedPreferences | in-memory,重启清空 |
| 配对码 TTL | 5 分钟 | 不过期(每次 current() 自动续期) |
| 默认 session | 无,必须配对 | 启动自带 1 个,跳过配对 |
| 限流 / 防滥用 | 60 req/s,1MB body limit | 无(纯 dev 用) |
| CORS | 内部网络,默认 reject 跨域 | `*` (任何 origin,方便 web dev) |
| Security headers | 全套 (X-Content-Type-Options 等) | 无 |
| Health response | 实时 DB count + uptime | 同样 (3 个 count + uptime + serverTime) |

**字段 shape 完全一致**:cookie 名 `gridly_session`、Set-Cookie 格式、JSON envelope (`{ok}` / `{error}`)、字段命名(camelCase)、时间格式(ISO8601 + `Z`)。

## 集成到 Flutter app

未来 web 端功能稳定后,可以**复用**这个 mock server 做 integration test:

```python
# 用 mock_server 跑 e2e 测试
mock = subprocess.Popen(['python3', 'tools/mock_server/server.py', '--port', '8123'])
time.sleep(1)  # wait for startup
# 跑 playwright / cypress 测试
# ...
mock.terminate()
```

无需起 Flutter app,跑一次测试 < 2 秒。

## 配套改动

- `web-react/vite.config.ts`:加 `/api` proxy → `http://localhost:8123`
- `docs/LAN_WEB.md`:P4 章节描述 mock 模式
- React web 不需要任何改动:它跟真 server / mock server 完全透明

## 已知限制

- 投资 / 福利 / 债务段暂时只 seed 了 cat,没有对应 account(真 app 也只在 user 主动建账户时才有,所以 demo 不暴露)
- 报表 API 的"投资段已实现但暂未启用"语义没模拟(monthly stats 只算 income/expense,跟真 server D62 口径一致)
- WebSocket / SSE 没实现(LAN_WEB v2.x 不需要 push,web 走轮询)
