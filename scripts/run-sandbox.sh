#!/bin/bash
# Developer Sandbox - Unified Launcher
# Interface for AI agent harness
# Usage: ./run-sandbox.sh <eshopweb|medplum> <build|run|reset|health>

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"

SANDBOX=${1:-}
OPERATION=${2:-run}

if [ -z "$SANDBOX" ]; then
    echo "Usage: $0 <eshopweb|medplum> <build|run|reset|health>"
    echo ""
    echo "Operations:"
    echo "  build  - Build docker images for the sandbox"
    echo "  run    - Execute full build → test → run sequence"
    echo "  reset  - Destroy and recreate sandbox from scratch"
    echo "  health - Check if sandbox services are healthy"
    exit 1
fi

SANDBOX_DIR="$SANDBOX_ROOT/$SANDBOX"
if [ ! -d "$SANDBOX_DIR" ]; then
    echo "ERROR: Unknown sandbox '$SANDBOX'"
    echo "Available: eshopweb, medplum"
    exit 1
fi

cd "$SANDBOX_DIR"

echo "[$(date)] Developer Sandbox: $SANDBOX | Operation: $OPERATION"
echo "=========================================="

case $OPERATION in
    build)
        echo "Building Docker images for $SANDBOX..."
        mkdir -p output
        docker compose build sandbox-runner
        EXIT_CODE=$?
        ;;
    
    run)
        echo "Running full sandbox sequence for $SANDBOX..."
        mkdir -p output
        rm -f output/build.log output/test-results.json output/health.json output/exit_code.txt

        echo "Starting infrastructure services..."
        if [ "$SANDBOX" = "eshopweb" ]; then
            docker compose up -d sqlserver
        else
            docker compose up -d postgres redis
        fi

        echo "Running sandbox runner..."
        set +e
        docker compose run --rm sandbox-runner
        EXIT_CODE=$?
        set -e

        echo ""
        echo "=========================================="
        if [ $EXIT_CODE -eq 0 ]; then
            echo "Sandbox $SANDBOX completed successfully."
        else
            echo "Sandbox $SANDBOX failed with exit code $EXIT_CODE."
        fi
        echo "Output files available in: $SANDBOX_DIR/output/"
        docker compose ps
        ;;
    
    reset)
        echo "Resetting sandbox to clean state..."
        echo "Stopping and removing containers..."
        docker compose down -v
        
        echo "Clearing output directory..."
        rm -rf output/
        mkdir -p output/
        
        echo "Building fresh images..."
        docker compose build --no-cache sandbox-runner
        
        echo "Sandbox reset complete."
        EXIT_CODE=$?
        ;;
    
    health)
        echo "Checking sandbox health..."
        docker compose ps
        echo ""
        echo "Latest output artifacts:"
        if [ -f output/exit_code.txt ]; then
            echo "  exit_code: $(cat output/exit_code.txt)"
        fi
        if [ -f output/test-results.json ]; then
            echo "  test_results: output/test-results.json"
        fi
        if [ -f output/health.json ]; then
            echo "  health: $(cat output/health.json)"
        fi
        EXIT_CODE=0
        ;;
    
    *)
        echo "ERROR: Unknown operation '$OPERATION'"
        echo "Valid operations: build, run, reset, health"
        EXIT_CODE=1
        ;;
esac

exit $EXIT_CODE
