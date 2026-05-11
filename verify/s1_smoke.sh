#!/usr/bin/env bash
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

cleanup() {
    echo ""
    echo "--- Tearing down ---"
    docker compose down -v 2>/dev/null || true
}
trap cleanup EXIT

echo "=== S1 Smoke Test ==="
echo ""

# Step 1: bring up
echo "--- Starting stack ---"
docker compose up -d --build
echo ""

# Initialise state variables before the poll loop
PG_HEALTH="unknown"
FA_HEALTH="unknown"
DI_STATE="unknown"
DI_EXIT="-1"

# Step 2: poll up to 60 seconds
echo "--- Waiting for services (up to 60s) ---"
TIMEOUT=60
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    PG_ID=$(docker compose ps -q postgres          2>/dev/null || true)
    FA_ID=$(docker compose ps -q fastapi           2>/dev/null || true)
    DI_ID=$(docker compose ps -q --all db-init     2>/dev/null || true)

    [ -n "$PG_ID" ] && PG_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$PG_ID" 2>/dev/null || echo "unknown")
    [ -n "$FA_ID" ] && FA_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$FA_ID" 2>/dev/null || echo "unknown")
    [ -n "$DI_ID" ] && DI_STATE=$(docker inspect --format='{{.State.Status}}'     "$DI_ID" 2>/dev/null || echo "unknown")
    [ -n "$DI_ID" ] && DI_EXIT=$(docker inspect  --format='{{.State.ExitCode}}'   "$DI_ID" 2>/dev/null || echo "-1")

    echo "  [${ELAPSED}s] postgres=${PG_HEALTH} db-init=${DI_STATE}(exit=${DI_EXIT}) fastapi=${FA_HEALTH}"

    if [ "$PG_HEALTH" = "healthy" ] && \
       [ "$DI_STATE"  = "exited"  ] && \
       [ "$DI_EXIT"   = "0"       ] && \
       [ "$FA_HEALTH" = "healthy" ]; then
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
echo "--- Check results ---"

# Check 1: postgres healthy
if [ "$PG_HEALTH" = "healthy" ]; then
    pass "postgres is healthy"
else
    fail "postgres is healthy" "status=${PG_HEALTH} after ${ELAPSED}s"
fi

# Check 2: db-init exited 0
if [ "$DI_STATE" = "exited" ] && [ "$DI_EXIT" = "0" ]; then
    pass "db-init exited 0"
else
    fail "db-init exited 0" "state=${DI_STATE} exit=${DI_EXIT}"
fi

# Check 3: fastapi healthy
if [ "$FA_HEALTH" = "healthy" ]; then
    pass "fastapi is healthy"
else
    fail "fastapi is healthy" "status=${FA_HEALTH} after ${ELAPSED}s"
fi

# Check 4: nginx serves HTTP 200 on port 80
HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost:80 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ]; then
    pass "GET http://localhost:80 → HTTP 200"
else
    fail "GET http://localhost:80 → HTTP 200" "got HTTP ${HTTP}"
fi

echo ""
echo "--- Summary ---"
echo "PASSED: ${PASS_COUNT}  FAILED: ${FAIL_COUNT}"
echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "Overall: PASS"
    exit 0
else
    echo "Overall: FAIL"
    exit 1
fi
