#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TIMEOUT=90

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() { docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v 2>/dev/null || true; }
trap cleanup EXIT

cd "$PROJECT_ROOT"

# Start only the services needed to confirm fastapi is actually running —
# the isolation check is only meaningful when the container is up.
echo "=== Starting postgres, db-init, fastapi ==="
docker compose up -d postgres db-init fastapi

echo "=== Waiting for fastapi healthy (up to ${TIMEOUT}s) ==="
DI_STATUS=""
DI_EXIT="-1"
FA_HEALTH=""
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    DI_ID=$(docker compose ps -q --all db-init 2>/dev/null || echo "")
    FA_ID=$(docker compose ps -q fastapi 2>/dev/null || echo "")

    DI_STATUS=""
    DI_EXIT="-1"
    FA_HEALTH=""

    if [ -n "$DI_ID" ]; then
        DI_STATUS=$(docker inspect --format='{{.State.Status}}' "$DI_ID" 2>/dev/null || echo "")
        DI_EXIT=$(docker inspect --format='{{.State.ExitCode}}' "$DI_ID" 2>/dev/null || echo "-1")
    fi
    if [ -n "$FA_ID" ]; then
        FA_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$FA_ID" 2>/dev/null || echo "")
    fi

    if [ "$DI_STATUS" = "exited" ] && [ "$DI_EXIT" = "0" ] && [ "$FA_HEALTH" = "healthy" ]; then
        echo "FastAPI healthy after ${ELAPSED}s"
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: FastAPI did not become healthy within ${TIMEOUT}s" \
         "— db-init=${DI_STATUS:-unknown}/${DI_EXIT:-unknown}, fastapi=${FA_HEALTH:-unknown}"
    exit 1
fi

echo ""
echo "=== Check ==="

# Attempt to reach FastAPI directly on port 8000 from the host.
# curl writes "%{http_code}" = "000" to stdout even when it exits non-zero
# (connection refused or timeout), so || true prevents set -e from aborting
# without adding a second "000" to the captured output.
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 3 http://localhost:8000/health 2>/dev/null || true)

if [ "$HTTP_CODE" = "200" ]; then
    fail "[S5-ISOLATION]: FastAPI port 8000 IS reachable from the host (HTTP 200) — docker-compose.yml must not expose port 8000 via 'ports:'"
else
    pass "[S5-ISOLATION]: FastAPI port 8000 is NOT reachable from the host (response: \"${HTTP_CODE:-none}\") — all external traffic must pass through nginx"
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
