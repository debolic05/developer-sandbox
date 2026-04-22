#!/bin/bash
# Developer Sandbox - Unified Launcher
# Interface for AI agent harness
# Usage: ./run-sandbox.sh <eshopweb|medplum> <build|run|reset|health>

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"

SANDBOX=$1
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
        docker compose build --no-cache
        EXIT_CODE=$?
        ;;
    
    run)
        echo "Running full sandbox sequence for $SANDBOX..."
        # Create output directory
        mkdir -p output
        
        # Check if images exist, build if not
        if ! docker compose config > /dev/null 2>&1; then
            echo "Building images..."
            docker compose build
        fi
        
        # Start services in background
        echo "Starting services..."
        docker compose up -d
        
        # Wait for primary service to be healthy
        if [ "$SANDBOX" = "eshopweb" ]; then
            PRIMARY_SERVICE="eshopwebmvc"
            WAIT_TIME=45
        else
            PRIMARY_SERVICE="medplum-server"
            WAIT_TIME=60
        fi
        
        echo "Waiting for $PRIMARY_SERVICE to be healthy (max ${WAIT_TIME}s)..."
        for i in $(seq 1 $WAIT_TIME); do
            if docker compose ps | grep -q "$PRIMARY_SERVICE.*healthy"; then
                echo "Service $PRIMARY_SERVICE is healthy!"
                break
            fi
            if [ $i -eq $WAIT_TIME ]; then
                echo "WARNING: Service did not reach healthy state within timeout"
                docker compose logs
            fi
            sleep 1
        done
        
        # Display results
        echo ""
        echo "=========================================="
        echo "Sandbox $SANDBOX is running."
        echo "Output files available in: $SANDBOX_DIR/output/"
        docker compose ps
        EXIT_CODE=0
        ;;
    
    reset)
        echo "Resetting sandbox to clean state..."
        echo "Stopping and removing containers..."
        docker compose down -v
        
        echo "Clearing output directory..."
        rm -rf output/
        mkdir -p output/
        
        echo "Building fresh images..."
        docker compose build --no-cache
        
        echo "Sandbox reset complete."
        EXIT_CODE=$?
        ;;
    
    health)
        echo "Checking sandbox health..."
        docker compose ps
        echo ""
        echo "Service status:"
        if [ "$SANDBOX" = "eshopweb" ]; then
            echo "  Web: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:5106/ || echo 'N/A')"
            echo "  API: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:5200/swagger/index.html || echo 'N/A')"
            echo "  DB:  managed by sqlserver container healthcheck"
        else
            echo "  Server: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8103/healthcheck || echo 'N/A')"
            echo "  App: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/ || echo 'N/A')"
            echo "  DB: $(docker compose exec postgres pg_isready -U medplum 2>/dev/null && echo '200' || echo 'N/A')"
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
