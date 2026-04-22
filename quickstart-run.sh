#!/bin/bash
# Developer Sandbox - Quick Start on VM
# Follow these steps to validate both projects with Docker

set -e

echo "========================================"
echo "Developer Sandbox - Quick Start"
echo "========================================"
echo ""

# Configuration
SANDBOX_DIR="developer-sandbox"
ESHOP_SANDBOX="$SANDBOX_DIR/eshopweb"
MEDPLUM_SANDBOX="$SANDBOX_DIR/medplum"

# Verify docker
echo "[Step 1/6] Verifying Docker..."
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Install Docker first."
    exit 1
fi
echo "✓ Docker: $(docker --version)"
echo ""

# Check directory structure
echo "[Step 2/6] Checking sandbox structure..."
if [ ! -d "$SANDBOX_DIR" ]; then
    echo "ERROR: $SANDBOX_DIR not found in current directory"
    echo "Current directory: $(pwd)"
    echo "Please copy developer-sandbox here first."
    exit 1
fi
if [ ! -f "$ESHOP_SANDBOX/docker-compose.yml" ]; then
    echo "ERROR: eshopweb configuration missing"
    exit 1
fi
if [ ! -f "$MEDPLUM_SANDBOX/docker-compose.yml" ]; then
    echo "ERROR: medplum configuration missing"
    exit 1
fi
echo "✓ Sandbox structure verified"
echo ""

# Check project repos
echo "[Step 3/6] Checking project repositories..."
if [ ! -d "../eShopOnWeb" ] && [ ! -d "eShopOnWeb" ]; then
    echo "ERROR: eShopOnWeb repository not found"
    echo "Expected: ./eShopOnWeb or ../eShopOnWeb"
    echo "Please clone: git clone https://github.com/NimblePros/eShopOnWeb.git"
    exit 1
fi
if [ ! -d "../medplum" ] && [ ! -d "medplum" ]; then
    echo "ERROR: Medplum repository not found"
    echo "Expected: ./medplum or ../medplum"
    echo "Please clone: git clone https://github.com/medplum/medplum.git"
    exit 1
fi
echo "✓ Project repositories found"
echo ""

# Build eShopOnWeb sandbox
echo "[Step 4/6] Building eShopOnWeb sandbox..."
echo "  This may take 1-2 minutes on first run..."
cd "$ESHOP_SANDBOX"
docker compose build --pull 2>&1 | tail -10
cd - > /dev/null
echo "✓ eShopOnWeb images built"
echo ""

# Build Medplum sandbox
echo "[Step 5/6] Building Medplum sandbox..."
echo "  This may take 1-2 minutes (pulls pre-built images)..."
cd "$MEDPLUM_SANDBOX"
docker compose build --pull 2>&1 | tail -10
cd - > /dev/null
echo "✓ Medplum images built"
echo ""

# Verify builds
echo "[Step 6/6] Verifying images..."
echo ""
echo "Built images:"
docker images | grep -E "eshopweb|medplum|mssql|postgres|redis" || echo "  (Images will appear after first run)"
echo ""

echo "========================================"
echo "✓ Quick Start Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Run eShopOnWeb:"
echo "     cd $SANDBOX_DIR && ./scripts/run-sandbox.sh eshopweb run"
echo ""
echo "  2. Run Medplum:"
echo "     cd $SANDBOX_DIR && ./scripts/run-sandbox.sh medplum run"
echo ""
echo "  3. Or use the unified launcher:"
echo "     cd $SANDBOX_DIR"
echo "     ./scripts/run-sandbox.sh eshopweb run"
echo "     ./scripts/run-sandbox.sh medplum run"
echo ""
