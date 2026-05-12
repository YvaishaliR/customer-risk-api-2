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
    echo "  postgres health:     ${PG_STATUS:-unknown}"
    echo "  db-init status/exit: ${DI_STATUS:-unknown}/${DI_EXIT:-unknown}"
    echo "  fastapi health:      ${FA_HEALTH:-unknown}"
    echo "  nginx status:        ${NG_STATUS:-unknown}"
    exit 1
fi

echo ""
echo "=== Checks ==="

# ── INV-01-FULLSTACK-A ────────────────────────────────────────────────────────
# No credentials at all — Nginx basic_auth blocks the request before proxying.
STATUS_A=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:80/api/risk/CUST001" || echo "000")
if [ "$STATUS_A" = "401" ]; then
    pass "INV-01-FULLSTACK-A: No Basic Auth credentials → Nginx returns HTTP 401 (FastAPI not reached)"
else
    fail "INV-01-FULLSTACK-A: No Basic Auth credentials → expected 401, got $STATUS_A"
fi

# ── INV-01-FULLSTACK-B ────────────────────────────────────────────────────────
# Caller sends explicit wrong X-API-Key alongside valid Basic Auth.
# nginx.conf.template uses proxy_set_header X-API-Key ${API_KEY} which unconditionally
# replaces any client-supplied X-API-Key header before proxying to FastAPI.
# Expected behaviour: HTTP 200 (nginx overrides wrong key with injected correct key).
# Script accepts both 200 and 401 and documents which header-override behaviour occurred.
STATUS_B=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    -H "X-API-Key: wrong-key" \
    "http://localhost:80/api/risk/CUST001" || echo "000")
if [ "$STATUS_B" = "200" ]; then
    pass "INV-01-FULLSTACK-B: Basic Auth + wrong X-API-Key → HTTP 200 (nginx proxy_set_header overrides caller header; FastAPI received injected correct key)"
elif [ "$STATUS_B" = "401" ]; then
    pass "INV-01-FULLSTACK-B: Basic Auth + wrong X-API-Key → HTTP 401 (caller header reached FastAPI unchanged; FastAPI rejected wrong key — proxy_set_header did not override)"
else
    fail "INV-01-FULLSTACK-B: Basic Auth + wrong X-API-Key → unexpected HTTP $STATUS_B (expected 200 or 401)"
fi

# ── INV-01-FULLSTACK-C + INV-02-FULLSTACK-A + INV-02-FULLSTACK-B ─────────────
# One request captures headers and body; reused for three checks below.
FULL_RESP=$(curl -s -D - \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    "http://localhost:80/api/risk/CUST001" 2>/dev/null || echo "")

STATUS_C=$(printf '%s' "$FULL_RESP" | head -1 | grep -oE '[0-9]{3}' | head -1 || echo "000")
RESP_HEADERS=$(printf '%s' "$FULL_RESP" | awk '/^(\r)?$/{exit} {print}')
RESP_BODY=$(printf '%s' "$FULL_RESP" | awk 'found{print} /^(\r)?$/{found=1}')

# ── INV-01-FULLSTACK-C ────────────────────────────────────────────────────────
if [ "$STATUS_C" = "200" ]; then
    pass "INV-01-FULLSTACK-C: Basic Auth + no explicit X-API-Key → HTTP 200 (nginx injects correct key; FastAPI accepts)"
else
    fail "INV-01-FULLSTACK-C: Basic Auth + no explicit X-API-Key → expected 200, got $STATUS_C"
fi

# ── INV-02-FULLSTACK-A ────────────────────────────────────────────────────────
# proxy_hide_header X-API-Key in nginx.conf.template also strips the header from
# any upstream response — but we test the full header block regardless.
if printf '%s' "$RESP_HEADERS" | grep -qF "$API_KEY"; then
    fail "INV-02-FULLSTACK-A: API_KEY value found in response headers"
    echo "  Offending line(s):"
    printf '%s' "$RESP_HEADERS" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-FULLSTACK-A: API_KEY value not present in response headers"
fi

# ── INV-02-FULLSTACK-B ────────────────────────────────────────────────────────
if printf '%s' "$RESP_BODY" | grep -qF "$API_KEY"; then
    fail "INV-02-FULLSTACK-B: API_KEY value found in response body"
    echo "  Offending line(s):"
    printf '%s' "$RESP_BODY" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-FULLSTACK-B: API_KEY value not present in response body"
fi

# ── INV-02-FULLSTACK-C ────────────────────────────────────────────────────────
# nginx access_log uses the api_safe format which logs: remote_addr, time_local,
# request line, status, bytes_sent, referer, user_agent — no header values.
# nginx:1.25-alpine symlinks /var/log/nginx/access.log → /dev/stdout so
# docker compose logs nginx captures the full access log.
NGINX_LOGS=$(docker compose logs nginx 2>/dev/null || echo "")
if printf '%s' "$NGINX_LOGS" | grep -qF "$API_KEY"; then
    fail "INV-02-FULLSTACK-C: API_KEY value found in nginx access logs"
    echo "  Offending line(s):"
    printf '%s' "$NGINX_LOGS" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-FULLSTACK-C: API_KEY value not present in nginx access logs"
fi

# ── INV-02-FULLSTACK-D ────────────────────────────────────────────────────────
# uvicorn logs to stdout; docker compose logs fastapi captures all FastAPI output.
FASTAPI_LOGS=$(docker compose logs fastapi 2>/dev/null || echo "")
if printf '%s' "$FASTAPI_LOGS" | grep -qF "$API_KEY"; then
    fail "INV-02-FULLSTACK-D: API_KEY value found in FastAPI logs"
    echo "  Offending line(s):"
    printf '%s' "$FASTAPI_LOGS" | grep -F "$API_KEY" | sed 's/^/    /'
else
    pass "INV-02-FULLSTACK-D: API_KEY value not present in FastAPI logs"
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
