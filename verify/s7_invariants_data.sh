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

api_get() {
    curl -s -o /dev/null \
        -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
        "http://localhost:80/api/risk/$1" || true
}

# ── INV-05: Read-only enforcement ─────────────────────────────────────────────

# Step 1: pre-request checksums
CK_CUST_PRE=$(psql_exec \
    "SELECT md5(string_agg(customer_id || tier, ',' ORDER BY customer_id)) FROM customers;")
CK_RF_PRE=$(psql_exec \
    "SELECT md5(string_agg(customer_id || factor_code, ',' ORDER BY id)) FROM risk_factors;")

echo "  [INV-05] Pre-request checksums:"
echo "    customers:    ${CK_CUST_PRE:-<empty>}"
echo "    risk_factors: ${CK_RF_PRE:-<empty>}"

if [ -z "$CK_CUST_PRE" ] || [ -z "$CK_RF_PRE" ]; then
    fail "[INV-05]: could not read pre-request checksums from database"
else
    # Step 2: 50 API requests cycling through all 9 seed customers
    echo "  [INV-05] Making 50 API requests..."
    for i in $(seq 1 50); do
        IDX=$(( (i - 1) % 9 + 1 ))
        api_get "$(printf 'CUST%03d' "$IDX")"
    done

    # Step 3: post-request checksums
    CK_CUST_POST=$(psql_exec \
        "SELECT md5(string_agg(customer_id || tier, ',' ORDER BY customer_id)) FROM customers;")
    CK_RF_POST=$(psql_exec \
        "SELECT md5(string_agg(customer_id || factor_code, ',' ORDER BY id)) FROM risk_factors;")

    echo "  [INV-05] Post-request checksums:"
    echo "    customers:    ${CK_CUST_POST:-<empty>}"
    echo "    risk_factors: ${CK_RF_POST:-<empty>}"

    # Steps 4 & 5: assert pre == post
    if [ "$CK_CUST_PRE" = "$CK_CUST_POST" ] && [ "$CK_RF_PRE" = "$CK_RF_POST" ]; then
        pass "[INV-05]: checksums unchanged after 50 API requests — no writes occurred"
    else
        fail "[INV-05]: checksum mismatch after API requests — unexpected write detected"
        [ "$CK_CUST_PRE" != "$CK_CUST_POST" ] && \
            echo "  customers    pre=${CK_CUST_PRE}  post=${CK_CUST_POST}"
        [ "$CK_RF_PRE" != "$CK_RF_POST" ] && \
            echo "  risk_factors pre=${CK_RF_PRE}  post=${CK_RF_POST}"
    fi
fi

# ── INV-10: Live query (no cache) ─────────────────────────────────────────────

# Step 1: read current tier via API
RESP=$(curl -s \
    -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
    "http://localhost:80/api/risk/CUST001" 2>/dev/null || echo "")
ORIG_TIER=$(echo "$RESP" | grep -o '"tier":"[A-Z]*"' | grep -o '"[A-Z]*"$' | tr -d '"' || echo "")

if [ -z "$ORIG_TIER" ]; then
    fail "[INV-10]: could not read current tier for CUST001 from API"
else
    echo "  [INV-10] CUST001 current tier (API): $ORIG_TIER"

    # Step 2: update tier in DB — only if not already HIGH to avoid a no-op
    psql_exec "UPDATE customers SET tier='HIGH' WHERE customer_id='CUST001' AND tier != 'HIGH';" > /dev/null

    # Step 3: immediately query API
    RESP2=$(curl -s \
        -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASSWORD" \
        "http://localhost:80/api/risk/CUST001" 2>/dev/null || echo "")
    NEW_TIER=$(echo "$RESP2" | grep -o '"tier":"[A-Z]*"' | grep -o '"[A-Z]*"$' | tr -d '"' || echo "")

    echo "  [INV-10] CUST001 tier after DB update (API): ${NEW_TIER:-<empty>}"

    # Step 4: assert API reflects the DB state
    if [ "$NEW_TIER" = "HIGH" ]; then
        pass "[INV-10]: API reflects live DB value (tier=HIGH) — no stale cache"
    else
        fail "[INV-10]: API returned '${NEW_TIER:-empty}' after DB was set to HIGH — stale cache suspected"
    fi

    # Step 5: restore original tier
    psql_exec "UPDATE customers SET tier='$ORIG_TIER' WHERE customer_id='CUST001';" > /dev/null
    echo "  [INV-10] CUST001 tier restored to $ORIG_TIER"
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
