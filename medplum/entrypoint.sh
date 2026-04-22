#!/bin/bash
# Medplum Sandbox Entrypoint
# Non-interactive execution for AI agent harness
# Captures build, test, and runtime output to /output/

set -e

OUTPUT_DIR="/output"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$OUTPUT_DIR/build.log"
TEST_RESULTS="$OUTPUT_DIR/test-results.json"
HEALTH_FILE="$OUTPUT_DIR/health.json"
EXIT_CODE_FILE="$OUTPUT_DIR/exit_code.txt"

# Cleanup function
cleanup() {
    EXIT_CODE=$?
    echo $EXIT_CODE > "$EXIT_CODE_FILE"
    if [ $EXIT_CODE -eq 0 ]; then
        echo "{ \"status\": \"success\", \"exit_code\": 0 }" > "$HEALTH_FILE"
    else
        echo "{ \"status\": \"failed\", \"exit_code\": $EXIT_CODE }" > "$HEALTH_FILE"
    fi
    exit $EXIT_CODE
}

trap cleanup EXIT

echo "[$(date)] Starting Medplum sandbox build sequence..." | tee -a "$LOG_FILE"

# Step 1: Wait for PostgreSQL and Redis
echo "[$(date)] Waiting for PostgreSQL to be ready..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if pg_isready -h postgres -U medplum &>/dev/null; then
        echo "[$(date)] PostgreSQL is ready!" | tee -a "$LOG_FILE"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "[$(date)] ERROR: PostgreSQL failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

echo "[$(date)] Waiting for Redis to be ready..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if redis-cli -h redis -a medplum ping &>/dev/null; then
        echo "[$(date)] Redis is ready!" | tee -a "$LOG_FILE"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "[$(date)] ERROR: Redis failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

# Step 2: Run migrations
echo "[$(date)] Running database migrations..." | tee -a "$LOG_FILE"
cd /app/packages/server
npm run migrate 2>&1 | tee -a "$LOG_FILE"

# Step 3: Install dependencies and build
echo "[$(date)] Installing dependencies..." | tee -a "$LOG_FILE"
cd /app
npm ci 2>&1 | tee -a "$LOG_FILE" || npm install 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Building server..." | tee -a "$LOG_FILE"
cd packages/server
npm run build 2>&1 | tee -a "$LOG_FILE"

# Step 4: Seed test database
echo "[$(date)] Seeding test database..." | tee -a "$LOG_FILE"
npm run test:seed 2>&1 | tee -a "$LOG_FILE" || true

# Step 5: Run tests with JSON output
echo "[$(date)] Running tests..." | tee -a "$LOG_FILE"
npm run test -- --json --outputFile "$TEST_RESULTS" 2>&1 | tee -a "$LOG_FILE" || true

# Step 6: Start server and verify health
echo "[$(date)] Starting Medplum server..." | tee -a "$LOG_FILE"
timeout 30 npm run start &
SERVER_PID=$!

# Wait for server to respond to health check
sleep 5
for i in {1..20}; do
    if curl -s -f http://localhost:8103/healthcheck > /dev/null 2>&1; then
        HEALTH_RESPONSE=$(curl -s http://localhost:8103/healthcheck)
        echo "[$(date)] Medplum server is healthy! Response: $HEALTH_RESPONSE" | tee -a "$LOG_FILE"
        echo "{ \"status\": \"healthy\", \"endpoint\": \"http://localhost:8103/healthcheck\", \"response\": $HEALTH_RESPONSE }" > "$HEALTH_FILE"
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        echo "[$(date)] Medplum sandbox build sequence completed successfully" | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 1
done

echo "[$(date)] ERROR: Medplum server failed to respond to health check" | tee -a "$LOG_FILE"
kill $SERVER_PID 2>/dev/null || true
exit 1
