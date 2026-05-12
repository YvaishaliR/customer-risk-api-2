#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASIC_AUTH_USER=$(grep "^BASIC_AUTH_USER=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
BASIC_AUTH_PASSWORD=$(grep "^BASIC_AUTH_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
POSTGRES_DB=$(grep "^POSTGRES_DB=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
POSTGRES_USER=$(grep "^POSTGRES_USER=" "$PROJECT_ROOT/.env" | cut -d= -f2-)

if [ -z "$BASIC_AUTH_USER" ] || [ -z "$BASIC_AUTH_PASSWORD" ] || \
   [ -z "$POSTGRES_DB" ] || [ -z "$POSTGRES_USER" ]; then
    echo "ERROR: BASIC_AUTH_USER, BASIC_AUTH_PASSWORD, POSTGRES_DB, POSTGRES_USER must all be set in .env" >&2
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

psql_exec() {
    docker compose exec -T postgres \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "$1" \
        2>/dev/null || echo ""
}

# ── INV-06-DB ─────────────────────────────────────────────────────────────────
COUNT=$(psql_exec \
    "SELECT COUNT(*) FROM customers WHERE tier NOT IN ('LOW','MEDIUM','HIGH');")
if [ "${COUNT:-1}" = "0" ]; then
    pass "INV-06-DB: all customer tier values are within {LOW, MEDIUM, HIGH}"
else
    fail "INV-06-DB: ${COUNT:-unknown} customer row(s) with tier value outside {LOW, MEDIUM, HIGH}"
fi

# ── INV-07-DB ─────────────────────────────────────────────────────────────────
COUNT=$(psql_exec \
    "SELECT COUNT(*) FROM customers c
     WHERE NOT EXISTS (
         SELECT 1 FROM risk_factors r WHERE r.customer_id = c.customer_id
     );")
if [ "${COUNT:-1}" = "0" ]; then
    pass "INV-07-DB: every customer has at least one risk_factor row"
else
    fail "INV-07-DB: ${COUNT:-unknown} customer(s) with zero associated risk_factors"
fi

# ── INV-08-DB ─────────────────────────────────────────────────────────────────
COUNT=$(psql_exec \
    "SELECT COUNT(*) FROM risk_factors rf
     LEFT JOIN customers c ON rf.customer_id = c.customer_id
     WHERE c.customer_id IS NULL;")
if [ "${COUNT:-1}" = "0" ]; then
    pass "INV-08-DB: no orphaned risk_factor rows (every customer_id references an existing customer)"
else
    fail "INV-08-DB: ${COUNT:-unknown} orphaned risk_factor row(s) with no matching customer"
fi

# ── INV-09-DB ─────────────────────────────────────────────────────────────────
COUNT=$(psql_exec \
    "SELECT COUNT(*) FROM (
         SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1
     ) dupes;")
if [ "${COUNT:-1}" = "0" ]; then
    pass "INV-09-DB: no duplicate customer_id values (primary key uniqueness confirmed)"
else
    fail "INV-09-DB: ${COUNT:-unknown} customer_id group(s) with duplicate rows"
fi

# ── API checks: INV-04-API, INV-06-API, INV-07-API ───────────────────────────
# Loop all 9 seed customers. Failures are counted per invariant; one pass/fail
# message is printed per invariant after the loop.
INV04_FAIL=0
INV06_FAIL=0
INV07_FAIL=0

echo "  Querying all 9 seed customers via Nginx..."
for i in $(seq 1 9); do
    CUST_ID=$(printf 'CUST%03d' "$i")
    RESP=$(curl -s \
        -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
        "http://localhost:80/api/risk/$CUST_ID" 2>/dev/null || echo "")

    # Extract customer_id: "customer_id":"CUST001" → CUST001
    RESP_CUST=$(echo "$RESP" | grep -o '"customer_id":"[^"]*"' | cut -d'"' -f4 || echo "")
    # Extract tier: "tier":"LOW" → LOW
    RESP_TIER=$(echo "$RESP" | grep -o '"tier":"[A-Z]*"' | grep -o '"[A-Z]*"$' | tr -d '"' || echo "")
    # Count risk factor entries in the array
    RESP_FACTOR_COUNT=$(echo "$RESP" | grep -c '"factor_code"' || echo "0")

    # INV-04: response.customer_id must match the URL parameter (populated from DB row, not path)
    if [ "$RESP_CUST" != "$CUST_ID" ]; then
        echo "  [INV-04-API] FAIL $CUST_ID: response customer_id='${RESP_CUST:-empty}'"
        INV04_FAIL=$((INV04_FAIL + 1))
    fi

    # INV-06: response.tier must be exactly one of {LOW, MEDIUM, HIGH}
    if [ "$RESP_TIER" != "LOW" ] && [ "$RESP_TIER" != "MEDIUM" ] && [ "$RESP_TIER" != "HIGH" ]; then
        echo "  [INV-06-API] FAIL $CUST_ID: tier='${RESP_TIER:-empty}'"
        INV06_FAIL=$((INV06_FAIL + 1))
    fi

    # INV-07: response.risk_factors must be non-empty (empty array → HTTP 500 per spec;
    # a 200 with zero factor_code entries also counts as a failure here)
    if [ "$RESP_FACTOR_COUNT" -eq 0 ]; then
        echo "  [INV-07-API] FAIL $CUST_ID: risk_factors empty (response: $(echo "$RESP" | head -c 120))"
        INV07_FAIL=$((INV07_FAIL + 1))
    fi
done

if [ "$INV04_FAIL" -eq 0 ]; then
    pass "INV-04-API: response.customer_id == request customer_id for all 9 seed customers"
else
    fail "INV-04-API: customer_id mismatch for $INV04_FAIL of 9 seed customers"
fi

if [ "$INV06_FAIL" -eq 0 ]; then
    pass "INV-06-API: response.tier in {LOW, MEDIUM, HIGH} for all 9 seed customers"
else
    fail "INV-06-API: invalid tier value for $INV06_FAIL of 9 seed customers"
fi

if [ "$INV07_FAIL" -eq 0 ]; then
    pass "INV-07-API: response.risk_factors non-empty for all 9 seed customers"
else
    fail "INV-07-API: empty risk_factors for $INV07_FAIL of 9 seed customers"
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
