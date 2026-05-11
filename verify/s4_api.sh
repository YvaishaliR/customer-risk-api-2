#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

API_KEY=$(grep "^API_KEY=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
POSTGRES_USER=$(grep "^POSTGRES_USER=" "$PROJECT_ROOT/.env" | cut -d= -f2-)
POSTGRES_DB=$(grep "^POSTGRES_DB=" "$PROJECT_ROOT/.env" | cut -d= -f2-)

if [ -z "$API_KEY" ]; then
    echo "ERROR: API_KEY not found in .env" >&2
    exit 1
fi

PASS=0
FAIL=0
TIMEOUT=90

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() { docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v 2>/dev/null || true; }
trap cleanup EXIT

cd "$PROJECT_ROOT"

echo "=== Starting postgres, db-init, fastapi ==="
docker compose up -d postgres db-init fastapi

echo "=== Waiting for db-init exit 0 and fastapi healthy (up to ${TIMEOUT}s) ==="
DI_STATUS=""
DI_EXIT="-1"
FA_HEALTH=""
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    DI_ID=$(docker compose ps -q --all db-init 2>/dev/null || echo "")
    FA_ID=$(docker compose ps -q fastapi 2>/dev/null || echo "")

    if [ -n "$DI_ID" ]; then
        DI_STATUS=$(docker inspect --format='{{.State.Status}}' "$DI_ID" 2>/dev/null || echo "")
        DI_EXIT=$(docker inspect --format='{{.State.ExitCode}}' "$DI_ID" 2>/dev/null || echo "-1")
    fi
    if [ -n "$FA_ID" ]; then
        FA_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$FA_ID" 2>/dev/null || echo "")
    fi

    if [ "$DI_STATUS" = "exited" ] && [ "$DI_EXIT" = "0" ] && [ "$FA_HEALTH" = "healthy" ]; then
        echo "Stack ready (db-init exited 0, fastapi healthy) after ${ELAPSED}s"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: stack not ready within ${TIMEOUT}s — db-init status=${DI_STATUS:-unknown}/exit=${DI_EXIT:-unknown}, fastapi health=${FA_HEALTH:-unknown}"
    exit 1
fi

# Run curl inside the fastapi container; returns "" on exec failure.
api_get() {
    docker compose exec -T fastapi curl -s "$@" 2>/dev/null || echo ""
}

echo ""
echo "=== Checks ==="

# ── S4-A ──────────────────────────────────────────────────────────────────────
STATUS=$(api_get -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: $API_KEY" http://localhost:8000/api/risk/CUST001)
if [ "$STATUS" = "200" ]; then
    pass "S4-A: GET /api/risk/CUST001 correct key → HTTP 200"
else
    fail "S4-A: GET /api/risk/CUST001 correct key → expected 200, got $STATUS"
fi

# Fetch body once; reused by S4-B, S4-C, S4-D.
BODY=$(api_get -H "X-API-Key: $API_KEY" http://localhost:8000/api/risk/CUST001)

# ── S4-B ──────────────────────────────────────────────────────────────────────
CUST_ID=$(echo "$BODY" | grep -o '"customer_id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
if [ "$CUST_ID" = "CUST001" ]; then
    pass "S4-B: response customer_id == \"CUST001\""
else
    fail "S4-B: response customer_id expected \"CUST001\", got \"$CUST_ID\""
fi

# ── S4-C ──────────────────────────────────────────────────────────────────────
TIER=$(echo "$BODY" | grep -o '"tier":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
case "$TIER" in
    LOW|MEDIUM|HIGH) pass "S4-C: tier \"$TIER\" is member of {LOW, MEDIUM, HIGH}" ;;
    *)               fail "S4-C: tier \"$TIER\" is not in {LOW, MEDIUM, HIGH}" ;;
esac

# ── S4-D ──────────────────────────────────────────────────────────────────────
if echo "$BODY" | grep -q '"factor_code"'; then
    pass "S4-D: risk_factors is non-empty array"
else
    fail "S4-D: risk_factors is empty or missing"
fi

# ── INV-04 ────────────────────────────────────────────────────────────────────
# Response customer_id must match the requested customer_id for every seed customer.
INV04_FAIL=0
for CID in CUST001 CUST002 CUST003 CUST004 CUST005 CUST006 CUST007 CUST008 CUST009; do
    RESP=$(api_get -H "X-API-Key: $API_KEY" "http://localhost:8000/api/risk/$CID")
    DB_CID=$(echo "$RESP" | grep -o '"customer_id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    if [ "$DB_CID" != "$CID" ]; then
        echo "  INV-04 mismatch: requested $CID, response customer_id=\"$DB_CID\""
        INV04_FAIL=$((INV04_FAIL + 1))
    fi
done
if [ "$INV04_FAIL" -eq 0 ]; then
    pass "INV-04: response customer_id matches request customer_id for all 9 seed customers"
else
    fail "INV-04: $INV04_FAIL customer(s) returned mismatched customer_id"
fi

# ── INV-05 ────────────────────────────────────────────────────────────────────
# Row count in customers must be identical before and after 20 API requests.
COUNT_BEFORE=$(docker compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A \
    -c "SELECT COUNT(*) FROM customers;" 2>/dev/null \
    | tr -d ' \n' || echo "")

for i in $(seq 1 20); do
    api_get -o /dev/null -H "X-API-Key: $API_KEY" \
        http://localhost:8000/api/risk/CUST001 > /dev/null
done

COUNT_AFTER=$(docker compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A \
    -c "SELECT COUNT(*) FROM customers;" 2>/dev/null \
    | tr -d ' \n' || echo "")

if [ -n "$COUNT_BEFORE" ] && [ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; then
    pass "INV-05: customers count unchanged ($COUNT_BEFORE) after 20 requests — no writes during API operation"
else
    fail "INV-05: customers count changed $COUNT_BEFORE → $COUNT_AFTER — writes detected during API operation"
fi

# ── S4-E ──────────────────────────────────────────────────────────────────────
STATUS=$(api_get -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: $API_KEY" http://localhost:8000/api/risk/NONEXISTENT)
if [ "$STATUS" = "404" ]; then
    pass "S4-E: GET /api/risk/NONEXISTENT → HTTP 404"
else
    fail "S4-E: GET /api/risk/NONEXISTENT → expected 404, got $STATUS"
fi

# ── S4-F ──────────────────────────────────────────────────────────────────────
STATUS=$(api_get -o /dev/null -w "%{http_code}" http://localhost:8000/api/risk/CUST001)
if [ "$STATUS" = "401" ]; then
    pass "S4-F: GET /api/risk/CUST001 no key → HTTP 401"
else
    fail "S4-F: GET /api/risk/CUST001 no key → expected 401, got $STATUS"
fi

# ── S4-G ──────────────────────────────────────────────────────────────────────
STATUS=$(api_get -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: wrong-key" http://localhost:8000/api/risk/CUST001)
if [ "$STATUS" = "401" ]; then
    pass "S4-G: GET /api/risk/CUST001 wrong key → HTTP 401"
else
    fail "S4-G: GET /api/risk/CUST001 wrong key → expected 401, got $STATUS"
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
