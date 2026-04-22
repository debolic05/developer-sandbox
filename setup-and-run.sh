#!/bin/bash
# Developer Sandbox - Complete Setup & Quick Start
# Run this on labvm-01: bash ~/setup-and-run.sh

set -e

echo "========================================"
echo "Developer Sandbox - Complete Setup"
echo "========================================"
echo ""

# Check if we're on the VM
echo "[1/8] Verifying environment..."
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not available"
    exit 1
fi
echo "✓ Docker: $(docker --version)"
echo "✓ User: $(whoami)"
echo "✓ Host: $(hostname)"
echo ""

# Check repos exist
echo "[2/8] Checking repositories..."
if [ ! -d "$HOME/Repos/eShopOnWeb" ]; then
    echo "ERROR: eShopOnWeb not found at $HOME/Repos/eShopOnWeb"
    exit 1
fi
echo "✓ eShopOnWeb found"

if [ ! -d "$HOME/Repos/medplum" ]; then
    echo "ERROR: Medplum not found at $HOME/Repos/medplum"
    exit 1
fi
echo "✓ Medplum found"
echo ""

# Create sandbox workspace
echo "[3/8] Setting up workspace..."
WORKSPACE="$HOME/sandbox-workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"
echo "✓ Workspace: $WORKSPACE"
echo ""

# Create symlinks to repos
echo "[4/8] Linking repositories..."
if [ ! -L "eShopOnWeb" ]; then
    ln -s "$HOME/Repos/eShopOnWeb" eShopOnWeb
fi
if [ ! -L "medplum" ]; then
    ln -s "$HOME/Repos/medplum" medplum
fi
echo "✓ Repository links created"
echo ""

# Extract sandbox config from repo or create inline
echo "[5/8] Setting up sandbox configurations..."
SANDBOX_DIR="$WORKSPACE/developer-sandbox"

# Create sandbox directory structure
mkdir -p "$SANDBOX_DIR"/{eshopweb,medplum,scripts}

# Create eShopOnWeb docker-compose.yml
cat > "$SANDBOX_DIR/eshopweb/docker-compose.yml" << 'EOF'
services:
  eshopwebmvc:
    image: ${DOCKER_REGISTRY-}eshopwebmvc
    build:
      context: ../../eShopOnWeb
      dockerfile: src/Web/Dockerfile
    depends_on:
      sqlserver:
        condition: service_healthy
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:8080
      - Seq__ServerUrl=http://localhost:5341
    ports:
      - "5106:8080"
    volumes:
      - ./output:/output
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 10s
      timeout: 5s
      retries: 5

  eshoppublicapi:
    image: ${DOCKER_REGISTRY-}eshoppublicapi
    build:
      context: ../../eShopOnWeb
      dockerfile: src/PublicApi/Dockerfile
    depends_on:
      sqlserver:
        condition: service_healthy
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:8080
    ports:
      - "5200:8080"
    volumes:
      - ./output:/output
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/swagger/index.html"]
      interval: 10s
      timeout: 5s
      retries: 5

  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    ports:
      - "1433:1433"
    environment:
      - SA_PASSWORD=@someThingComplicated1234
      - ACCEPT_EULA=Y
    volumes:
      - sqlserver-data:/var/opt/mssql
    healthcheck:
      test: ["CMD", "/opt/mssql-tools18/bin/sqlcmd", "-C", "-S", "localhost", "-U", "sa", "-P", "@someThingComplicated1234", "-Q", "SELECT 1"]
      interval: 10s
      timeout: 5s
      retries: 12

volumes:
  sqlserver-data:
EOF

cat > "$SANDBOX_DIR/medplum/medplum.config.json" << 'EOF'
{
  "port": 8103,
  "baseUrl": "http://localhost:8103/",
  "appBaseUrl": "http://localhost:3000/",
  "binaryStorage": "file:./binary/",
  "storageBaseUrl": "http://localhost:8103/storage/",
  "supportEmail": "\"Medplum\" <support@medplum.com>",
  "googleClientId": "397236612778-c0b5tnjv98frbo1tfuuha5vkme3cmq4s.apps.googleusercontent.com",
  "googleClientSecret": "",
  "recaptchaSiteKey": "6LfHdsYdAAAAAC0uLnnRrDrhcXnziiUwKd8VtLNq",
  "recaptchaSecretKey": "6LfHdsYdAAAAAH9dN154jbJ3zpQife3xaiTvPChL",
  "adminClientId": "2a4b77f2-4d4e-43c6-9b01-330eb5ca772f",
  "maxJsonSize": "1mb",
  "maxBatchSize": "50mb",
  "botLambdaRoleArn": "",
  "botLambdaLayerName": "medplum-bot-layer",
  "vmContextBotsEnabled": true,
  "defaultBotRuntimeVersion": "vmcontext",
  "allowedOrigins": "*",
  "introspectionEnabled": true,
  "database": {
    "host": "postgres",
    "port": 5432,
    "dbname": "medplum",
    "username": "medplum",
    "password": "medplum"
  },
  "redis": {
    "host": "redis",
    "port": 6379,
    "password": "medplum"
  },
  "bullmq": {
    "removeOnFail": { "count": 1 },
    "removeOnComplete": { "count": 1 }
  },
  "shutdownTimeoutMilliseconds": 30000
}
EOF

# Create Medplum docker-compose.yml
cat > "$SANDBOX_DIR/medplum/docker-compose.yml" << 'EOF'
services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      - POSTGRES_USER=medplum
      - POSTGRES_PASSWORD=medplum
    volumes:
      - medplum-postgres-data:/var/lib/postgresql/data
    command:
      - 'postgres'
      - '-c'
      - 'listen_addresses=*'
      - '-c'
      - 'statement_timeout=60000'
      - '-c'
      - 'default_transaction_isolation=REPEATABLE READ'
      - '-c'
      - 'shared_preload_libraries=pg_stat_statements,auto_explain'
    ports:
      - '5432:5432'
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U medplum']
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    restart: unless-stopped
    command: redis-server --requirepass medplum
    ports:
      - '6379:6379'
    volumes:
      - medplum-redis-data:/data
    healthcheck:
      test: ['CMD', 'redis-cli', '-a', 'medplum', 'ping']
      interval: 10s
      timeout: 5s
      retries: 5

  medplum-server:
    image: medplum/medplum-server:latest
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - '8103:8103'
    environment:
      MEDPLUM_PORT: 8103
      MEDPLUM_BASE_URL: 'http://localhost:8103/'
      MEDPLUM_APP_BASE_URL: 'http://localhost:3000/'
      MEDPLUM_STORAGE_BASE_URL: 'http://localhost:8103/storage/'
      MEDPLUM_DATABASE_HOST: 'postgres'
      MEDPLUM_DATABASE_PORT: 5432
      MEDPLUM_DATABASE_DBNAME: 'medplum'
      MEDPLUM_DATABASE_USERNAME: 'medplum'
      MEDPLUM_DATABASE_PASSWORD: 'medplum'
      MEDPLUM_REDIS_HOST: 'redis'
      MEDPLUM_REDIS_PORT: 6379
      MEDPLUM_REDIS_PASSWORD: 'medplum'
      MEDPLUM_BINARY_STORAGE: 'file:./binary/'
      MEDPLUM_MAX_JSON_SIZE: '1mb'
      MEDPLUM_MAX_BATCH_SIZE: '50mb'
      MEDPLUM_VM_CONTEXT_BOTS_ENABLED: 'true'
      MEDPLUM_DEFAULT_BOT_RUNTIME_VERSION: 'vmcontext'
      MEDPLUM_ALLOWED_ORIGINS: '*'
      MEDPLUM_INTROSPECTION_ENABLED: 'true'
      MEDPLUM_SHUTDOWN_TIMEOUT_MILLISECONDS: 30000
    volumes:
      - ./output:/output
      - medplum-binary-storage:/app/binary
      - ./medplum.config.json:/usr/src/medplum/medplum.config.json:ro
    healthcheck:
      test:
        [
          'CMD',
          'node',
          '-e',
          'fetch("http://localhost:8103/healthcheck").then(r => r.json()).then(console.log).catch(() => { process.exit(1); })',
        ]
      interval: 30s
      timeout: 10s
      retries: 5

  medplum-app:
    image: medplum/medplum-app:latest
    restart: unless-stopped
    depends_on:
      medplum-server:
        condition: service_healthy
    ports:
      - '3000:3000'
    healthcheck:
      test: ['CMD', 'curl', '-f', 'http://localhost:3000']
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  medplum-postgres-data:
  medplum-redis-data:
  medplum-binary-storage:
EOF

# Create run-sandbox.sh
cat > "$SANDBOX_DIR/scripts/run-sandbox.sh" << 'SCRIPT'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_ROOT="$(dirname "$SCRIPT_DIR")"
SANDBOX=$1
OPERATION=${2:-run}

if [ -z "$SANDBOX" ]; then
    echo "Usage: $0 <eshopweb|medplum> <build|run|reset|health>"
    exit 1
fi

SANDBOX_DIR="$SANDBOX_ROOT/$SANDBOX"
cd "$SANDBOX_DIR"

case $OPERATION in
    build)
        echo "[$(date)] Building $SANDBOX images..."
        docker compose build --no-cache
        ;;
    run)
        echo "[$(date)] Running $SANDBOX sandbox..."
        mkdir -p output
        docker compose up -d
        echo "[$(date)] Waiting for services to be healthy..."
        sleep 10
        docker compose ps
        echo "[$(date)] $SANDBOX sandbox is running"
        ;;
    reset)
        echo "[$(date)] Resetting $SANDBOX..."
        docker compose down -v
        rm -rf output
        mkdir -p output
        echo "[$(date)] Reset complete"
        ;;
    health)
        echo "[$(date)] Checking $SANDBOX health..."
        docker compose ps
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        exit 1
        ;;
esac
SCRIPT

chmod +x "$SANDBOX_DIR/scripts/run-sandbox.sh"

# Create collect-results.sh
cat > "$SANDBOX_DIR/scripts/collect-results.sh" << 'SCRIPT'
#!/bin/bash
SANDBOX=$1
SANDBOX_ROOT="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
OUTPUT_DIR="$SANDBOX_ROOT/$SANDBOX/output"

EXIT_CODE=0
if [ -f "$OUTPUT_DIR/exit_code.txt" ]; then
    EXIT_CODE=$(cat "$OUTPUT_DIR/exit_code.txt")
fi

echo "{"
echo "  \"sandbox\": \"$SANDBOX\","
echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
echo "  \"exit_code\": $EXIT_CODE,"
echo "  \"containers\": $(docker ps -a --format '{{json .}}' | jq -s '.')"
echo "}"
SCRIPT

chmod +x "$SANDBOX_DIR/scripts/collect-results.sh"

echo "✓ Sandbox configuration created"
echo ""

# Build eShopOnWeb
echo "[6/8] Building eShopOnWeb images..."
cd "$SANDBOX_DIR/eshopweb"
docker compose build --pull 2>&1 | tail -5
echo "✓ eShopOnWeb images built"
echo ""

# Build Medplum
echo "[7/8] Building Medplum images..."
cd "$SANDBOX_DIR/medplum"
docker compose build --pull 2>&1 | tail -5
echo "✓ Medplum images built"
echo ""

# Test run
echo "[8/8] Testing sandboxes..."
echo ""
echo "=== eShopOnWeb Test ==="
cd "$SANDBOX_DIR/eshopweb"
docker compose up -d
sleep 5
docker compose ps
echo ""
echo "=== Medplum Test ==="
cd "$SANDBOX_DIR/medplum"
docker compose up -d
sleep 5
docker compose ps
echo ""

echo "========================================"
echo "✓ Setup Complete!"
echo "========================================"
echo ""
echo "Sandboxes are running at:"
echo "  eShopOnWeb:"
echo "    - Web: http://localhost:5106"
echo "    - API: http://localhost:5200"
echo "    - DB:  localhost:1433"
echo ""
echo "  Medplum:"
echo "    - Server: http://localhost:8103"
echo "    - App: http://localhost:3000"
echo "    - DB: localhost:5432"
echo ""
echo "Workspace: $WORKSPACE"
echo "Sandbox: $SANDBOX_DIR"
echo ""
echo "Next commands:"
echo "  cd $SANDBOX_DIR"
echo "  ./scripts/run-sandbox.sh eshopweb reset  # Clean state"
echo "  ./scripts/run-sandbox.sh medplum health  # Check status"
echo "  docker-compose logs -f                   # View logs"
