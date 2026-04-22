#!/bin/bash
# Medplum Sandbox Entrypoint
# Builds, tests, and smoke-tests the sibling checkout inside a disposable runner.

set -euo pipefail

OUTPUT_DIR="/output"
WORKSPACE_DIR="/workspace"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$OUTPUT_DIR/build.log"
TEST_RESULTS="$OUTPUT_DIR/test-results.json"
HEALTH_FILE="$OUTPUT_DIR/health.json"
EXIT_CODE_FILE="$OUTPUT_DIR/exit_code.txt"

cleanup() {
    local exit_code=$?
    echo "$exit_code" > "$EXIT_CODE_FILE"
    if [ "$exit_code" -ne 0 ] && [ ! -f "$HEALTH_FILE" ]; then
        echo "{ \"status\": \"failed\", \"exit_code\": $exit_code }" > "$HEALTH_FILE"
    fi
}

trap cleanup EXIT

echo "[$(date)] Starting Medplum sandbox build sequence..." | tee "$LOG_FILE"

echo "[$(date)] Waiting for PostgreSQL..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if pg_isready -h postgres -U medplum >/dev/null 2>&1; then
        echo "[$(date)] PostgreSQL is ready." | tee -a "$LOG_FILE"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[$(date)] ERROR: PostgreSQL failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

echo "[$(date)] Waiting for Redis..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if redis-cli -h redis -a medplum ping >/dev/null 2>&1; then
        echo "[$(date)] Redis is ready." | tee -a "$LOG_FILE"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[$(date)] ERROR: Redis failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

cd "$WORKSPACE_DIR"

echo "[$(date)] Installing workspace dependencies..." | tee -a "$LOG_FILE"
npm ci 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Building app and server packages..." | tee -a "$LOG_FILE"
npm run build:fast 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Running database migrations..." | tee -a "$LOG_FILE"
npm --workspace @medplum/server run migrate -- file:/workspace/medplum.config.json 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Seeding test data..." | tee -a "$LOG_FILE"
npm --workspace @medplum/server run test:seed 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Running server tests..." | tee -a "$LOG_FILE"
set +e
npm --workspace @medplum/server run test -- --json --outputFile "$TEST_RESULTS" 2>&1 | tee -a "$LOG_FILE"
TEST_EXIT_CODE=${PIPESTATUS[0]}
set -e

if [ "$TEST_EXIT_CODE" -ne 0 ]; then
    echo "[$(date)] ERROR: Server tests failed" | tee -a "$LOG_FILE"
    exit "$TEST_EXIT_CODE"
fi

echo "[$(date)] Starting Medplum server for smoke test..." | tee -a "$LOG_FILE"
npm --workspace @medplum/server run start -- file:/workspace/medplum.config.json &
SERVER_PID=$!

for i in {1..45}; do
    if curl -fsS http://localhost:8103/healthcheck > /dev/null 2>&1; then
        HEALTH_RESPONSE=$(curl -fsS http://localhost:8103/healthcheck)
        printf '{ "status": "healthy", "endpoint": "http://localhost:8103/healthcheck", "response": %s }\n' "$HEALTH_RESPONSE" > "$HEALTH_FILE"
        echo "[$(date)] Medplum server responded successfully." | tee -a "$LOG_FILE"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        echo "[$(date)] Medplum sandbox build sequence completed successfully." | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 1
done

echo "[$(date)] ERROR: Medplum server failed smoke test" | tee -a "$LOG_FILE"
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
echo "{ \"status\": \"failed\", \"endpoint\": \"http://localhost:8103/healthcheck\", \"reason\": \"smoke-test-timeout\" }" > "$HEALTH_FILE"
exit 1
