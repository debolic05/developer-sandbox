#!/bin/bash
# Developer Sandbox - Output Collection Script
# Collects and merges results from a sandbox run
# Usage: ./collect-results.sh <eshopweb|medplum>

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"

SANDBOX=$1

if [ -z "$SANDBOX" ]; then
    echo "Usage: $0 <eshopweb|medplum>"
    exit 1
fi

SANDBOX_DIR="$SANDBOX_ROOT/$SANDBOX"
OUTPUT_DIR="$SANDBOX_DIR/output"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "{\"status\": \"error\", \"message\": \"Output directory not found\"}"
    exit 1
fi

# Collect exit code
EXIT_CODE=0
if [ -f "$OUTPUT_DIR/exit_code.txt" ]; then
    EXIT_CODE=$(cat "$OUTPUT_DIR/exit_code.txt")
fi

# Collect build log
BUILD_LOG=""
if [ -f "$OUTPUT_DIR/build.log" ]; then
    BUILD_LOG=$(cat "$OUTPUT_DIR/build.log")
fi

# Collect test results
TEST_RESULTS=""
if [ -f "$OUTPUT_DIR/test-results.json" ]; then
    TEST_RESULTS=$(cat "$OUTPUT_DIR/test-results.json")
else
    TEST_RESULTS="{\"status\": \"not-run\"}"
fi

# Collect health check
HEALTH_CHECK=""
if [ -f "$OUTPUT_DIR/health.json" ]; then
    HEALTH_CHECK=$(cat "$OUTPUT_DIR/health.json")
else
    HEALTH_CHECK="{\"status\": \"unknown\"}"
fi

# Generate unified results JSON
cat <<EOF
{
  "sandbox": "$SANDBOX",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "exit_code": $EXIT_CODE,
  "success": $([ $EXIT_CODE -eq 0 ] && echo "true" || echo "false"),
  "build_log": "$(echo "$BUILD_LOG" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')",
  "test_results": $TEST_RESULTS,
  "health_check": $HEALTH_CHECK
}
EOF

exit $EXIT_CODE
