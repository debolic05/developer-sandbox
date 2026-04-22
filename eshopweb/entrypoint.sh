#!/bin/bash
# eShopOnWeb Sandbox Entrypoint
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

echo "[$(date)] Starting eShopOnWeb sandbox build sequence..." | tee -a "$LOG_FILE"

# Step 1: Wait for SQL Server
echo "[$(date)] Waiting for SQL Server to be ready..." | tee -a "$LOG_FILE"
for i in {1..30}; do
    if sqlcmd -S sqlserver,1433 -U sa -P '@someThingComplicated1234' -Q "SELECT 1" &>/dev/null; then
        echo "[$(date)] SQL Server is ready!" | tee -a "$LOG_FILE"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "[$(date)] ERROR: SQL Server failed to start" | tee -a "$LOG_FILE"
        exit 1
    fi
    sleep 1
done

# Step 2: Restore NuGet packages and build
echo "[$(date)] Restoring NuGet packages..." | tee -a "$LOG_FILE"
cd /src
dotnet restore 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Building solution..." | tee -a "$LOG_FILE"
dotnet build --configuration Release 2>&1 | tee -a "$LOG_FILE"

# Step 3: Run tests with JSON output
echo "[$(date)] Running tests..." | tee -a "$LOG_FILE"
dotnet test tests/UnitTests/UnitTests.csproj \
  --configuration Release \
  --logger="json;LogFileName=$TEST_RESULTS" \
  --logger="console;verbosity=quiet" \
  2>&1 | tee -a "$LOG_FILE" || true

# Step 4: Start Web application and verify
echo "[$(date)] Starting Web application..." | tee -a "$LOG_FILE"
cd src/Web
timeout 30 dotnet run --configuration Release &
APP_PID=$!

# Wait for app to respond
sleep 5
for i in {1..20}; do
    if curl -s -f http://localhost:8080/ > /dev/null 2>&1; then
        echo "[$(date)] Web application is responding!" | tee -a "$LOG_FILE"
        echo "{ \"status\": \"healthy\", \"endpoint\": \"http://localhost:8080/\" }" > "$HEALTH_FILE"
        kill $APP_PID 2>/dev/null || true
        wait $APP_PID 2>/dev/null || true
        echo "[$(date)] eShopOnWeb sandbox build sequence completed successfully" | tee -a "$LOG_FILE"
        exit 0
    fi
    sleep 1
done

echo "[$(date)] ERROR: Web application failed to respond" | tee -a "$LOG_FILE"
kill $APP_PID 2>/dev/null || true
exit 1
