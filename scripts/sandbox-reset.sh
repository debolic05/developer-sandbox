#!/bin/bash
# Developer Sandbox - Reset Script
# Completely destroys and recreates sandbox from scratch
# Usage: ./sandbox-reset.sh <eshopweb|medplum> [--full]

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"

SANDBOX=$1
FULL_RESET=${2:-false}

if [ -z "$SANDBOX" ]; then
    echo "Usage: $0 <eshopweb|medplum> [--full]"
    echo ""
    echo "Performs a cold start reset of the sandbox."
    echo "--full: Also prune Docker system to remove orphaned images/volumes"
    exit 1
fi

SANDBOX_DIR="$SANDBOX_ROOT/$SANDBOX"
if [ ! -d "$SANDBOX_DIR" ]; then
    echo "ERROR: Unknown sandbox '$SANDBOX'"
    exit 1
fi

cd "$SANDBOX_DIR"

echo "[$(date)] Resetting sandbox: $SANDBOX"
echo "=========================================="

# Step 1: Stop and remove containers
echo "[$(date)] Stopping containers..."
docker compose down -v 2>/dev/null || true

# Step 2: Prune if requested
if [ "$FULL_RESET" = "--full" ]; then
    echo "[$(date)] Running full Docker prune..."
    docker system prune -f --volumes 2>/dev/null || true
fi

# Step 3: Clear output directory
echo "[$(date)] Clearing output directory..."
rm -rf output/
mkdir -p output/

# Step 4: Rebuild images from scratch
echo "[$(date)] Building fresh Docker images..."
docker compose build --no-cache

echo "[$(date)] Reset complete!"
echo "Run './scripts/run-sandbox.sh $SANDBOX run' to start."
