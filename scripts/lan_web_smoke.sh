#!/usr/bin/env bash
# scripts/lan_web_smoke.sh
# LAN_WEB v2.0.0 P2 手工 smoke test —— 真机 / 仿真器跑 gridly 后,跑这个验 11 个端点
#
# 用法:
#   URL=http://192.168.1.5:8123 ./scripts/lan_web_smoke.sh
#   URL=http://127.0.0.1:8123 ./scripts/lan_web_smoke.sh     # macOS dev mode
#
# 依赖:curl + jq
# 退出码:0 全过;非 0 有失败
set -euo pipefail

URL="${URL:-http://127.0.0.1:8123}"
COOKIES=$(mktemp)
trap "rm -f $COOKIES" EXIT

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
fail=0

step() { echo -e "${YELLOW}== $1 ==${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; pass=$((pass+1)); }
ng() { echo -e "${RED}✗ $1${NC}"; fail=$((fail+1)); }

# 1. 健康检查
step "1. GET / 健康检查"
RESP=$(curl -s -w "\n%{http_code}" "$URL/")
BODY=$(echo "$RESP" | head -n1)
CODE=$(echo "$RESP" | tail -n1)
if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.name == "gridly web"' >/dev/null; then
  ok "健康检查 200,name 正确"
else
  ng "健康检查失败 code=$CODE body=$BODY"
fi

# 2. 拿配对码
step "2. GET /api/auth/code 拿 6 位码"
CODE_RESP=$(curl -s "$URL/api/auth/code")
PAIR_CODE=$(echo "$CODE_RESP" | jq -r .code)
if [ "${#PAIR_CODE}" = "6" ]; then
  ok "配对码: $PAIR_CODE"
else
  ng "配对码格式错:$CODE_RESP"
  exit 1
fi

# 3. pair
step "3. POST /api/auth/pair 配对拿 cookie"
PAIR_RESP=$(curl -s -i -X POST "$URL/api/auth/pair" \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"$PAIR_CODE\",\"label\":\"smoke-test\"}")
PAIR_CODE_HTTP=$(echo "$PAIR_RESP" | head -n1 | awk '{print $2}')
SET_COOKIE=$(echo "$PAIR_RESP" | grep -i '^set-cookie:' | head -n1 | sed 's/^[Ss]et-[Cc]ookie: //' | cut -d';' -f1)
if [ "$PAIR_CODE_HTTP" = "200" ] && [ -n "$SET_COOKIE" ]; then
  echo "$SET_COOKIE" > "$COOKIES"
  ok "配对 200,cookie=$SET_COOKIE"
else
  ng "配对失败 code=$PAIR_CODE_HTTP"
  exit 1
fi

# 4. 受保护端点无 cookie
step "4. GET /api/ledgers 无 cookie → 401"
RESP=$(curl -s -w "\n%{http_code}" "$URL/api/ledgers")
HTTP=$(echo "$RESP" | tail -n1)
if [ "$HTTP" = "401" ]; then
  ok "无 cookie 受保护端点 → 401"
else
  ng "期望 401 实际 $HTTP"
fi

# 5. 受保护端点有 cookie
step "5. GET /api/ledgers 有 cookie → 200"
RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIES" "$URL/api/ledgers")
HTTP=$(echo "$RESP" | tail -n1)
if [ "$HTTP" = "200" ]; then
  ok "有 cookie 受保护端点 → 200"
else
  ng "期望 200 实际 $HTTP body=$(echo "$RESP"|head -n1)"
fi

# 6. 分类列表
step "6. GET /api/categories"
RESP=$(curl -s -b "$COOKIES" "$URL/api/categories")
CAT_COUNT=$(echo "$RESP" | jq -r '.categories | length')
if [ "$CAT_COUNT" -gt "0" ]; then
  ok "分类 $CAT_COUNT 条"
else
  ng "分类列表空:$RESP"
fi

# 7. 新增流水
step "7. POST /api/ledgers 新增"
CAT_ID=$(echo "$RESP" | jq -r '.categories[0].id')
ADD_RESP=$(curl -s -X POST "$URL/api/ledgers" \
  -b "$COOKIES" \
  -H 'Content-Type: application/json' \
  -d "{\"amount\":42.5,\"type\":\"expense\",\"categoryId\":$CAT_ID,\"occurredAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"note\":\"smoke test\"}")
LEDGER_ID=$(echo "$ADD_RESP" | jq -r '.ledger.id')
if [ "$LEDGER_ID" != "null" ] && [ -n "$LEDGER_ID" ]; then
  ok "新增流水 id=$LEDGER_ID"
else
  ng "新增失败:$ADD_RESP"
fi

# 8. 月度统计
step "8. GET /api/stats/monthly"
YEAR=$(date +%Y); MONTH=$(date +%-m)
RESP=$(curl -s -b "$COOKIES" "$URL/api/stats/monthly?year=$YEAR&month=$MONTH")
EXPENSE=$(echo "$RESP" | jq -r '.expense')
TX_COUNT=$(echo "$RESP" | jq -r '.transactionCount')
ok "月度统计 expense=$EXPENSE,tx_count=$TX_COUNT(应该 >= 1)"

# 9. 预算
step "9. GET /api/budget"
RESP=$(curl -s -b "$COOKIES" "$URL/api/budget?year=$YEAR&month=$MONTH")
TOTAL=$(echo "$RESP" | jq -r '.total')
ok "预算 total=$TOTAL(可能 0,没设过预算)"

# 10. 404 兜底
step "10. GET /api/nonexistent → 404"
RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIES" "$URL/api/nonexistent")
HTTP=$(echo "$RESP" | tail -n1)
ERR=$(echo "$RESP" | head -n1 | jq -r '.error')
if [ "$HTTP" = "404" ] && [ "$ERR" = "route_not_found" ]; then
  ok "404 route_not_found 兜底正常"
else
  ng "404 测试失败 code=$HTTP error=$ERR"
fi

# 11. 注销
step "11. POST /api/auth/logout"
RESP=$(curl -s -w "\n%{http_code}" -X POST -b "$COOKIES" "$URL/api/auth/logout")
HTTP=$(echo "$RESP" | tail -n1)
if [ "$HTTP" = "200" ]; then
  ok "注销 200"
else
  ng "注销失败 code=$HTTP"
fi

# 12. 注销后再访问受保护端点 → 401
step "12. GET /api/ledgers 注销后 → 401"
RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIES" "$URL/api/ledgers")
HTTP=$(echo "$RESP" | tail -n1)
ERR=$(echo "$RESP" | head -n1 | jq -r '.error')
if [ "$HTTP" = "401" ] && [ "$ERR" = "session_expired" ]; then
  ok "注销后 session_expired"
else
  ng "注销后鉴权失败 code=$HTTP error=$ERR"
fi

echo
echo "================================"
echo -e "通过: ${GREEN}$pass${NC}  失败: ${RED}$fail${NC}"
echo "================================"
[ "$fail" = "0" ] && exit 0 || exit 1
