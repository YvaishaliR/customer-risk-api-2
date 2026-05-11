#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

# Load env vars so we can pass POSTGRES_USER / POSTGRES_DB to psql
set -a
# shellcheck source=../.env
source .env
set +a

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

echo "=== S2 Database Verification ==="
echo ""

# Step 1: start postgres and db-init only
echo "--- Starting postgres and db-init ---"
docker compose up -d postgres db-init
echo ""

# Step 2: wait for db-init to exit (90-second timeout)
echo "--- Waiting for db-init to complete (up to 90s) ---"
TIMEOUT=90
ELAPSED=0
DI_STATE="unknown"
DI_EXIT="-1"

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    DI_ID=$(docker compose ps -q --all db-init 2>/dev/null || true)

    if [ -n "$DI_ID" ]; then
        DI_STATE=$(docker inspect --format='{{.State.Status}}'   "$DI_ID" 2>/dev/null || echo "unknown")
        DI_EXIT=$(docker inspect  --format='{{.State.ExitCode}}' "$DI_ID" 2>/dev/null || echo "-1")
    fi

    echo "  [${ELAPSED}s] db-init=${DI_STATE}(exit=${DI_EXIT})"

    if [ "$DI_STATE" = "exited" ]; then
        break
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""

if [ "$DI_STATE" != "exited" ]; then
    echo "ERROR: db-init did not exit within ${TIMEOUT}s — aborting"
    exit 1
fi

if [ "$DI_EXIT" != "0" ]; then
    echo "ERROR: db-init exited with code ${DI_EXIT} — aborting"
    exit 1
fi

echo "db-init: completed successfully (exit 0)"
echo ""

# Helper: run one SQL check and pass/fail by comparing the result
# Usage: sql_check <label> <query> <expected> [gte]
#   op defaults to exact equality; pass "gte" for >= comparison
sql_check() {
    local label="$1"
    local query="$2"
    local expected="$3"
    local op="${4:-eq}"
    local result

    result=$(docker compose exec -T postgres \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "$query" \
        2>/dev/null | tr -d ' \n') || result=""

    if [ "$op" = "gte" ]; then
        if [ -n "$result" ] && [ "$result" -ge "$expected" ] 2>/dev/null; then
            pass "$label"
        else
            fail "$label" "expected >= ${expected}, got '${result}'"
        fi
    else
        if [ -n "$result" ] && [ "$result" -eq "$expected" ] 2>/dev/null; then
            pass "$label"
        else
            fail "$label" "expected ${expected}, got '${result}'"
        fi
    fi
}

# Step 3: run SQL checks
echo "--- SQL checks ---"

sql_check \
    "CHECK A (INV-06): All tier values are valid" \
    "SELECT COUNT(*) FROM customers WHERE tier NOT IN ('LOW','MEDIUM','HIGH');" \
    0

sql_check \
    "CHECK B (INV-07): All customers have at least one risk factor" \
    "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM risk_factors r WHERE r.customer_id = c.customer_id);" \
    0

sql_check \
    "CHECK C (INV-08): No orphaned risk factor rows" \
    "SELECT COUNT(*) FROM risk_factors rf LEFT JOIN customers c ON rf.customer_id = c.customer_id WHERE c.customer_id IS NULL;" \
    0

sql_check \
    "CHECK D (INV-09): No duplicate customer_id values" \
    "SELECT COUNT(*) FROM (SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1) dupes;" \
    0

sql_check \
    "CHECK E: All three tiers are represented" \
    "SELECT COUNT(DISTINCT tier) FROM customers;" \
    3

sql_check \
    "CHECK F: Minimum 9 seed records" \
    "SELECT COUNT(*) FROM customers;" \
    9 gte

# Step 4: docker compose down -v is handled by the trap on EXIT

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
