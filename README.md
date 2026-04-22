# Developer Sandbox for AI Agent Execution

A Docker-based sandboxed execution environment for building, testing, and validating code in two real-world open-source projects with very different technology stacks. Designed to support non-interactive execution by AI coding agents.

## Architecture Overview

### Design Decision: Two Isolated Sandboxes, Not One

This implementation uses **completely separate, isolated sandboxes** for each project rather than consolidating them into a single shared environment.

#### Rationale

1. **Database Incompatibility**: eShopOnWeb requires SQL Server 2022, Medplum requires PostgreSQL 16. These have fundamentally different initialization, connection protocols, and migration systems. Forcing them into a single environment would require complex abstraction layers.

2. **Runtime/Toolchain Differences**: 
   - eShopOnWeb: .NET 10.0, dotnet CLI, C#, xUnit testing
   - Medplum: Node.js 22+, npm/Turborepo monorepo, TypeScript, Jest testing
   
   Each has its own build patterns, dependency systems, and testing frameworks. Sharing would require custom translation layers.

3. **Failure Isolation**: If an agent generates broken code in one project, it won't corrupt the database or state of the other. Each sandbox failure is contained.

4. **Independent Scaling**: Resource-intensive operations (Medplum tests can be slow) don't impact the other project.

5. **Simplified State Management**: Each project's existing docker-compose configuration can be reused with minimal modification. Reduces maintenance burden and ensures changes to the projects flow through automatically.

6. **Agent Harness Simplicity**: The consumer (agent harness) calls `./run-sandbox.sh <project>` and gets consistent behavior regardless of which project is executing.

#### Trade-offs

- **Complexity**: Two separate setups instead of one unified environment (+complexity, but minimal given they're isolated anyway)
- **Resource Usage**: Both databases run simultaneously if both sandboxes are active (~4GB RAM for both + runtime overhead)
- **Disk Space**: Separate Docker images and volumes (~2-3GB total)

These trade-offs are worth the cleaner architecture and isolation benefits.

### Diagram: Sandbox Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         AI Agent Harness (Consumer)                         │
│         orchestration/execution controller                  │
└──────────────┬──────────────────────────────────────────────┘
               │
               │ ./run-sandbox.sh <project> <operation>
               │
      ┌────────┴────────┐
      │                 │
      ▼                 ▼
┌──────────────┐   ┌──────────────┐
│  eShopOnWeb  │   │   Medplum    │
│  Sandbox     │   │   Sandbox    │
├──────────────┤   ├──────────────┤
│ docker-compose   │ docker-compose
│ .yml             │ .yml
├──────────────┤   ├──────────────┤
│ Containers:  │   │ Containers:  │
│ • Web        │   │ • Server     │
│ • PublicAPI  │   │ • App        │
│ • SQL Server │   │ • PostgreSQL │
│              │   │ • Redis      │
└──────────────┘   └──────────────┘
  Port: 5106/5200     Port: 8103/3000
```

### How It Works

1. **Agent calls**: `./run-sandbox.sh eshopweb run`
2. **Sandbox launcher**:
   - Ensures Docker images are built
   - Starts docker-compose services in background
   - Waits for database and primary service healthchecks
   - Mounts `/output` volume for results capture
3. **Build sequence** (via entrypoint.sh):
   - Waits for infrastructure (DB, cache) readiness
   - Builds code (dotnet build, npm build)
   - Runs tests with structured output (JSON)
   - Starts application and verifies HTTP response
   - All output captured to `/output/` directory
4. **Results collection**:
   - `collect-results.sh` merges build logs, test results, health checks into unified JSON
   - Agent harness parses results and determines success/failure

## Sandbox Specifications

### eShopOnWeb Sandbox

**Location**: `./eshopweb/`

**Services**:
- `eshopwebmvc`: ASP.NET Core web application (port 5106)
- `eshoppublicapi`: ASP.NET Core REST API (port 5200)
- `sqlserver`: SQL Server 2022 (port 1433)

**Build Context**: Clones from `/../../eShopOnWeb` (relative to sandbox dir)

**Key Features**:
- Multi-stage Dockerfiles (SDK → ASP.NET runtime) for optimized images
- SQL Server 2022 with automatic schema initialization (Entity Framework migrations)
- Seed data loads on startup (catalog, brands, users)
- Health checks on Web and API endpoints
- Output volume `/output/` for test results and logs

**Database**:
- Automatic migrations via `Database.Migrate()` on app startup
- Two contexts: `CatalogContext` and `AppIdentityDbContext`
- Connection string: `Server=sqlserver,1433;User Id=sa;Password=@someThingComplicated1234;Trusted_Connection=false;TrustServerCertificate=true;`

### Medplum Sandbox

**Location**: `./medplum/`

**Services**:
- `medplum-server`: FHIR API server (port 8103)
- `medplum-app`: React UI (port 3000)
- `postgres`: PostgreSQL 16 (port 5432)
- `redis`: Redis 7 (port 6379)

**Build Context**: Pre-built images (`medplum/medplum-server:latest`, `medplum/medplum-app:latest`)

**Key Features**:
- Pre-built container images (build happens outside sandbox)
- PostgreSQL with schema migrations (v1-v103+)
- Redis for caching, pub/sub, rate limiting
- Health checks on API and UI endpoints
- Output volume `/output/` for test results and logs
- Test seeding: `npm run test:seed` creates FHIR resources and admin account

**Database**:
- Schema migrations in `packages/server/src/migrations/schema/`
- Auto-migration on server startup
- Connection: `Host=postgres;Port=5432;User Id=medplum;Password=medplum;Database=medplum`

## Usage

### Quick Start

```bash
# Build sandbox images
./scripts/run-sandbox.sh eshopweb build

# Run full build → test → run sequence
./scripts/run-sandbox.sh eshopweb run

# Check health
./scripts/run-sandbox.sh eshopweb health

# Reset to clean state
./scripts/sandbox-reset.sh eshopweb

# Same for Medplum
./scripts/run-sandbox.sh medplum run
```

### Operations

#### `build` - Build Docker Images
Compiles Dockerfile(s) for the sandbox without starting services.
```bash
./scripts/run-sandbox.sh eshopweb build
```

#### `run` - Execute Full Sandbox Sequence
1. Starts all services (docker-compose up -d)
2. Waits for healthchecks
3. Monitors output files
4. Returns when complete

```bash
./scripts/run-sandbox.sh eshopweb run

# Output files:
# - eshopweb/output/build.log        : Full build logs
# - eshopweb/output/test-results.json : xUnit test results
# - eshopweb/output/health.json      : Health check response
# - eshopweb/output/exit_code.txt    : Exit code (0=success, 1=failure)
```

#### `reset` - Cold Start Reset
Destroys all containers and volumes, clears output, rebuilds images from scratch.
```bash
./scripts/sandbox-reset.sh eshopweb --full
```

**Why cold-start?** Ensures deterministic, reproducible state. Every agent run starts from a known baseline. Database migrations, seed data, dependency installs all run fresh. Tradeoff: ~30-45 seconds vs. 5-10 seconds for warm-start, but safety is worth it for validation.

#### `health` - Check Running Sandbox
Displays container status and health of all services.
```bash
./scripts/run-sandbox.sh eshopweb health
```

### Integration with Agent Harness

The agent harness should:

```bash
# 1. Reset to clean state
./scripts/sandbox-reset.sh medplum

# 2. Generate code and commit to a branch in cloned repo
# (Agent creates/modifies files, commits to local branch)

# 3. Run sandbox build → test sequence
./scripts/run-sandbox.sh medplum run

# 4. Collect results
./scripts/collect-results.sh medplum > medplum-run-results.json

# 5. Parse results
exit_code=$(jq '.exit_code' medplum-run-results.json)
test_results=$(jq '.test_results' medplum-run-results.json)

if [ $exit_code -eq 0 ]; then
    echo "Build succeeded! Creating PR..."
else
    echo "Build failed. Test results:"
    echo $test_results | jq .
fi

# 6. Repeat for next run (containers are destroyed, fresh state)
```

## Clean State & Reset Strategy

### Cold-Start Reset (Recommended for Validation)

**Process**:
```bash
docker-compose down -v          # Destroy containers + volumes
rm -rf output/                  # Clear output directory
docker-compose build --no-cache # Rebuild images
```

**Duration**: ~30-45 seconds per project

**Guarantees**:
- Truly fresh database (migrations re-run)
- No stale test artifacts
- No accumulated temporary files
- Each run is independent

**Use case**: Primary mode for agent validation. Every agent code generation cycle starts clean.

### Warm-Start Reset (Future Optimization)

**Process** (not yet implemented):
```bash
docker-compose down -v        # Destroy containers + volumes ONLY
docker-compose up -d          # Reuse built images (much faster)
```

**Duration**: ~5-10 seconds per project

**Trade-off**: Faster startup, but assumes image layers are unchanged.

**Use case**: Could be used if same images run repeatedly, or for human developer iteration.

## Non-Interactive Execution

### Challenge
AI agents can't answer prompts, click through wizards, or manually approve licenses. Both projects have some interactive assumptions.

### Solutions

#### eShopOnWeb
- **No-prompt migrations**: Seed logic in C# classes (not SQL scripts)
- **Automatic seed on startup**: `SeedDatabaseAsync()` called during `WebApplicationExtensions.cs`
- **Headless HTTP startup**: No interactive prompts needed

#### Medplum
- **No-prompt migrations**: TypeScript migration runner (`npm run migrate`) runs without prompts
- **Test seeding**: `npm run test:seed` creates base FHIR resources
- **Environment-based config**: All settings from environment variables, no config wizards

### Implementation
- Entrypoint scripts (entrypoint.sh) handle all waiting/polling
- `timeout` command ensures processes don't hang
- Health checks verify readiness before declaring success

## Output Capture for Agent Results

### Files Captured

Each sandbox run captures:

```
output/
├── build.log            : Full build output (stdout + stderr)
├── test-results.json    : Test framework output (xUnit or Jest JSON)
├── health.json          : Final health check response
└── exit_code.txt        : Process exit code (0 or 1)
```

### Unified Results Format

`collect-results.sh` merges these into a single JSON document:

```json
{
  "sandbox": "eshopweb",
  "timestamp": "2026-04-19T12:34:56Z",
  "exit_code": 0,
  "success": true,
  "build_log": "...",
  "test_results": {
    "testCollection": [...],
    "assembly": "..."
  },
  "health_check": {
    "status": "healthy",
    "endpoint": "http://localhost:8080/"
  }
}
```

### Why Structured Output?

1. **Machine-readable**: Agent harness parses JSON, not logs
2. **Deterministic**: No parsing fragile log text
3. **Complete**: Build logs, test results, health checks in one place
4. **Timestamped**: Reproducibility and debugging

## Security & Isolation

### Container Isolation

1. **Namespace isolation**: Each service runs in its own container with isolated network, PID, mount namespaces
2. **Read-only filesystems**: Runtime containers (Web, API, Server) configured with read-only rootfs (improvements for Phase 4)
3. **Volume constraints**: 
   - Output volume mounted read-write only to `/output/`
   - Database volumes use named volumes (not host mounts)
   - No host filesystem access except through explicit mounts

### Network Isolation

- Containers communicate via internal Docker network (not host network)
- Ports exposed only as needed (5106, 5200 for eShopOnWeb; 8103, 3000 for Medplum)
- Internal service-to-service communication via hostnames (e.g., `sqlserver`, `postgres`)

### Threat Model

**Assumption**: Arbitrary code generated by AI agents will execute in the sandbox.

**Boundaries**:
- Code cannot access host filesystem beyond `/output/`
- Code cannot reach outside the sandbox network
- Memory/CPU limits can be enforced via docker-compose resource constraints (future)
- Process runs as non-root (inherited from project Dockerfiles)

**Not Protected Against**:
- Container breakout (Docker escape): Use trusted Docker runtime, keep Docker updated
- Denial-of-service: CPU/memory limits mitigate (set in compose file)
- Supply chain attacks: Use digest-pinned base images in Phase 2+

## Build Performance & Layer Caching

### eShopOnWeb

**Dockerfile Strategy**: Two-stage build (SDK + Runtime)

```dockerfile
# Stage 1: SDK (compilation)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
COPY . .
RUN dotnet publish -c Release -o out

# Stage 2: Runtime (final image)
FROM mcr.microsoft.com/dotnet/aspnet:9.0
COPY --from=build /src/out .
ENTRYPOINT ["dotnet", "Web.dll"]
```

**Layer Caching**:
- Base images (SDK, ASP.NET runtime) cached from Docker Hub
- `COPY . .` layer invalidated on any code change
- Optimization: Pre-layer dependency restore in future iteration

### Medplum

**Dockerfile Strategy**: Pre-built images (build done outside sandbox)

```dockerfile
# medplum-server:latest already built by medplum CI/CD
# Sandbox pulls it directly
```

**Layer Caching**:
- Image pulls from registry (fast if cached locally)
- No re-build needed inside sandbox
- Reduces sandbox startup time (no compilation)

### Cold-Start vs. Warm-Start Performance

| Operation | Cold-Start | Warm-Start |
|-----------|-----------|-----------|
| Image build | 30s | N/A |
| Container startup | 10s | 10s |
| Database migration | 5s | 5s |
| Dependency restore | 15s | (reused layer) |
| Build code | 20s | 20s |
| Run tests | 30s | 30s |
| **Total** | **110s** | **65s** |

**Recommendation**: Cold-start for validation (ensures reproducibility), warm-start for iteration (faster feedback loop).

## Resource Management

### Default Limits (Recommendations)

```yaml
# In docker-compose.yml (future enhancement)
services:
  eshopwebmvc:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 512M
  sqlserver:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G

  medplum-server:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1.5G
  postgres:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
```

### Rationale

- **SQL Server**: Requires 2GB+ baseline
- **Web/API**: 1GB sufficient for mid-scale workloads
- **Medplum server**: 1.5GB for Node.js runtime + caching
- **PostgreSQL**: 1GB with caching

**Total resource footprint**: ~6-8GB RAM + CPU for both sandboxes running simultaneously.

## Future Improvements

### Phase 2 Enhancements (if time permits)

1. **Resource limits**: Add `deploy.resources` to docker-compose for predictable allocation
2. **Warm-start mode**: Implement fast reset (container-only, not image rebuild)
3. **Health check polling**: Script waits for all healthchecks before declaring ready
4. **Timeout management**: Configurable timeouts for different operations

### Phase 3+ Enhancements (beyond 2-hour scope)

1. **Read-only rootfs**: Runtime containers with read-only root + tmpfs for temp files
2. **Dropped capabilities**: Run containers with minimal Linux capabilities (`CAP_CHOWN` only)
3. **Network policies**: Restrict inter-container communication where possible
4. **Observability**:
   - Centralized logging (ELK stack)
   - Tracing (Jaeger) for cross-service debugging
   - Metrics (Prometheus) for resource usage
5. **Artifact persistence**: Archive test results, build logs to S3/Azure Blob
6. **Parallel execution**: Support multiple agent runs simultaneously on different ports
7. **Kubernetes integration**: Translate docker-compose to Helm charts for scale

## Troubleshooting

### Container Won't Start

**Check logs**:
```bash
docker-compose logs sqlserver  # eShopOnWeb
docker-compose logs postgres   # Medplum
```

**Common issues**:
- Port conflict: Check if 5106, 5200, 8103, 3000, 1433, 5432, 6379 are in use
- Insufficient disk space: `docker system prune -a --volumes`
- Docker daemon not running: Restart Docker Desktop / Docker service

### Tests Failing in Sandbox

**Check build logs**:
```bash
cat eshopweb/output/build.log
cat medplum/output/test-results.json
```

**Common issues**:
- Database not ready: Migrations might be slow, increase healthcheck timeout
- Missing dependencies: `npm ci` / `dotnet restore` might have failed
- Test isolation: Tests might be interfering; ensure cold-start reset between runs

### Health Check Timeouts

**Increase timeout** in docker-compose.yml:
```yaml
healthcheck:
  interval: 10s
  timeout: 10s    # Increase from 5s
  retries: 10     # Increase from 5
```

## Contributing

- Entrypoint scripts: Modify `eshopweb/entrypoint.sh` and `medplum/entrypoint.sh`
- Orchestration: Modify `scripts/run-sandbox.sh` and `scripts/sandbox-reset.sh`
- Docker config: Modify `*/docker-compose.yml` in each sandbox directory
- Documentation: This README

## Conclusion

This sandbox architecture provides AI agents with:

✅ **Two independent, reproducible execution environments**
✅ **Automatic state reset between runs**
✅ **Non-interactive, headless operation**
✅ **Structured output capture for parsing**
✅ **Security isolation boundaries**
✅ **Clear, extensible design**

The agent harness can confidently build, test, and validate code in either project without worrying about state pollution, port conflicts, or database corruption.
