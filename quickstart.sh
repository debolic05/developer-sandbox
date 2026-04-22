#!/bin/bash
# Quick Start - Copy and paste this on VM: bash ~/quickstart.sh
set -e

echo "=== Developer Sandbox - Quick Start ==="
WORKSPACE="$HOME/sandbox-workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

echo "1. Setting up workspace at: $WORKSPACE"

# Link repos
[ -L eShopOnWeb ] || ln -s "$HOME/Repos/eShopOnWeb" eShopOnWeb
[ -L medplum ] || ln -s "$HOME/Repos/medplum" medplum
echo "✓ Repos linked"

# Create sandbox dirs
mkdir -p developer-sandbox/{eshopweb,medplum,scripts}
cd developer-sandbox

echo "2. Building eShopOnWeb sandbox..."
cd eshopweb
cat > docker-compose.yml << 'DOCKER'
services:
  eshopwebmvc:
    image: eshopwebmvc
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
    image: eshoppublicapi
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
DOCKER

echo "3. Building images (this takes 1-2 minutes)..."
docker compose build --pull
mkdir -p output
docker compose up -d
sleep 10

echo ""
echo "✓ eShopOnWeb is running:"
docker compose ps

echo ""
echo "4. Testing eShopOnWeb..."
curl -s -o /dev/null -w "Web: HTTP %{http_code}\n" http://localhost:5106/ || echo "Web: Not ready"
curl -s -o /dev/null -w "API: HTTP %{http_code}\n" http://localhost:5200/swagger/index.html || echo "API: Not ready"

echo ""
echo "5. Building Medplum sandbox..."
cd ../medplum
cat > medplum.config.json << 'CONFIG'
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
CONFIG
cat > docker-compose.yml << 'DOCKER'
services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      - POSTGRES_USER=medplum
      - POSTGRES_PASSWORD=medplum
    volumes:
      - medplum-postgres-data:/var/lib/postgresql/data
    command: ['postgres', '-c', 'listen_addresses=*', '-c', 'statement_timeout=60000']
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
      MEDPLUM_DATABASE_HOST: 'postgres'
      MEDPLUM_DATABASE_PORT: 5432
      MEDPLUM_DATABASE_DBNAME: 'medplum'
      MEDPLUM_DATABASE_USERNAME: 'medplum'
      MEDPLUM_DATABASE_PASSWORD: 'medplum'
      MEDPLUM_REDIS_HOST: 'redis'
      MEDPLUM_REDIS_PORT: 6379
      MEDPLUM_REDIS_PASSWORD: 'medplum'
      MEDPLUM_BINARY_STORAGE: 'file:./binary/'
    volumes:
      - ./output:/output
      - medplum-binary-storage:/app/binary
      - ./medplum.config.json:/usr/src/medplum/medplum.config.json:ro
    healthcheck:
      test: ['CMD', 'node', '-e', 'fetch("http://localhost:8103/healthcheck").then(r => r.json()).then(console.log).catch(() => { process.exit(1); })']
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
DOCKER

echo "6. Building Medplum images..."
docker compose build --pull
mkdir -p output
docker compose up -d
sleep 15

echo ""
echo "✓ Medplum is running:"
docker compose ps

echo ""
echo "7. Testing Medplum..."
curl -s http://localhost:8103/healthcheck | grep -q '"ok"' && echo "Server: Healthy" || echo "Server: Starting..."
curl -s -o /dev/null -w "App: HTTP %{http_code}\n" http://localhost:3000/ || echo "App: Not ready"

echo ""
echo "========================================"
echo "✓✓✓ Quick Start Complete! ✓✓✓"
echo "========================================"
echo ""
echo "Workspace: $WORKSPACE"
echo ""
echo "Services are running:"
echo "  eShopOnWeb Web:  http://localhost:5106"
echo "  eShopOnWeb API:  http://localhost:5200"
echo "  Medplum Server:  http://localhost:8103"
echo "  Medplum App:     http://localhost:3000"
echo ""
echo "Useful commands:"
echo "  docker ps"
echo "  docker logs <container>"
echo "  docker compose -f eshopweb/docker-compose.yml logs"
echo "  docker compose -f medplum/docker-compose.yml down"
echo ""
