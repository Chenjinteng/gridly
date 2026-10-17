#!/usr/bin/env python3
# tools/mock_server/server.py
# LAN_WEB mock server (decoupled from Flutter app)
#
# Purpose:
#   - 让 React web (web-react/) 在 Vite dev (5173) 下能独立于 Flutter app 跑通,
#     不用每次启动 macOS Flutter app 才能联调。
#   - 实现 gridly 后端 LAN_WEB v2.0.0 全部 20+ REST endpoint 的 in-memory 模拟。
#   - 启动时 seed:22 分类 + 3 账户 + 30 流水 + 1 active session,
#     配对码固定 "123456" 不过期,web 直接登录就能用。
#
# 跟真实后端的差异(刻意简化):
#   - 全部数据 in-memory,重启清空(无持久化)
#   - 配对码不过期(默认 5 分钟太短,影响 demo)
#   - 自动 seed 一个 session("Mock Device"),web 启动无需配对
#   - 不做 rate limit / body size limit / security headers(纯 dev 用)
#
# 跟真实后端一致的字段:
#   - Cookie name: gridly_session
#   - Set-Cookie: gridly_session=TOKEN; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800
#   - 401: {error: "missing_cookie"|"session_expired"|"invalid_or_expired"|...}
#   - 200/201/400/404 JSON envelope 跟 Dart json_helpers.dart 完全对齐
#
# 启动:
#   python3 tools/mock_server/server.py            # 默认 0.0.0.0:8123
#   python3 tools/mock_server/server.py --port 8200
#
# 依赖:Python 3.9+ stdlib,无第三方包
#
# 配套 Vite proxy(参见 web-react/vite.config.ts):
#   /api/* → http://localhost:8123
from __future__ import annotations

import argparse
import json
import os
import random
import secrets
import sys
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse


# ============================================================
# Constants (跟 Dart 端对齐)
# ============================================================

GRIDLY_VERSION = "2.1.0"  # 跟 P4 React app 同步(覆盖 Dart 端 2.0.0 标识)
GRIDLY_BUILD = 156        # 跟 pubspec.yaml 2.0.0+155 大致对齐(此 mock 自增)
GRIDLY_DB_SCHEMA = 9      # 跟 Dart health_handler 默认 schemaVersion 对齐

COOKIE_NAME = "gridly_session"
SESSION_MAX_AGE = 604800  # 7 天 (跟 Dart LanWebAuth.sessionTtl 一致)
PAIRING_CODE_TTL = 300    # mock 端放宽到 300s 但不过期自动清(每次 current() 都续期)

# AppCategory / AppBrand 色 (ARGB int) — 跟 Dart AppCategory 数值对齐
# web 端 hex 字符串时直接 (color >>> 0).toString(16).padLeft(8, '0')
CAT_COLOR = {
    "food": 0xFFEF4444,         # red-500
    "transport": 0xFFF59E0B,    # amber-500
    "shopping": 0xFFEC4899,     # pink-500
    "housing": 0xFF8B5CF6,      # violet-500
    "telecom": 0xFF3B82F6,      # blue-500
    "medical": 0xFF10B981,      # emerald-500
    "education": 0xFF06B6D4,    # cyan-500
    "entertainment": 0xFFF97316, # orange-500
    "home": 0xFFA855F7,         # purple-500
    "beauty": 0xFFF43F5E,       # rose-500
    "pet": 0xFF84CC16,          # lime-500
    "neutral": 0xFF94A3B8,      # slate-400 (其他 / 退款 fallback)
    "salary": 0xFF22C55E,       # green-500
    "bonus": 0xFFEAB308,        # yellow-500
    "invest": 0xFF14B8A6,       # teal-500
    "parttime": 0xFF6366F1,     # indigo-500
    "benefit": 0xFFF472B6,      # pink-400
    "liability": 0xFFDC2626,    # red-600
    "other": 0xFF6B7280,        # gray-500
}

# Default session token (启动就有) — 32 hex chars
DEFAULT_SESSION_TOKEN = "mockdev" + secrets.token_hex(13)  # 7 + 26 = 33? 修一下
DEFAULT_SESSION_TOKEN = "mockdev" + secrets.token_hex(12)  # 7 + 24 = 31? 也不对
# 重做:32 hex chars 总长
DEFAULT_SESSION_TOKEN = (secrets.token_hex(16))[:32]

# 默认配对码(过 5 分钟自动续期)
DEFAULT_PAIRING_CODE = "123456"

# Cash flow 段 type list (跟 Dart stats handler / category handler 对齐)
TX_TYPES = ["expense", "income", "balance"]
CAT_TYPES = ["expense", "income", "investment", "benefit", "liability", "other"]
ASSET_TYPES = ["cash_flow", "investment", "benefit", "fixed_asset", "receivable", "other"]


# ============================================================
# In-memory store (单例,带锁)
# ============================================================

class Store:
    """线程安全的 in-memory 数据存储。

    设计:跟 Dart 端 AppDatabase 表结构对齐,字段名也跟 Drift generated 同名
    (camelCase),handler 直接返回 dict 即可。
    """
    def __init__(self, started_at: datetime):
        self._lock = threading.RLock()
        self.started_at = started_at
        self.server_time = started_at  # 每次 health 调用时更新
        self._auto_id = 1000  # 自增 ID 起点(避开 seed 跟 1-30 冲突)
        # 启动配对码
        self._pairing_code = DEFAULT_PAIRING_CODE
        self._pairing_expires = started_at + timedelta(seconds=PAIRING_CODE_TTL)

        # 启动 session
        self._sessions: dict[str, dict[str, Any]] = {}

        # seed 数据
        self._categories: list[dict[str, Any]] = []
        self._assets: list[dict[str, Any]] = []
        self._transactions: list[dict[str, Any]] = []
        self._monthly_budgets: dict[tuple[int, int], float] = {}
        self._category_budgets: dict[tuple[int, int, int], float] = {}  # (catId, year, month) → amount

        self._seed()

    # --- ID 生成 ---
    def next_id(self) -> int:
        with self._lock:
            self._auto_id += 1
            return self._auto_id

    # --- Pairing ---
    def pairing_current(self) -> dict[str, Any]:
        with self._lock:
            now = datetime.now(timezone.utc)
            if now >= self._pairing_expires:
                self._pairing_code = DEFAULT_PAIRING_CODE
                self._pairing_expires = now + timedelta(seconds=PAIRING_CODE_TTL)
            expires = self._pairing_expires
            remaining = max(0, int((expires - now).total_seconds()))
            return {
                "code": self._pairing_code,
                "expiresAt": expires.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
                "remainingSeconds": remaining,
            }

    def pairing_verify(self, code: str) -> bool:
        with self._lock:
            self.pairing_current()  # 自动续期
            return code == self._pairing_code

    def pairing_clear(self) -> None:
        with self._lock:
            self._pairing_code = DEFAULT_PAIRING_CODE
            self._pairing_expires = datetime.now(timezone.utc) + timedelta(seconds=PAIRING_CODE_TTL)

    # --- Sessions ---
    def sessions_all(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._sessions.values())

    def session_get(self, token: str) -> dict[str, Any] | None:
        with self._lock:
            s = self._sessions.get(token)
            if s is None:
                return None
            # 更新 lastSeenAt
            s["lastSeenAt"] = datetime.now(timezone.utc).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            return s

    def session_create(self, label: str) -> dict[str, Any]:
        with self._lock:
            token = secrets.token_hex(16)  # 32 hex chars
            now = datetime.now(timezone.utc)
            s = {
                "token": token,
                "createdAt": now.isoformat().replace("+00:00", "Z"),
                "lastSeenAt": now.isoformat().replace("+00:00", "Z"),
                "label": label or "Device",
            }
            self._sessions[token] = s
            return s

    def session_revoke(self, token: str) -> bool:
        with self._lock:
            return self._sessions.pop(token, None) is not None

    # --- Categories ---
    def categories_all(self, type_filter: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            if type_filter:
                return [c for c in self._categories if c["type"] == type_filter]
            return list(self._categories)

    def category_get(self, cid: int) -> dict[str, Any] | None:
        with self._lock:
            for c in self._categories:
                if c["id"] == cid:
                    return c
            return None

    def category_create(self, name: str, type_: str, color: int, icon: str, sort_order: int) -> dict[str, Any]:
        with self._lock:
            cid = self.next_id()
            c = {
                "id": cid,
                "name": name,
                "type": type_,
                "color": color,
                "icon": icon,
                "sortOrder": sort_order,
                "isSystem": False,
            }
            self._categories.append(c)
            return c

    def category_update(self, cid: int, fields: dict[str, Any]) -> dict[str, Any] | None:
        with self._lock:
            for c in self._categories:
                if c["id"] == cid:
                    for k, v in fields.items():
                        if v is not None:
                            c[k] = v
                    return c
            return None

    # --- Assets ---
    def assets_all(self) -> list[dict[str, Any]]:
        with self._lock:
            return sorted(self._assets, key=lambda a: a["displayOrder"])

    def asset_get(self, aid: int) -> dict[str, Any] | None:
        with self._lock:
            for a in self._assets:
                if a["id"] == aid:
                    return a
            return None

    # --- Transactions ---
    def transactions_query(
        self,
        from_: datetime | None,
        to_: datetime | None,
        type_: str | None,
        category_id: int | None,
        keyword: str | None,
        page: int,
        page_size: int,
    ) -> tuple[list[dict[str, Any]], int]:
        """返 (ledger_list 含 join name, page)。"""
        with self._lock:
            rows = []
            for t in self._transactions:
                if from_ and t["occurredAt"] < from_.isoformat().replace("+00:00", "Z"):
                    continue
                if to_ and t["occurredAt"] > to_.isoformat().replace("+00:00", "Z"):
                    continue
                if type_ and t["type"] != type_:
                    continue
                if category_id and t["categoryId"] != category_id:
                    continue
                if keyword and keyword.lower() not in (t.get("note") or "").lower():
                    continue
                # join
                cat = self.category_get(t["categoryId"])
                acct = self.asset_get(t["accountId"])
                row = dict(t)
                row["categoryName"] = cat["name"] if cat else None
                row["accountName"] = acct["name"] if acct else None
                rows.append(row)
            # order by occurredAt desc
            rows.sort(key=lambda r: r["occurredAt"], reverse=True)
            page_count = (len(rows) + page_size - 1) // page_size
            start = (page - 1) * page_size
            return rows[start:start + page_size], page

    def transaction_get(self, tid: int) -> dict[str, Any] | None:
        with self._lock:
            for t in self._transactions:
                if t["id"] == tid:
                    return t
            return None

    def transaction_create(self, body: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            tid = self.next_id()
            now = datetime.now(timezone.utc).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            t = {
                "id": tid,
                "amount": float(body["amount"]),
                "type": body["type"],
                "categoryId": int(body["categoryId"]),
                "occurredAt": body["occurredAt"],
                "note": body.get("note"),
                "accountId": int(body.get("accountId") or self._first_cash_asset_id()),
                "destinationAccountId": body.get("destinationAccountId"),
                "createdAt": now,
                "updatedAt": now,
            }
            self._transactions.append(t)
            return t

    def transaction_update(self, tid: int, body: dict[str, Any]) -> dict[str, Any] | None:
        with self._lock:
            for t in self._transactions:
                if t["id"] == tid:
                    if "amount" in body and body["amount"] is not None:
                        t["amount"] = float(body["amount"])
                    if "type" in body and body["type"] is not None:
                        t["type"] = body["type"]
                    if "categoryId" in body and body["categoryId"] is not None:
                        t["categoryId"] = int(body["categoryId"])
                    if "occurredAt" in body and body["occurredAt"] is not None:
                        t["occurredAt"] = body["occurredAt"]
                    if "note" in body:
                        t["note"] = body["note"]
                    if "accountId" in body and body["accountId"] is not None:
                        t["accountId"] = int(body["accountId"])
                    if "destinationAccountId" in body:
                        t["destinationAccountId"] = body["destinationAccountId"]
                    t["updatedAt"] = datetime.now(timezone.utc).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
                    return t
            return None

    def transaction_delete(self, tid: int) -> bool:
        with self._lock:
            for i, t in enumerate(self._transactions):
                if t["id"] == tid:
                    del self._transactions[i]
                    return True
            return False

    def _first_cash_asset_id(self) -> int:
        for a in self._assets:
            if a["type"] == "cash_flow":
                return a["id"]
        raise RuntimeError("no cash_flow asset seeded")

    # --- Budgets ---
    def budget_get(self, year: int, month: int) -> dict[str, Any]:
        with self._lock:
            total = self._monthly_budgets.get((year, month), 0.0)
            # 同期支出按 categoryId
            start = datetime(year, month, 1, tzinfo=timezone.utc)
            if month == 12:
                end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
            else:
                end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
            spent_by_cat: dict[int, float] = {}
            spent_total = 0.0
            for t in self._transactions:
                ts = datetime.fromisoformat(t["occurredAt"].replace("Z", "+00:00"))
                if ts < start or ts >= end:
                    continue
                if t["type"] != "expense":
                    continue
                spent_by_cat[t["categoryId"]] = spent_by_cat.get(t["categoryId"], 0.0) + t["amount"]
                spent_total += t["amount"]
            items = []
            for (cid, y, m), amount in self._category_budgets.items():
                if (y, m) != (year, month):
                    continue
                cat = self.category_get(cid)
                if not cat:
                    continue
                spent = spent_by_cat.get(cid, 0.0)
                items.append({
                    "categoryId": cid,
                    "categoryName": cat["name"],
                    "color": cat["color"],
                    "amount": amount,
                    "spent": spent,
                    "remaining": amount - spent,
                })
            return {
                "year": year,
                "month": month,
                "total": total,
                "spent": spent_total,
                "categoryBudgets": items,
            }

    def budget_put(self, year: int, month: int, total: float, cat_budgets: list[dict[str, Any]] | None) -> dict[str, Any]:
        with self._lock:
            self._monthly_budgets[(year, month)] = total
            if cat_budgets:
                for cb in cat_budgets:
                    cid = int(cb["categoryId"])
                    amount = float(cb["amount"])
                    self._category_budgets[(cid, year, month)] = amount
            return {"ok": True, "year": year, "month": month, "total": total}

    # --- Health counts ---
    def counts(self) -> tuple[int, int, int]:
        with self._lock:
            return len(self._transactions), len(self._categories), len(self._assets)

    # ============================================================
    # Seed
    # ============================================================
    def _seed(self) -> None:
        """启动 seed。22 分类 + 3 资产 + 30 流水 + 1 session。"""
        # --- 22 categories (跟 Dart DefaultCategories 全对齐) ---
        expense_cats = [
            ("餐饮", "restaurant", "food"),
            ("交通", "directions_bus", "transport"),
            ("购物", "shopping_bag", "shopping"),
            ("居住", "home", "housing"),
            ("通讯", "phone_iphone", "telecom"),
            ("医疗", "medical_services", "medical"),
            ("教育", "school", "education"),
            ("娱乐", "movie", "entertainment"),
            ("居家", "chair", "home"),
            ("美妆", "spa", "beauty"),
            ("宠物", "pets", "pet"),
            ("其他", "more_horiz", "neutral"),
        ]
        for i, (name, icon, color_key) in enumerate(expense_cats):
            self._categories.append({
                "id": i + 1,
                "name": name,
                "type": "expense",
                "color": CAT_COLOR[color_key],
                "icon": icon,
                "sortOrder": i if name != "其他" else 99,
                "isSystem": True,
            })

        income_cats = [
            ("工资", "payments", "salary"),
            ("奖金", "card_giftcard", "bonus"),
            ("理财", "savings", "invest"),
            ("兼职", "work", "parttime"),
            ("退款", "replay", "neutral"),
        ]
        offset = len(self._categories)
        for i, (name, icon, color_key) in enumerate(income_cats):
            self._categories.append({
                "id": offset + i + 1,
                "name": name,
                "type": "income",
                "color": CAT_COLOR[color_key],
                "icon": icon,
                "sortOrder": i if name != "退款" else 99,
                "isSystem": True,
            })

        # Investment 2 类 (D51)
        offset = len(self._categories)
        for i, (name, icon, color_key) in enumerate([
            ("投资投入", "savings", "invest"),
            ("投资收益", "trending_up", "invest"),
        ]):
            self._categories.append({
                "id": offset + i + 1,
                "name": name,
                "type": "investment",
                "color": CAT_COLOR[color_key],
                "icon": icon,
                "sortOrder": i,
                "isSystem": True,
            })

        # Benefit 1 类
        offset = len(self._categories)
        self._categories.append({
            "id": offset + 1,
            "name": "福利",
            "type": "benefit",
            "color": CAT_COLOR["benefit"],
            "icon": "favorite",
            "sortOrder": 0,
            "isSystem": True,
        })

        # Receivable 1 类 (D51 v2: '债务')
        offset = len(self._categories)
        self._categories.append({
            "id": offset + 1,
            "name": "债务",
            "type": "liability",
            "color": CAT_COLOR["liability"],
            "icon": "request_quote",
            "sortOrder": 0,
            "isSystem": True,
        })

        # Other 1 类
        offset = len(self._categories)
        self._categories.append({
            "id": offset + 1,
            "name": "其它",
            "type": "other",
            "color": CAT_COLOR["other"],
            "icon": "category",
            "sortOrder": 0,
            "isSystem": True,
        })

        # --- 3 cash_flow assets (跟 Dart DefaultAssets 全对齐) ---
        self._assets = [
            {
                "id": 1,
                "name": "现金",
                "type": "cash_flow",
                "color": 0xFFF5BC1F,
                "icon": "payments",
                "initialBalance": 0.0,
                "includeInTransactions": True,
                "isDefault": True,
                "actAsCashFlow": False,
                "isLender": False,
                "displayOrder": 0,
            },
            {
                "id": 2,
                "name": "银行卡",
                "type": "cash_flow",
                "color": 0xFF14B8A6,
                "icon": "credit_card",
                "initialBalance": 0.0,
                "includeInTransactions": True,
                "isDefault": False,
                "actAsCashFlow": False,
                "isLender": False,
                "displayOrder": 1,
            },
            {
                "id": 3,
                "name": "微信支付",
                "type": "cash_flow",
                "color": 0xFF14B8A6,
                "icon": "account_balance_wallet",
                "initialBalance": 0.0,
                "includeInTransactions": True,
                "isDefault": False,
                "actAsCashFlow": False,
                "isLender": False,
                "displayOrder": 2,
            },
        ]

        # --- 30 ledgers (过去 180 天随机) ---
        # 大致分布:支出 18 笔 / 收入 6 笔 / balance 6 笔(调拨)
        rng = random.Random(42)  # 固定 seed,保证每次重启一致
        now = datetime.now(timezone.utc)
        notes_expense = [
            "午饭", "晚饭", "咖啡", "地铁", "打车", "超市", "午餐外卖",
            "电费", "话费", "电影", "理发", "护肤品", "猫粮",
            None, None, None,  # 部分没 note
        ]
        notes_income = ["工资到账", "项目奖金", "理财赎回", "兼职收入", "京东退款"]
        notes_balance = ["现金 → 银行卡", "微信 → 现金", "银行卡 → 微信"]

        # expense cats id 1..12
        # income cats id 13..17
        tx_id = 0
        for i in range(18):  # expense
            tx_id += 1
            cat_id = rng.randint(1, 12)
            amount = round(rng.uniform(8.0, 380.0), 2)
            days_ago = rng.randint(0, 180)
            occurred = (now - timedelta(days=days_ago, hours=rng.randint(0, 23))).replace(microsecond=0)
            note = rng.choice(notes_expense)
            self._transactions.append({
                "id": tx_id,
                "amount": amount,
                "type": "expense",
                "categoryId": cat_id,
                "occurredAt": occurred.isoformat().replace("+00:00", "Z"),
                "note": note,
                "accountId": rng.randint(1, 3),
                "destinationAccountId": None,
                "createdAt": occurred.isoformat().replace("+00:00", "Z"),
                "updatedAt": occurred.isoformat().replace("+00:00", "Z"),
            })

        for i in range(6):  # income
            tx_id += 1
            cat_id = rng.randint(13, 17)
            amount = round(rng.uniform(500.0, 12000.0), 2)
            days_ago = rng.randint(0, 180)
            occurred = (now - timedelta(days=days_ago, hours=rng.randint(0, 23))).replace(microsecond=0)
            self._transactions.append({
                "id": tx_id,
                "amount": amount,
                "type": "income",
                "categoryId": cat_id,
                "occurredAt": occurred.isoformat().replace("+00:00", "Z"),
                "note": rng.choice(notes_income),
                "accountId": rng.randint(1, 3),
                "destinationAccountId": None,
                "createdAt": occurred.isoformat().replace("+00:00", "Z"),
                "updatedAt": occurred.isoformat().replace("+00:00", "Z"),
            })

        for i in range(6):  # balance (调拨)
            tx_id += 1
            src = rng.randint(1, 3)
            dst = rng.choice([d for d in range(1, 4) if d != src])
            amount = round(rng.uniform(50.0, 1000.0), 2)
            days_ago = rng.randint(0, 180)
            occurred = (now - timedelta(days=days_ago, hours=rng.randint(0, 23))).replace(microsecond=0)
            self._transactions.append({
                "id": tx_id,
                "amount": amount,
                "type": "balance",
                "categoryId": 1,  # 强制 '餐饮' cat(任意 cat.type='expense' 即可)
                "occurredAt": occurred.isoformat().replace("+00:00", "Z"),
                "note": rng.choice(notes_balance),
                "accountId": src,
                "destinationAccountId": dst,
                "createdAt": occurred.isoformat().replace("+00:00", "Z"),
                "updatedAt": occurred.isoformat().replace("+00:00", "Z"),
            })

        # --- 1 default session (启动即可用) ---
        now = datetime.now(timezone.utc)
        self._sessions[DEFAULT_SESSION_TOKEN] = {
            "token": DEFAULT_SESSION_TOKEN,
            "createdAt": now.isoformat().replace("+00:00", "Z"),
            "lastSeenAt": now.isoformat().replace("+00:00", "Z"),
            "label": "Mock Device",
        }

        # --- 当月预算 (seed 一个例子) ---
        self._monthly_budgets[(now.year, now.month)] = 5000.0
        self._category_budgets[(1, now.year, now.month)] = 1500.0  # 餐饮 1500
        self._category_budgets[(2, now.year, now.month)] = 500.0   # 交通 500


# ============================================================
# HTTP handler
# ============================================================

class MockHandler(BaseHTTPRequestHandler):
    """单文件路由 handler,BaseHTTPRequestHandler + dispatch 字典。

    跟 shelf_plus 行为对齐:
    - /api/health, /api/auth/*:public
    - 其它 /api/*:需 cookie
    - 401 时 JSON envelope:{error: "..."}
    """

    # 类级别共享 store (启动时注入)
    store: Store = None  # type: ignore

    # --- Routing ---
    def do_GET(self):    self._dispatch("GET")
    def do_POST(self):   self._dispatch("POST")
    def do_PUT(self):    self._dispatch("PUT")
    def do_DELETE(self): self._dispatch("DELETE")
    def do_OPTIONS(self): self._dispatch("OPTIONS")

    def _dispatch(self, method: str) -> None:
        try:
            parsed = urlparse(self.path)
            path = parsed.path
            query = parse_qs(parsed.query, keep_blank_values=True)
            # 统一 query value (parse_qs 返 list, 我们要单值)
            query = {k: v[0] if v else "" for k, v in query.items()}

            body_bytes = b""
            if method in ("POST", "PUT"):
                length = int(self.headers.get("Content-Length", "0") or "0")
                if length > 0:
                    body_bytes = self.rfile.read(length)
            body = self._parse_body(body_bytes)

            handler_fn = self._route(method, path)
            if handler_fn is None:
                self._json(404, {"error": "not_found", "path": path, "method": method})
                return
            handler_fn(self, path, query, body)
        except Exception as e:
            sys.stderr.write(f"[mock_server] unhandled error: {e!r}\n")
            import traceback
            traceback.print_exc(file=sys.stderr)
            try:
                self._json(500, {"error": "internal_error", "message": str(e)})
            except Exception:
                pass

    def _route(self, method: str, path: str) -> Callable | None:
        # 注意顺序:具体 path 在前,dynamic path 在后
        routes = ROUTES.get(method, {})
        # 1) 精确匹配
        if path in routes:
            return routes[path]
        # 2) dynamic pattern: <int:id> / <token>
        for pattern, fn, regex in _DYNAMIC_ROUTES.get(method, []):
            params = _match_path_with_regex(regex, path)
            if params is not None:
                # 按 fn 签名参数顺序 unpack,并按 annotation 转 int
                param_info = _fn_params_with_types(fn)
                ordered = []
                for name in param_info["names"]:
                    v = params[name]
                    target_type = param_info["types"].get(name)
                    if target_type is int:
                        try:
                            v = int(v)
                        except (TypeError, ValueError):
                            pass
                    ordered.append(v)
                def wrapped(handler, path_, query, body, fn=fn, ordered=ordered):
                    return fn(handler, path_, query, body, *ordered)
                return wrapped
        return None

    # --- Helpers ---
    def _parse_body(self, raw: bytes) -> dict[str, Any]:
        if not raw:
            return {}
        try:
            parsed = json.loads(raw.decode("utf-8"))
            if isinstance(parsed, dict):
                return parsed
            return {}
        except Exception:
            return {}

    def _cookie_token(self) -> str | None:
        header = self.headers.get("Cookie", "")
        if not header:
            return None
        for part in header.split(";"):
            part = part.strip()
            if "=" not in part:
                continue
            name, _, value = part.partition("=")
            if name == COOKIE_NAME:
                return value
        return None

    def _json(self, status: int, body: dict[str, Any], extra_headers: dict[str, str] | None = None) -> None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        # CORS(纯 dev 用,放宽松)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Cookie")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _require_session(self) -> dict[str, Any] | None:
        """校验 cookie + 返 session。失败时直接发 401 并返 None。"""
        token = self._cookie_token()
        if not token:
            self._json(401, {"error": "missing_cookie"})
            return None
        s = self.store.session_get(token)
        if not s:
            self._json(401, {"error": "session_expired"})
            return None
        return s

    def _read_json(self, body: dict[str, Any]) -> tuple[bool, dict[str, Any] | None]:
        if not body:
            return False, None
        return True, body

    def log_message(self, fmt: str, *args: Any) -> None:
        # 简化日志:[时间] METHOD /path -> status
        try:
            sys.stderr.write(f"[mock] {self.command} {self.path} -> {args[1] if len(args) > 1 else '?'}\n")
        except Exception:
            pass


# ============================================================
# Route handlers
# ============================================================

# 通用 400 helper
def _err_400(h: MockHandler, code: str) -> None:
    h._json(400, {"error": code})

# --- /api/health ---
def handle_health(h: MockHandler, path: str, q: dict, body: dict) -> None:
    tx, cat, asset = h.store.counts()
    now = datetime.now(timezone.utc)
    h._json(200, {
        "name": "gridly web (mock)",
        "version": GRIDLY_VERSION,
        "build": GRIDLY_BUILD,
        "phase": "mock P4 (decoupled from Flutter)",
        "dbSchemaVersion": GRIDLY_DB_SCHEMA,
        "transactions": tx,
        "categories": cat,
        "assets": asset,
        "uptimeSeconds": int((now - h.store.started_at).total_seconds()),
        "serverTime": now.isoformat().replace("+00:00", "Z"),
        "defaultSessionToken": DEFAULT_SESSION_TOKEN,
        "defaultPairingCode": DEFAULT_PAIRING_CODE,
    })

# --- /api/auth/code ---
def handle_auth_code(h: MockHandler, path: str, q: dict, body: dict) -> None:
    h._json(200, h.store.pairing_current())

# --- /api/auth/pair ---
def handle_auth_pair(h: MockHandler, path: str, q: dict, body: dict) -> None:
    ok, parsed = h._read_json(body)
    if not ok:
        h._json(400, {"error": "invalid_body"})
        return
    code = parsed.get("code")
    if not code or not isinstance(code, str) or len(code) != 6:
        h._json(400, {"error": "invalid_code_format"})
        return
    if not h.store.pairing_verify(code):
        h._json(401, {"error": "invalid_or_expired"})
        return
    label = (parsed.get("label") or "Device").strip() or "Device"
    session = h.store.session_create(label)
    h.store.pairing_clear()
    cookie = f"{COOKIE_NAME}={session['token']}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_MAX_AGE}"
    h._json(200, {"ok": True, "session": session}, extra_headers={"Set-Cookie": cookie})

# --- /api/auth/logout ---
def handle_auth_logout(h: MockHandler, path: str, q: dict, body: dict) -> None:
    token = h._cookie_token()
    if token:
        h.store.session_revoke(token)
    clear_cookie = f"{COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    h._json(200, {"ok": True}, extra_headers={"Set-Cookie": clear_cookie})

# --- /api/auth/sessions ---
def handle_auth_sessions_get(h: MockHandler, path: str, q: dict, body: dict) -> None:
    sess = h._require_session()
    if sess is None:
        return
    current = sess["token"]
    others = [s for s in h.store.sessions_all() if s["token"] != current]
    h._json(200, {"sessions": others})

def handle_auth_sessions_delete(h: MockHandler, path: str, q: dict, body: dict, token: str) -> None:
    sess = h._require_session()
    if sess is None:
        return
    if token == sess["token"]:
        h._json(400, {"error": "cannot_revoke_current"})
        return
    ok = h.store.session_revoke(token)
    if not ok:
        h._json(404, {"error": "session_not_found"})
        return
    h._json(200, {"ok": True})

# --- /api/categories ---
def handle_categories_get(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    type_filter = q.get("type") or None
    cats = h.store.categories_all(type_filter)
    h._json(200, {"categories": cats})

def handle_categories_post(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    name = body.get("name")
    type_ = body.get("type")
    if not name:
        h._json(400, {"error": "missing_name"})
        return
    if type_ not in CAT_TYPES:
        h._json(400, {"error": "invalid_type"})
        return
    color = body.get("color") or 0xFF94A3B8
    icon = body.get("icon") or "category_outlined"
    # 缺省 sortOrder = 当前 type 最大 sortOrder + 10
    sort_order = body.get("sortOrder")
    if sort_order is None:
        same_type = [c for c in h.store.categories_all(type_)]
        sort_order = (max((c["sortOrder"] for c in same_type), default=0) + 10)
    cat = h.store.category_create(name, type_, color, icon, int(sort_order))
    h._json(201, {"category": cat})

def handle_categories_put(h: MockHandler, path: str, q: dict, body: dict, cid: int) -> None:
    if h._require_session() is None:
        return
    existing = h.store.category_get(cid)
    if not existing:
        h._json(404, {"error": "category_not_found"})
        return
    fields = {
        "name": body.get("name"),
        "color": body.get("color"),
        "icon": body.get("icon"),
        "sortOrder": body.get("sortOrder"),
    }
    cat = h.store.category_update(cid, fields)
    h._json(200, {"category": cat})

# --- /api/assets ---
def handle_assets_get(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    h._json(200, {"assets": h.store.assets_all()})

# --- /api/ledgers ---
def _parse_dt(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        # Dart 端传 ISO8601,ex: "2026-10-17T12:30:00.000Z"
        s2 = s.replace("Z", "+00:00") if s.endswith("Z") else s
        return datetime.fromisoformat(s2)
    except Exception:
        return None

def handle_ledgers_get(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    from_ = _parse_dt(q.get("from"))
    to_ = _parse_dt(q.get("to"))
    type_ = q.get("type") or None
    cat_id_str = q.get("category") or ""
    category_id = int(cat_id_str) if cat_id_str.isdigit() else None
    keyword = q.get("keyword") or None
    page = int(q.get("page") or 1)
    page_size = int(q.get("pageSize") or 50)
    rows, _ = h.store.transactions_query(from_, to_, type_, category_id, keyword, page, page_size)
    h._json(200, {"ledgers": rows, "page": page, "pageSize": page_size})

def handle_ledgers_get_id(h: MockHandler, path: str, q: dict, body: dict, tid: int) -> None:
    if h._require_session() is None:
        return
    t = h.store.transaction_get(tid)
    if not t:
        h._json(404, {"error": "ledger_not_found"})
        return
    h._json(200, {"ledger": t})

def handle_ledgers_post(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    if "amount" not in body:
        h._json(400, {"error": "missing_amount"})
        return
    if body.get("type") not in TX_TYPES:
        h._json(400, {"error": "invalid_type"})
        return
    if "categoryId" not in body:
        h._json(400, {"error": "missing_categoryId"})
        return
    occurred = _parse_dt(body.get("occurredAt"))
    if not occurred:
        h._json(400, {"error": "missing_or_invalid_occurredAt"})
        return
    body2 = dict(body)
    body2["occurredAt"] = occurred.isoformat().replace("+00:00", "Z")
    t = h.store.transaction_create(body2)
    h._json(201, {"ledger": t})

def handle_ledgers_put(h: MockHandler, path: str, q: dict, body: dict, tid: int) -> None:
    if h._require_session() is None:
        return
    existing = h.store.transaction_get(tid)
    if not existing:
        h._json(404, {"error": "ledger_not_found"})
        return
    body2 = dict(body)
    if "occurredAt" in body2 and body2["occurredAt"]:
        dt = _parse_dt(body2["occurredAt"])
        if dt:
            body2["occurredAt"] = dt.isoformat().replace("+00:00", "Z")
    t = h.store.transaction_update(tid, body2)
    h._json(200, {"ledger": t})

def handle_ledgers_delete(h: MockHandler, path: str, q: dict, body: dict, tid: int) -> None:
    if h._require_session() is None:
        return
    ok = h.store.transaction_delete(tid)
    if not ok:
        h._json(404, {"error": "ledger_not_found"})
        return
    h._json(200, {"ok": True})

# --- /api/stats ---
def handle_stats_monthly(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    year_str = q.get("year")
    month_str = q.get("month")
    if not year_str or not month_str:
        h._json(400, {"error": "missing_year_or_month"})
        return
    year, month = int(year_str), int(month_str)
    # 计算当月所有 cash_flow 收支 (D62: type in ['income','expense'])
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    income = 0.0
    expense = 0.0
    tx_count = 0
    for t in h.store._transactions:
        ts = datetime.fromisoformat(t["occurredAt"].replace("Z", "+00:00"))
        if ts < start or ts >= end:
            continue
        if t["type"] == "income":
            income += t["amount"]
            tx_count += 1
        elif t["type"] == "expense":
            expense += t["amount"]
            tx_count += 1
    h._json(200, {
        "year": year,
        "month": month,
        "income": income,
        "expense": expense,
        "balance": income - expense,
        "transactionCount": tx_count,
    })

def handle_stats_categories(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    from_ = _parse_dt(q.get("from"))
    to_ = _parse_dt(q.get("to"))
    if not from_ or not to_:
        h._json(400, {"error": "missing_from_or_to"})
        return
    by_cat: dict[int, float] = {}
    total = 0.0
    for t in h.store._transactions:
        ts = datetime.fromisoformat(t["occurredAt"].replace("Z", "+00:00"))
        if ts < from_ or ts > to_:
            continue
        if t["type"] != "expense":
            continue
        by_cat[t["categoryId"]] = by_cat.get(t["categoryId"], 0.0) + t["amount"]
        total += t["amount"]
    items = []
    for cid, amount in by_cat.items():
        cat = h.store.category_get(cid)
        if not cat:
            continue
        items.append({
            "categoryId": cid,
            "categoryName": cat["name"],
            "color": cat["color"],
            "amount": amount,
            "percentage": (amount / total) if total > 0 else 0,
        })
    items.sort(key=lambda x: x["amount"], reverse=True)
    h._json(200, {
        "from": from_.isoformat().replace("+00:00", "Z"),
        "to": to_.isoformat().replace("+00:00", "Z"),
        "total": total,
        "items": items,
    })

def handle_stats_top(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    from_ = _parse_dt(q.get("from"))
    to_ = _parse_dt(q.get("to"))
    if not from_ or not to_:
        h._json(400, {"error": "missing_from_or_to"})
        return
    limit = int(q.get("limit") or 10)
    by_cat: dict[int, float] = {}
    for t in h.store._transactions:
        ts = datetime.fromisoformat(t["occurredAt"].replace("Z", "+00:00"))
        if ts < from_ or ts > to_:
            continue
        if t["type"] != "expense":
            continue
        by_cat[t["categoryId"]] = by_cat.get(t["categoryId"], 0.0) + t["amount"]
    items = []
    for cid, amount in by_cat.items():
        cat = h.store.category_get(cid)
        if not cat:
            continue
        items.append({
            "categoryId": cid,
            "categoryName": cat["name"],
            "color": cat["color"],
            "amount": amount,
        })
    items.sort(key=lambda x: x["amount"], reverse=True)
    h._json(200, {
        "from": from_.isoformat().replace("+00:00", "Z"),
        "to": to_.isoformat().replace("+00:00", "Z"),
        "items": items[:limit],
    })

# --- /api/budget ---
def handle_budget_get(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    year_str = q.get("year")
    month_str = q.get("month")
    if not year_str or not month_str:
        h._json(400, {"error": "missing_year_or_month"})
        return
    year, month = int(year_str), int(month_str)
    h._json(200, h.store.budget_get(year, month))

def handle_budget_put(h: MockHandler, path: str, q: dict, body: dict) -> None:
    if h._require_session() is None:
        return
    year = body.get("year")
    month = body.get("month")
    total = body.get("total")
    if year is None or month is None or total is None:
        h._json(400, {"error": "missing_year_month_or_total"})
        return
    cb_list = body.get("categoryBudgets")
    if cb_list is not None and not isinstance(cb_list, list):
        cb_list = None
    h._json(200, h.store.budget_put(int(year), int(month), float(total), cb_list))

# --- OPTIONS (CORS preflight) ---
def handle_options(h: MockHandler, path: str, q: dict, body: dict) -> None:
    h._json(204, {})


# ============================================================
# Route registration
# ============================================================

# 简单 path matcher,支持 <int:id> / <token>
import re

def _compile_pattern(pattern: str, fn: Callable) -> re.Pattern:
    """编译 pattern → regex,group name 跟 fn 签名参数名一致。

    pattern 占位符 `<int:foo>` → named int group `(?P<foo>-?\\d+)`,
    占位符 `<foo>` → named group `(?P<foo>[^/]+)`。
    fn 签名里第 5 个之后的参数按顺序对应 pattern 占位符(第 1 个占位符 ↔ 第 5 个参数)。
    """
    param_names = _fn_param_names(fn)
    pi = [0]  # 占位符 index

    def repl(m: re.Match) -> str:
        idx = pi[0]
        pi[0] += 1
        name = param_names[idx]
        full = m.group(0)
        if full.startswith("<int:"):
            return f"(?P<{name}>-?\\d+)"
        else:
            return f"(?P<{name}>[^/]+)"

    regex_str = re.sub(r"<int:(\w+)>|<(\w+)>", repl, pattern)
    return re.compile(regex_str)


def _match_path_with_regex(regex: re.Pattern, path: str) -> dict[str, Any] | None:
    m = regex.fullmatch(path)
    if not m:
        return None
    return m.groupdict()


def _match_path(pattern: str, path: str) -> dict[str, Any] | None:
    # 兼容旧调用(直接 pattern + path,fn 拿不到,所以 group name 用 pattern 占位符名)
    def repl(m: re.Match) -> str:
        full = m.group(0)
        if full.startswith("<int:"):
            name = m.group(1)
            return f"(?P<{name}>-?\\d+)"
        else:
            name = m.group(2)
            return f"(?P<{name}>[^/]+)"

    regex_str = re.sub(r"<int:(\w+)>|<(\w+)>", repl, pattern)
    m = re.fullmatch(regex_str, path)
    if not m:
        return None
    return m.groupdict()


ROUTES: dict[str, dict[str, Callable]] = {
    "GET": {
        "/api/health": handle_health,
        "/api/auth/code": handle_auth_code,
        "/api/auth/sessions": handle_auth_sessions_get,
        "/api/categories": handle_categories_get,
        "/api/assets": handle_assets_get,
        "/api/ledgers": handle_ledgers_get,
        "/api/ledgers/<int:id>": handle_ledgers_get_id,
        "/api/stats/monthly": handle_stats_monthly,
        "/api/stats/categories": handle_stats_categories,
        "/api/stats/top": handle_stats_top,
        "/api/budget": handle_budget_get,
    },
    "POST": {
        "/api/auth/pair": handle_auth_pair,
        "/api/auth/logout": handle_auth_logout,
        "/api/categories": handle_categories_post,
        "/api/ledgers": handle_ledgers_post,
        "/api/budget": handle_budget_put,
    },
    "PUT": {
        "/api/categories/<int:id>": handle_categories_put,
        "/api/ledgers/<int:id>": handle_ledgers_put,
        "/api/budget": handle_budget_put,
    },
    "DELETE": {
        "/api/auth/sessions/<token>": handle_auth_sessions_delete,
        "/api/ledgers/<int:id>": handle_ledgers_delete,
    },
    "OPTIONS": {
        "*": handle_options,
    },
}

# 抽出 dynamic routes(pattern + fn + precompiled regex,group name 跟 fn 签名对齐)
_DYNAMIC_ROUTES: dict[str, list[tuple[str, Callable, re.Pattern]]] = {}


def _fn_param_names(fn: Callable) -> list[str]:
    """返 handler 函数在 (handler, path, query, body, ...) 之后的位置参数名。"""
    import inspect
    sig = inspect.signature(fn)
    params = list(sig.parameters.values())
    names = []
    skip = 4  # 跳过 handler, path, query, body
    for p in params[skip:]:
        if p.kind == inspect.Parameter.VAR_KEYWORD:
            continue
        if p.kind == inspect.Parameter.VAR_POSITIONAL:
            continue
        names.append(p.name)
    return names


def _fn_params_with_types(fn: Callable) -> dict[str, Any]:
    """返 {"names": [name...], "types": {name: type_or_None}}。

    注意:文件顶部有 `from __future__ import annotations`,annotation 在 inspect
    默认是 string。必须用 `typing.get_type_hints()` evaluate 之后才是真 type。
    """
    import inspect
    import typing
    sig = inspect.signature(fn)
    params = list(sig.parameters.values())
    names: list[str] = []
    types: dict[str, Any] = {}
    skip = 4
    # 用 get_type_hints 拿到 evaluate 后的真实类型(PEP 563 兼容)
    try:
        hints = typing.get_type_hints(fn)
    except Exception:
        hints = {}
    for p in params[skip:]:
        if p.kind in (inspect.Parameter.VAR_KEYWORD, inspect.Parameter.VAR_POSITIONAL):
            continue
        names.append(p.name)
        ann = hints.get(p.name, inspect.Parameter.empty)
        if ann is inspect.Parameter.empty:
            types[p.name] = None
        elif isinstance(ann, type):
            types[p.name] = ann
        else:
            types[p.name] = None
    return {"names": names, "types": types}


for method, routes in ROUTES.items():
    for pattern, fn in routes.items():
        if "<" in pattern:
            regex = _compile_pattern(pattern, fn)
            _DYNAMIC_ROUTES.setdefault(method, []).append((pattern, fn, regex))


# ============================================================
# Main
# ============================================================

def main() -> int:
    parser = argparse.ArgumentParser(description="gridly LAN_WEB mock server")
    parser.add_argument("--host", default="0.0.0.0", help="bind host (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8123, help="bind port (default 8123)")
    args = parser.parse_args()

    started_at = datetime.now(timezone.utc)
    store = Store(started_at)
    MockHandler.store = store

    server = ThreadingHTTPServer((args.host, args.port), MockHandler)
    print(f"[mock_server] gridly LAN_WEB mock server listening on http://{args.host}:{args.port}", flush=True)
    print(f"[mock_server] default pairing code: {DEFAULT_PAIRING_CODE}", flush=True)
    print(f"[mock_server] default session token: {DEFAULT_SESSION_TOKEN}", flush=True)
    print(f"[mock_server] (cookie: gridly_session={DEFAULT_SESSION_TOKEN})", flush=True)
    print(f"[mock_server] seed: {len(store._categories)} cats / {len(store._assets)} assets / {len(store._transactions)} ledgers / {len(store._sessions)} sessions", flush=True)
    print(f"[mock_server] press Ctrl+C to stop", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[mock_server] shutting down", flush=True)
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
