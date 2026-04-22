#!/bin/bash
# Developer Sandbox - Output Collection Script
# Collects and merges results from a sandbox run
# Usage: ./collect-results.sh <eshopweb|medplum>

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"

SANDBOX=${1:-}

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

BUILD_LOG_JSON="null"
if [ -f "$OUTPUT_DIR/build.log" ]; then
    BUILD_LOG_JSON=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$OUTPUT_DIR/build.log" | awk 'BEGIN { printf "\"" } { if (NR > 1) printf "\\n"; printf "%s", $0 } END { printf "\"" }')
fi

TEST_RESULTS_JSON='{"status":"not-run"}'
if [ -f "$OUTPUT_DIR/test-results.json" ]; then
    TEST_RESULTS_JSON=$(cat "$OUTPUT_DIR/test-results.json")
fi

HEALTH_CHECK_JSON='{"status":"unknown"}'
if [ -f "$OUTPUT_DIR/health.json" ]; then
    HEALTH_CHECK_JSON=$(cat "$OUTPUT_DIR/health.json")
fi

printf '{\n'
printf '  "sandbox": "%s",\n' "$SANDBOX"
printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '  "exit_code": %s,\n' "$EXIT_CODE"
if [ "$EXIT_CODE" -eq 0 ]; then
    printf '  "success": true,\n'
else
    printf '  "success": false,\n'
fi
printf '  "build_log": %s,\n' "$BUILD_LOG_JSON"
printf '  "test_results": %s,\n' "$TEST_RESULTS_JSON"
printf '  "health_check": %s\n' "$HEALTH_CHECK_JSON"
printf '}\n'

exit $EXIT_CODE
