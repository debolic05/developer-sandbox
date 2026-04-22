#!/bin/bash
# Developer Sandbox - VM Setup Script
# Run this on labvm-01 to prepare the sandbox environment

set -e

echo "=== Developer Sandbox Setup for labvm-01 ==="
echo ""

# Step 1: Create working directory
echo "[1/4] Creating working directory..."
mkdir -p ~/sandbox-workspace
cd ~/sandbox-workspace

# Step 2: Clone required repositories
echo "[2/4] Cloning projects..."
if [ ! -d "eShopOnWeb" ]; then
    echo "  Cloning eShopOnWeb..."
    git clone https://github.com/NimblePros/eShopOnWeb.git
    echo "  ✓ eShopOnWeb cloned"
else
    echo "  ✓ eShopOnWeb already present"
fi

if [ ! -d "medplum" ]; then
    echo "  Cloning Medplum..."
    git clone https://github.com/medplum/medplum.git
    echo "  ✓ Medplum cloned"
else
    echo "  ✓ Medplum already present"
fi

# Step 3: Verify Docker is available
echo "[3/4] Verifying Docker..."
docker --version || { echo "ERROR: Docker not available"; exit 1; }
docker compose version || { echo "ERROR: Docker Compose not available"; exit 1; }
echo "  ✓ Docker ready"

# Step 4: Summary
echo "[4/4] Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Copy developer-sandbox directory to: ~/sandbox-workspace/"
echo "  2. Navigate to: cd ~/sandbox-workspace/developer-sandbox"
echo "  3. Run quick start: ./scripts/run-sandbox.sh eshopweb build"
echo ""
echo "Working directory: $(pwd)"
echo "Projects:"
echo "  - eShopOnWeb: $(pwd)/eShopOnWeb"
echo "  - Medplum: $(pwd)/medplum"
