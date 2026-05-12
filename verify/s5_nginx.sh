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

# ── S5-A ──────────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ || echo "000")
if [ "$STATUS" = "401" ]; then
    pass "S5-A: GET / no credentials → HTTP 401"
else
    fail "S5-A: GET / no credentials → expected 401, got $STATUS"
fi

# ── S5-B ──────────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" http://localhost:80/ || echo "000")
if [ "$STATUS" = "200" ]; then
    pass "S5-B: GET / with Basic Auth → HTTP 200"
else
    fail "S5-B: GET / with Basic Auth → expected 200, got $STATUS"
fi

# ── S5-C ──────────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:80/api/risk/CUST001 || echo "000")
if [ "$STATUS" = "401" ]; then
    pass "S5-C: GET /api/risk/CUST001 no credentials → HTTP 401"
else
    fail "S5-C: GET /api/risk/CUST001 no credentials → expected 401, got $STATUS"
fi

# ── S5-D + INV-02-C + INV-02-D ───────────────────────────────────────────────
# One request; split the response into headers and body for reuse.
FULL_RESP=$(curl -s -D - \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/api/risk/CUST001 2>/dev/null || echo "")

S5D_STATUS=$(echo "$FULL_RESP" | head -1 | grep -oE '[0-9]{3}' | head -1 || echo "000")
RESP_HEADERS=$(printf '%s' "$FULL_RESP" | awk '/^(\r)?$/{exit} {print}')
RESP_BODY=$(printf '%s' "$FULL_RESP" | awk 'found{print} /^(\r)?$/{found=1}')

if [ "$S5D_STATUS" = "200" ]; then
    pass "S5-D: GET /api/risk/CUST001 Basic Auth only (key injected by nginx) → HTTP 200"
else
    fail "S5-D: GET /api/risk/CUST001 Basic Auth only → expected 200, got $S5D_STATUS"
fi

# INV-02-C: response headers must not contain the API_KEY value
if echo "$RESP_HEADERS" | grep -qF "$API_KEY"; then
    fail "INV-02-C: API_KEY value found in response headers"
    echo "  Offending header(s):"
    echo "$RESP_HEADERS" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-C: API_KEY value not present in response headers"
fi

# INV-02-D: response body must not contain the API_KEY value
if echo "$RESP_BODY" | grep -qF "$API_KEY"; then
    fail "INV-02-D: API_KEY value found in response body"
else
    pass "INV-02-D: API_KEY value not present in response body"
fi

# ── INV-02-E ──────────────────────────────────────────────────────────────────
# Collect nginx logs after all requests and check the API_KEY value is absent.
NGINX_LOGS=$(docker compose logs nginx 2>/dev/null || echo "")
if echo "$NGINX_LOGS" | grep -qF "$API_KEY"; then
    fail "INV-02-E: API_KEY value found in nginx access logs"
    echo "  Offending line(s):"
    echo "$NGINX_LOGS" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-E: API_KEY value not present in nginx access logs"
fi

# ── S5-E ──────────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/api/risk/NONEXISTENT || echo "000")
if [ "$STATUS" = "404" ]; then
    pass "S5-E: GET /api/risk/NONEXISTENT with Basic Auth → HTTP 404"
else
    fail "S5-E: GET /api/risk/NONEXISTENT with Basic Auth → expected 404, got $STATUS"
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
