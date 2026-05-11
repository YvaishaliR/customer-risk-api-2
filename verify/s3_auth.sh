#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."

PASS_COUNT=0
FAIL_COUNT=0
TEST_KEY="inv01-test-key-do-not-use"
CONTAINER="fastapi-auth-test"

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

cleanup() {
    echo ""
    echo "--- Stopping container ---"
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== S3 Auth Verification ==="
echo ""

# Step 1: build fastapi image
echo "--- Building fastapi image ---"
docker compose build fastapi 2>&1 | tail -3
echo ""

IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "customer-risk-api-dg-fastapi" | head -1)
if [ -z "$IMAGE" ]; then
    echo "ERROR: fastapi image not found after build — aborting"
    exit 1
fi
echo "Image: $IMAGE"
echo ""

# Step 2: start container standalone (no postgres/nginx required)
echo "--- Starting fastapi container ---"
docker run --rm -d --name "$CONTAINER" -p 8002:8000 \
    -e API_KEY="$TEST_KEY" \
    "$IMAGE"
echo ""

# Step 3: wait up to 30 seconds for /health to respond (auth required)
echo "--- Waiting for fastapi to be ready (up to 30s) ---"
READY=false
for i in $(seq 1 6); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-API-Key: $TEST_KEY" \
        http://localhost:8002/health 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ]; then
        echo "  [${i}] fastapi ready (HTTP 200)"
        READY=true
        break
    fi
    echo "  [${i}] not ready yet (HTTP $STATUS) — waiting 5s"
    sleep 5
done
echo ""

if [ "$READY" = "false" ]; then
    echo "ERROR: fastapi did not become ready within 30s — aborting"
    exit 1
fi

# Step 4: run checks
echo "--- Checks ---"

# INV-01-A: no X-API-Key header → 401
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8002/health)
[ "$STATUS" = "401" ] \
    && pass "[INV-01-A] No header → HTTP 401" \
    || fail "[INV-01-A] No header → HTTP 401" "got HTTP $STATUS"

# INV-01-B: wrong X-API-Key value → 401
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: wrong-key" http://localhost:8002/health)
[ "$STATUS" = "401" ] \
    && pass "[INV-01-B] Wrong header value → HTTP 401" \
    || fail "[INV-01-B] Wrong header value → HTTP 401" "got HTTP $STATUS"

# INV-01-C: correct X-API-Key value → 200
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: $TEST_KEY" http://localhost:8002/health)
[ "$STATUS" = "200" ] \
    && pass "[INV-01-C] Correct header value → HTTP 200" \
    || fail "[INV-01-C] Correct header value → HTTP 200" "got HTTP $STATUS"

# INV-01-D: 401 body must not contain key string (request with no header)
BODY=$(curl -s http://localhost:8002/health)
echo "$BODY" | grep -q "$TEST_KEY" \
    && fail "[INV-01-D] 401 body does not contain key" "key found in body: $BODY" \
    || pass "[INV-01-D] 401 body does not contain key"

# INV-02-A: response headers for a valid request must not contain key string
RESP_HEADERS=$(curl -s -D - -o /dev/null -H "X-API-Key: $TEST_KEY" http://localhost:8002/health)
echo "$RESP_HEADERS" | grep -q "$TEST_KEY" \
    && fail "[INV-02-A] Response headers do not contain key" "key found in headers" \
    || pass "[INV-02-A] Response headers do not contain key"

# INV-02-B: container logs after all requests must not contain key string
LOGS=$(docker logs "$CONTAINER" 2>&1)
echo "$LOGS" | grep -q "$TEST_KEY" \
    && fail "[INV-02-B] Container logs do not contain key" "key found in logs" \
    || pass "[INV-02-B] Container logs do not contain key"

# Step 5: container stopped by trap on EXIT

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
