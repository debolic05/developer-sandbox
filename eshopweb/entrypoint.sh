#!/bin/bash
# eShopOnWeb Sandbox Entrypoint
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

echo "[$(date)] Starting eShopOnWeb sandbox build sequence..." | tee "$LOG_FILE"

echo "[$(date)] Waiting for SQL Server port 1433..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if bash -c 'echo > /dev/tcp/sqlserver/1433' >/dev/null 2>&1; then
        echo "[$(date)] SQL Server is reachable." | tee -a "$LOG_FILE"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[$(date)] ERROR: SQL Server failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

cd "$WORKSPACE_DIR"

echo "[$(date)] Restoring NuGet packages..." | tee -a "$LOG_FILE"
dotnet restore 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Building solution..." | tee -a "$LOG_FILE"
dotnet build --configuration Release --no-restore 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Running unit tests..." | tee -a "$LOG_FILE"
set +e
dotnet test tests/UnitTests/UnitTests.csproj \
  --configuration Release \
  --no-build \
  --logger "trx;LogFileName=unit-tests.trx" \
  --results-directory "$OUTPUT_DIR" \
  2>&1 | tee -a "$LOG_FILE"
TEST_EXIT_CODE=${PIPESTATUS[0]}
set -e

TEST_STATUS="passed"
if [ "$TEST_EXIT_CODE" -ne 0 ]; then
    TEST_STATUS="failed"
fi

cat > "$TEST_RESULTS" <<EOF
{ "framework": "dotnet test", "project": "tests/UnitTests/UnitTests.csproj", "status": "$TEST_STATUS", "exit_code": $TEST_EXIT_CODE, "results_file": "unit-tests.trx" }
EOF

if [ "$TEST_EXIT_CODE" -ne 0 ]; then
    echo "[$(date)] ERROR: Unit tests failed" | tee -a "$LOG_FILE"
    exit "$TEST_EXIT_CODE"
fi

echo "[$(date)] Starting Web application for smoke test..." | tee -a "$LOG_FILE"
cd src/Web
dotnet run --configuration Release --no-build &
APP_PID=$!

for i in {1..30}; do
    if curl -fsS http://localhost:8080/ > /dev/null 2>&1; then
        echo "{ \"status\": \"healthy\", \"endpoint\": \"http://localhost:8080/\" }" > "$HEALTH_FILE"
        echo "[$(date)] Web application responded successfully." | tee -a "$LOG_FILE"
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
        echo "[$(date)] eShopOnWeb sandbox build sequence completed successfully." | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 1
done

echo "[$(date)] ERROR: Web application failed smoke test" | tee -a "$LOG_FILE"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
echo "{ \"status\": \"failed\", \"endpoint\": \"http://localhost:8080/\", \"reason\": \"smoke-test-timeout\" }" > "$HEALTH_FILE"
exit 1
