#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

API_KEY=$(grep "^API_KEY=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
BASIC_AUTH_USER=$(grep "^BASIC_AUTH_USER=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
BASIC_AUTH_PASSWORD=$(grep "^BASIC_AUTH_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d= -f2-)

if [ -z "$API_KEY" ] || [ -z "$BASIC_AUTH_USER" ] || [ -z "$BASIC_AUTH_PASSWORD" ]; then
    echo "ERROR: API_KEY, BASIC_AUTH_USER, BASIC_AUTH_PASSWORD must all be set in .env" >&2
    exit 1
fi

PASS=0
FAIL=0
TIMEOUT=120

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() { docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v 2>/dev/null || true; }
trap cleanup EXIT

cd "$PROJECT_ROOT"

echo "=== Starting full stack ==="
docker compose up -d

echo "=== Waiting for all services ready (up to ${TIMEOUT}s) ==="
PG_STATUS=""
DI_STATUS=""
DI_EXIT="-1"
FA_HEALTH=""
NG_STATUS=""
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    PG_ID=$(docker compose ps -q postgres 2>/dev/null || echo "")
    DI_ID=$(docker compose ps -q --all db-init 2>/dev/null || echo "")
    FA_ID=$(docker compose ps -q fastapi 2>/dev/null || echo "")
    NG_ID=$(docker compose ps -q nginx 2>/dev/null || echo "")

    PG_STATUS=""
    DI_STATUS=""
    DI_EXIT="-1"
    FA_HEALTH=""
    NG_STATUS=""

    if [ -n "$PG_ID" ]; then
        PG_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$PG_ID" 2>/dev/null || echo "")
    fi
    if [ -n "$DI_ID" ]; then
        DI_STATUS=$(docker inspect --format='{{.State.Status}}' "$DI_ID" 2>/dev/null || echo "")
        DI_EXIT=$(docker inspect --format='{{.State.ExitCode}}' "$DI_ID" 2>/dev/null || echo "-1")
    fi
    if [ -n "$FA_ID" ]; then
        FA_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$FA_ID" 2>/dev/null || echo "")
    fi
    if [ -n "$NG_ID" ]; then
        NG_STATUS=$(docker inspect --format='{{.State.Status}}' "$NG_ID" 2>/dev/null || echo "")
    fi

    if [ "$PG_STATUS" = "healthy" ] && \
       [ "$DI_STATUS" = "exited" ] && [ "$DI_EXIT" = "0" ] && \
       [ "$FA_HEALTH" = "healthy" ] && \
       [ "$NG_STATUS" = "running" ]; then
        echo "All services ready after ${ELAPSED}s"
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: stack not ready within ${TIMEOUT}s"
    echo "  postgres health: ${PG_STATUS:-unknown}"
    echo "  db-init status/exit: ${DI_STATUS:-unknown}/${DI_EXIT:-unknown}"
    echo "  fastapi health: ${FA_HEALTH:-unknown}"
    echo "  nginx status: ${NG_STATUS:-unknown}"
    exit 1
fi

echo ""
echo "=== Checks ==="

# ── S6-A ──────────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ || echo "000")
if [ "$STATUS" = "401" ]; then
    pass "S6-A: GET / no credentials → HTTP 401"
else
    fail "S6-A: GET / no credentials → expected 401, got $STATUS"
fi

# ── S6-B + S6-C + S6-D + INV-02-F: one request, split and reused ─────────────
UI_RESP=$(curl -s -D - \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/ 2>/dev/null || echo "")

S6B_STATUS=$(echo "$UI_RESP" | head -1 | grep -oE '[0-9]{3}' | head -1 || echo "000")
UI_BODY=$(printf '%s' "$UI_RESP" | awk 'found{print} /^(\r)?$/{found=1}')

# ── S6-B ──────────────────────────────────────────────────────────────────────
if [ "$S6B_STATUS" = "200" ]; then
    pass "S6-B: GET / with Basic Auth → HTTP 200"
else
    fail "S6-B: GET / with Basic Auth → expected 200, got $S6B_STATUS"
fi

# ── S6-C ──────────────────────────────────────────────────────────────────────
if echo "$UI_BODY" | grep -q "Customer Risk Lookup"; then
    pass "S6-C: Response body contains \"Customer Risk Lookup\""
else
    fail "S6-C: Response body does not contain \"Customer Risk Lookup\""
fi

# ── S6-D ──────────────────────────────────────────────────────────────────────
if echo "$UI_BODY" | grep -q "Enter customer ID" && \
   echo "$UI_BODY" | grep -q "Look up"; then
    pass "S6-D: Response body contains lookup form elements (input placeholder + button text)"
else
    fail "S6-D: Response body missing lookup form elements"
fi

# ── INV-02-F ──────────────────────────────────────────────────────────────────
if echo "$UI_BODY" | grep -qF "$API_KEY"; then
    fail "INV-02-F: API_KEY value found in served HTML"
    echo "  Offending line(s):"
    echo "$UI_BODY" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-F: API_KEY value not present in served HTML"
fi

# ── S6-E + S6-F: one request, split and reused ────────────────────────────────
API_RESP=$(curl -s -D - \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/api/risk/CUST001 2>/dev/null || echo "")

S6E_STATUS=$(echo "$API_RESP" | head -1 | grep -oE '[0-9]{3}' | head -1 || echo "000")
S6E_BODY=$(printf '%s' "$API_RESP" | awk 'found{print} /^(\r)?$/{found=1}')

# ── S6-E ──────────────────────────────────────────────────────────────────────
if [ "$S6E_STATUS" = "200" ]; then
    pass "S6-E: GET /api/risk/CUST001 via Nginx with Basic Auth → HTTP 200"
else
    fail "S6-E: GET /api/risk/CUST001 via Nginx → expected 200, got $S6E_STATUS"
fi

# ── S6-F ──────────────────────────────────────────────────────────────────────
if echo "$S6E_BODY" | grep -q '"customer_id"' && \
   echo "$S6E_BODY" | grep -q '"tier"' && \
   echo "$S6E_BODY" | grep -q '"risk_factors"'; then
    pass "S6-F: API response is valid JSON with keys: customer_id, tier, risk_factors"
else
    fail "S6-F: API response missing expected JSON keys (got: $(echo "$S6E_BODY" | head -c 200))"
fi

echo ""
echo "PASSED: $PASS  FAILED: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "Overall: PASS"
    exit 0
else
    echo "Overall: FAIL"
    exit 1
fi
