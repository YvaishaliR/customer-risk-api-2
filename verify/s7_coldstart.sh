#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASIC_AUTH_USER=$(grep "^BASIC_AUTH_USER=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
BASIC_AUTH_PASSWORD=$(grep "^BASIC_AUTH_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d= -f2-)

if [ -z "$BASIC_AUTH_USER" ] || [ -z "$BASIC_AUTH_PASSWORD" ]; then
    echo "ERROR: BASIC_AUTH_USER, BASIC_AUTH_PASSWORD must be set in .env" >&2
    exit 1
fi

PASS=0
FAIL=0
TIMEOUT=120

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Cleanup on any exit path — explicit down in step 7 is the primary teardown;
# this trap handles unexpected aborts (ctrl-c, script error) so no stack is left running.
cleanup() { docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v 2>/dev/null || true; }
trap cleanup EXIT

cd "$PROJECT_ROOT"

# ── Step 1: ensure clean state ────────────────────────────────────────────────
echo "=== Step 1: Ensuring clean state ==="
docker compose down -v 2>/dev/null || true

# ── Step 2: record start time ─────────────────────────────────────────────────
START_EPOCH=$(date +%s)
echo "=== Step 2: Start time recorded ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="

# ── Step 3: build and start ───────────────────────────────────────────────────
echo "=== Step 3: docker compose up -d --build ==="
docker compose up -d --build

# ── Step 4: poll until all services ready ────────────────────────────────────
# DEVIATION: task spec says "nginx: healthy" but docker-compose.yml defines no
# healthcheck for the nginx service. docker inspect returns "" for Health.Status
# on a container with no healthcheck — it will never equal "healthy". Using
# "running" for nginx, consistent with s5_nginx.sh and s6_ui.sh. To satisfy the
# literal spec, a healthcheck would need to be added to docker-compose.yml.
echo "=== Step 4: Waiting for all services ready (up to ${TIMEOUT}s) ==="
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

    echo "  [${ELAPSED}s] postgres=${PG_STATUS:-unknown}  db-init=${DI_STATUS:-unknown}(exit=${DI_EXIT})  fastapi=${FA_HEALTH:-unknown}  nginx=${NG_STATUS:-unknown}"

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

# ── Step 5: record end time ───────────────────────────────────────────────────
END_EPOCH=$(date +%s)
ELAPSED_TOTAL=$((END_EPOCH - START_EPOCH))
echo "=== Step 5: End time recorded — elapsed ${ELAPSED_TOTAL}s ==="

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: stack not ready within ${TIMEOUT}s"
    echo "  postgres health:       ${PG_STATUS:-unknown}"
    echo "  db-init status/exit:   ${DI_STATUS:-unknown}/${DI_EXIT:-unknown}"
    echo "  fastapi health:        ${FA_HEALTH:-unknown}"
    echo "  nginx status:          ${NG_STATUS:-unknown}"
    exit 1
fi

# ── Step 6: integration checks ────────────────────────────────────────────────
echo ""
echo "=== Step 6: Checks ==="

# ── S7-COLD-A ─────────────────────────────────────────────────────────────────
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/ || echo "000")
if [ "$STATUS" = "200" ]; then
    pass "S7-COLD-A: GET / with Basic Auth → HTTP 200"
else
    fail "S7-COLD-A: GET / with Basic Auth → expected 200, got $STATUS"
fi

# ── S7-COLD-B + S7-COLD-C: one request, reused ────────────────────────────────
API_RESP=$(curl -s -D - \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    http://localhost:80/api/risk/CUST001 2>/dev/null || echo "")

S7B_STATUS=$(echo "$API_RESP" | head -1 | grep -oE '[0-9]{3}' | head -1 || echo "000")
S7_BODY=$(printf '%s' "$API_RESP" | awk 'found{print} /^(\r)?$/{found=1}')

if [ "$S7B_STATUS" = "200" ]; then
    pass "S7-COLD-B: GET /api/risk/CUST001 with Basic Auth → HTTP 200"
else
    fail "S7-COLD-B: GET /api/risk/CUST001 → expected 200, got $S7B_STATUS"
fi

# ── S7-COLD-C ─────────────────────────────────────────────────────────────────
TIER=$(echo "$S7_BODY" | grep -o '"tier":"[A-Z]*"' | grep -o '"[A-Z]*"$' | tr -d '"' || echo "")
FACTOR_COUNT=$(echo "$S7_BODY" | grep -c '"factor_code"' || echo "0")

if [ -n "$TIER" ] && [ "$FACTOR_COUNT" -gt 0 ]; then
    pass "S7-COLD-C: Response contains tier ($TIER) and non-empty risk_factors ($FACTOR_COUNT factor(s))"
else
    fail "S7-COLD-C: Response missing tier or risk_factors (tier=${TIER:-none}, factors=${FACTOR_COUNT})"
fi

# ── INV-03 ────────────────────────────────────────────────────────────────────
# Compare db-init FinishedAt against fastapi's first-healthy timestamp.
# First health log entry with ExitCode=0 is fastapi's earliest confirmed-healthy time.
# Falls back to fastapi StartedAt if the health log has no passing entry.
DI_ID=$(docker compose ps -q --all db-init 2>/dev/null || echo "")
FA_ID=$(docker compose ps -q fastapi 2>/dev/null || echo "")

DI_FINISHED=""
FA_HEALTHY_AT=""

if [ -n "$DI_ID" ]; then
    DI_FINISHED=$(docker inspect --format='{{.State.FinishedAt}}' "$DI_ID" 2>/dev/null || echo "")
fi
if [ -n "$FA_ID" ]; then
    FA_HEALTHY_AT=$(docker inspect \
        --format='{{range .State.Health.Log}}{{if eq .ExitCode 0}}{{.Start}}{{"\n"}}{{end}}{{end}}' \
        "$FA_ID" 2>/dev/null | head -1 || echo "")
    if [ -z "$FA_HEALTHY_AT" ]; then
        FA_HEALTHY_AT=$(docker inspect --format='{{.State.StartedAt}}' "$FA_ID" 2>/dev/null || echo "")
    fi
fi

# Normalize both timestamps to "YYYY-MM-DD HH:MM:SS" before comparing.
# State.FinishedAt uses RFC3339  ("2026-05-12T06:48:20.525Z")   — T separator.
# Health.Log Start uses Go format ("2026-05-12 06:48:31.036 +0000 UTC") — space separator.
# Both formats are "YYYY-MM-DDxHH:MM:SS..." in the first 19 chars; replacing T→space makes
# them identical in structure and therefore lexicographically comparable to second precision.
norm_ts() { echo "$1" | cut -c1-19 | tr 'T' ' '; }

DI_NORM=$(norm_ts "$DI_FINISHED")
FA_NORM=$(norm_ts "$FA_HEALTHY_AT")

if [[ -n "$DI_NORM" && -n "$FA_NORM" && "$DI_NORM" < "$FA_NORM" ]]; then
    pass "INV-03: db-init finished ($DI_FINISHED) before fastapi first-healthy ($FA_HEALTHY_AT)"
else
    fail "INV-03: ordering not confirmed — db-init.FinishedAt=${DI_FINISHED:-unknown}  fastapi.first-healthy=${FA_HEALTHY_AT:-unknown}"
fi

# ── Step 7: teardown ──────────────────────────────────────────────────────────
echo ""
echo "=== Step 7: Teardown ==="
docker compose down -v
trap - EXIT   # disarm trap — teardown already done

echo ""
echo "Elapsed time: ${ELAPSED_TOTAL}s"
echo "PASSED: $PASS  FAILED: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "Overall: PASS"
    exit 0
else
    echo "Overall: FAIL"
    exit 1
fi
