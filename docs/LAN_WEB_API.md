# LAN_WEB v2.0.0 API 文档

> 局域网 Web 伴侣端的 REST API。
> 同 WiFi 设备可通过浏览器 / curl / 自写客户端访问,无需公网、无需账号。
>
> 详细设计见 [`LAN_WEB.md`](LAN_WEB.md)

---

## 基础约定

- **Base URL**:`http://<gridly 设备 IP>:8123`(默认端口 8123,见 `gridly_server.dart` 的 `kLanWebPort`)
- **鉴权**:首次访问需 6 位配对码(5 分钟有效),配对成功后拿 7 天 cookie
- **Cookie 名**:`gridly_session`
- **请求 / 响应格式**:JSON(`Content-Type: application/json`)
- **错误格式**:`{"error": "<code>"}`,HTTP 状态码:400 / 401 / 404 / 500

### 公共端点(无需 cookie)
- `GET /`  —— 健康检查 + 简单 JSON
- `GET /api/auth/code`  —— 拿当前 6 位配对码
- `POST /api/auth/pair`  —— 提交 6 位码 → 200 + Set-Cookie
- `POST /api/auth/logout`  —— 撤销当前 session + Clear-Cookie
- `GET /api/auth/sessions`  —— 列已配对设备
- `DELETE /api/auth/sessions/<token>`  —— 撤销某设备

### 受保护端点(需 cookie)
- `GET /api/ledgers?from&to&type&category&keyword&page&pageSize`
- `GET /api/ledgers/<id>`
- `POST /api/ledgers`
- `PUT /api/ledgers/<id>`
- `DELETE /api/ledgers/<id>`
- `GET /api/categories?type`
- `POST /api/categories`
- `PUT /api/categories/<id>`
- `GET /api/stats/monthly?year&month`
- `GET /api/stats/categories?from&to`
- `GET /api/stats/top?from&to&limit`
- `GET /api/budget?year&month`
- `PUT /api/budget`

---

## 0. 健康检查

```bash
curl http://192.168.1.5:8123/
```

```json
{
  "name": "gridly web",
  "version": "2.0.0",
  "build": 120,
  "transactions": 0,
  "phase": "P1 prototype"
}
```

> `transactions` 字段是 placeholder(始终 0),真实数据从 P2 commit 3 加 `/api/ledgers` 后通过该接口拉取。

---

## 1. 鉴权流程

### 1.1 拿配对码(无需 cookie)

```bash
curl http://192.168.1.5:8123/api/auth/code
```

```json
{
  "code": "648402",
  "expiresAt": "2026-10-17T10:39:00.000Z",
  "remainingSeconds": 218
}
```

> 5 分钟过期;过期后再调,服务端自动生成新码,旧码同时失效。
> UI 端(手机 app)有「显示配对码」按钮,直接展示给用户。

### 1.2 提交配对码 → 拿 cookie

```bash
curl -X POST http://192.168.1.5:8123/api/auth/pair \
  -H 'Content-Type: application/json' \
  -d '{"code":"648402","label":"My Laptop"}' \
  -c cookies.txt -i
```

Response headers:
```
HTTP/1.1 200 OK
Set-Cookie: gridly_session=abc123...; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800
Content-Type: application/json
```

Response body:
```json
{
  "ok": true,
  "session": {
    "token": "abc123...",
    "createdAt": "2026-10-17T10:35:00.000Z",
    "lastSeenAt": "2026-10-17T10:35:00.000Z",
    "label": "My Laptop"
  }
}
```

可选 `label` 字段(便于在「已配对设备」里区分设备);空就 fallback 到 "Device"。

### 1.3 列已配对设备

```bash
curl -b cookies.txt http://192.168.1.5:8123/api/auth/sessions
```

```json
{
  "sessions": [
    {
      "token": "abc123...",
      "createdAt": "2026-10-17T10:35:00.000Z",
      "lastSeenAt": "2026-10-17T10:36:00.000Z",
      "label": "My Laptop"
    },
    {
      "token": "def456...",
      "createdAt": "2026-10-16T08:00:00.000Z",
      "lastSeenAt": "2026-10-17T09:50:00.000Z",
      "label": "Work Desktop"
    }
  ]
}
```

> 当前 session 不在列表里(避免误删自己);用 `lastSeenAt` 排序看谁在活跃。

### 1.4 撤销某设备(不是当前)

```bash
curl -X DELETE -b cookies.txt \
  http://192.168.1.5:8123/api/auth/sessions/def456...
```

```json
{ "ok": true }
```

错误(防误删自己):
- 400 `cannot_revoke_current` — 试图撤销自己
- 404 `session_not_found` — token 不存在

### 1.5 注销(撤销当前)

```bash
curl -X POST -b cookies.txt -c cookies.txt \
  http://192.168.1.5:8123/api/auth/logout -i
```

Response headers:
```
HTTP/1.1 200 OK
Set-Cookie: gridly_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0
```

服务端同时从持久化里删 session;7 天内再次访问会 401。

---

## 2. 流水(ledgers)

### 2.1 列表 + 过滤 + 分页

```bash
curl -b cookies.txt "http://192.168.1.5:8123/api/ledgers?page=1&pageSize=50"
```

支持 query params:
- `from` `to`:ISO 8601 日期(只比 `occurredAt` >= from,<= to,含端点)
- `type`:`expense` | `income` | `balance`
- `category`:分类 ID(int)
- `keyword`:note 模糊搜索(LIKE %keyword%)
- `page`(默认 1)+ `pageSize`(默认 50)

```json
{
  "ledgers": [
    {
      "id": 42,
      "amount": 50.00,
      "type": "expense",
      "categoryId": 1,
      "occurredAt": "2026-10-17T12:30:00.000Z",
      "note": "lunch",
      "accountId": 1,
      "destinationAccountId": null,
      "createdAt": "2026-10-17T12:30:01.000Z",
      "updatedAt": "2026-10-17T12:30:01.000Z"
    }
  ],
  "page": 1,
  "pageSize": 50
}
```

### 2.2 单笔

```bash
curl -b cookies.txt http://192.168.1.5:8123/api/ledgers/42
```

```json
{ "ledger": { /* 同 2.1 字段 */ } }
```

### 2.3 新增

```bash
curl -X POST -b cookies.txt http://192.168.1.5:8123/api/ledgers \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": 50.00,
    "type": "expense",
    "categoryId": 1,
    "occurredAt": "2026-10-17T12:30:00Z",
    "note": "lunch",
    "accountId": 1
  }' -i
```

必填:`amount` / `type` / `categoryId` / `occurredAt`
选填:`note` / `accountId`(缺省 → 第一个 cash_flow 账户) / `destinationAccountId`(投资场景)

Response:201 + `{ "ledger": {...} }`
Errors:
- 400 `invalid_body` — body 不是 JSON object
- 400 `missing_amount` / `invalid_type` / `missing_categoryId` / `missing_or_invalid_occurredAt`

### 2.4 修改

```bash
curl -X PUT -b cookies.txt http://192.168.1.5:8123/api/ledgers/42 \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": 60.00,
    "note": "lunch + tip"
  }' -i
```

partial update,只改 body 里给的字段。

### 2.5 删除

```bash
curl -X DELETE -b cookies.txt \
  http://192.168.1.5:8123/api/ledgers/42 -i
```

Response:200 `{ "ok": true }` 或 404 `ledger_not_found`

---

## 3. 分类(categories)

### 3.1 列表

```bash
# 全部
curl -b cookies.txt http://192.168.1.5:8123/api/categories

# 按 type 过滤
curl -b cookies.txt "http://192.168.1.5:8123/api/categories?type=expense"
```

`type` 值:`expense` | `income` | `investment` | `benefit` | `liability` | `other`

```json
{
  "categories": [
    {
      "id": 1,
      "name": "餐饮",
      "type": "expense",
      "color": 4281783992,         // int (ARGB),web 端自己 int → hex
      "icon": "restaurant",
      "sortOrder": 10,
      "isSystem": true            // 系统预置(true)vs 用户自定义(false)
    }
  ]
}
```

### 3.2 新增

```bash
curl -X POST -b cookies.txt http://192.168.1.5:8123/api/categories \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "宠物",
    "type": "expense",
    "color": 4281856109,
    "icon": "pets",
    "sortOrder": 100
  }'
```

必填:`name` / `type`
选填:`color`(默认 `#94A3B8` = 4281773976)/ `icon`(默认 `category_outlined`) / `sortOrder`(缺省 = 同 type 已有 max + 10)

Errors:400 `missing_name` / `invalid_type`

### 3.3 修改

```bash
curl -X PUT -b cookies.txt http://192.168.1.5:8123/api/categories/47 \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "宠物用品",
    "color": 4288216575
  }'
```

partial update。

---

## 4. 报表(stats)

### 4.1 月度汇总

```bash
curl -b cookies.txt "http://192.168.1.5:8123/api/stats/monthly?year=2026&month=10"
```

```json
{
  "year": 2026,
  "month": 10,
  "income": 12500.00,
  "expense": 8230.50,
  "balance": 4269.50,
  "transactionCount": 47
}
```

> 口径跟 home 页一致(D62 收紧):income/expense 只算 cash_flow 段(`cat.type='cash_flow'`)。

### 4.2 期间分类饼图(支出 only)

```bash
curl -b cookies.txt "http://192.168.1.5:8123/api/stats/categories?from=2026-10-01&to=2026-10-31"
```

```json
{
  "from": "2026-10-01T00:00:00.000Z",
  "to": "2026-10-31T00:00:00.000Z",
  "total": 8230.50,
  "items": [
    {
      "categoryId": 1,
      "categoryName": "餐饮",
      "color": 4281783992,
      "amount": 3200.00,
      "percentage": 0.389
    }
    // ...
  ]
}
```

按 amount 降序。

### 4.3 Top N

```bash
curl -b cookies.txt "http://192.168.1.5:8123/api/stats/top?from=2026-10-01&to=2026-10-31&limit=10"
```

`limit` 默认 10。

```json
{
  "from": "2026-10-01T00:00:00.000Z",
  "to": "2026-10-31T00:00:00.000Z",
  "items": [
    { "categoryId": 1, "categoryName": "餐饮", "color": 4281783992, "amount": 3200.00 }
    // ...
  ]
}
```

---

## 5. 月度预算(budget)

### 5.1 读

```bash
curl -b cookies.txt "http://192.168.1.5:8123/api/budget?year=2026&month=10"
```

```json
{
  "year": 2026,
  "month": 10,
  "total": 8000.00,         // 当月总额度
  "spent": 3200.00,         // 当月实际支出合计
  "categoryBudgets": [
    {
      "categoryId": 1,
      "categoryName": "餐饮",
      "color": 4281783992,
      "amount": 3000.00,     // 该分类子额度
      "spent": 2200.00,      // 该分类当月实际支出
      "remaining": 800.00    // 子额度 - spent
    }
    // ...
  ]
}
```

### 5.2 写

```bash
curl -X PUT -b cookies.txt http://192.168.1.5:8123/api/budget \
  -H 'Content-Type: application/json' \
  -d '{
    "year": 2026,
    "month": 10,
    "total": 8000.00,
    "categoryBudgets": [
      { "categoryId": 1, "amount": 3000.00 },
      { "categoryId": 2, "amount": 2000.00 }
    ]
  }'
```

- `total` 必填 → 覆盖当月总额度
- `categoryBudgets` 选填 → 覆盖式 upsert,只更新传了的;没传的不变

---

## 6. 错误码速查

| HTTP | error code | 含义 |
|---|---|---|
| 400 | `invalid_body` | body 不是 JSON object |
| 400 | `invalid_id` | URL 路径里的 ID 不是 int |
| 400 | `missing_*` | 必填字段缺失(amount / name / year / total 等) |
| 400 | `invalid_type` | type 字段值不在白名单 |
| 400 | `cannot_revoke_current` | 试图撤销自己的 session |
| 401 | `missing_cookie` | 缺 cookie 或 cookie 无 gridly_session 字段 |
| 401 | `session_expired` | cookie 里的 token 找不到 / 过期 |
| 401 | `invalid_or_expired` | 6 位配对码错或过期 |
| 401 | `invalid_code_format` | 配对码不是 6 位数字 |
| 404 | `*_not_found` | 资源不存在(ledger / category / session) |
| 500 | (无 error code) | 内部错误,看 `flutter run` 终端 log |

---

## 7. 完整工作流示例

```bash
URL="http://192.168.1.5:8123"

# 1. 启动时拿配对码
CODE=$(curl -s $URL/api/auth/code | jq -r .code)
echo "Pairing code: $CODE"

# 2. 配对,保存 cookie
curl -X POST $URL/api/auth/pair \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"$CODE\",\"label\":\"CLI\"}" \
  -c cookies.txt > /dev/null

# 3. 列出本月流水
curl -s -b cookies.txt "$URL/api/ledgers?from=2026-10-01&to=2026-10-31" | jq .

# 4. 拉本月汇总 + 分类饼图
curl -s -b cookies.txt "$URL/api/stats/monthly?year=2026&month=10" | jq .
curl -s -b cookies.txt "$URL/api/stats/categories?from=2026-10-01&to=2026-10-31" | jq .

# 5. 新增一笔
curl -X POST -b cookies.txt $URL/api/ledgers \
  -H 'Content-Type: application/json' \
  -d '{"amount":50,"type":"expense","categoryId":1,"occurredAt":"2026-10-17T12:30:00Z","note":"lunch"}' | jq .

# 6. 注销
curl -X POST -b cookies.txt -c cookies.txt $URL/api/auth/logout > /dev/null
```

---

## 8. 安全注意

- 同 WiFi 配对后,同 WiFi 任何人都能拿到 cookie(裸 HTTP)
- 文档明确要求「勿连公共 WiFi」(家用 / 自建 AP 没事)
- 撤销 / 过期 / 切 OFF 都能立即断已配对设备
- 配对码 5 分钟过期,已配对设备 7 天内任意访问无需重输
- Android 15 `dataSync` 限制:24h 内 6h,超时 fg_service 会被系统 kill
- (P4 计划)加 IP 段白名单 + 简易 token 轮换

详细架构与决策见 [`LAN_WEB.md`](LAN_WEB.md)。
