# Developer Sandbox Configuration

## Directory Structure

```
developer-sandbox/
├── README.md                          # Architecture & usage guide
├── .gitignore                         # Exclude build artifacts, volumes
├── eshopweb/
│   ├── docker-compose.yml             # Service orchestration
│   └── entrypoint.sh                  # Non-interactive execution script
├── medplum/
│   ├── docker-compose.yml             # Service orchestration
│   └── entrypoint.sh                  # Non-interactive execution script
└── scripts/
    ├── run-sandbox.sh                 # Unified launcher (build, run, reset, health)
    ├── sandbox-reset.sh               # Cold-start reset
    └── collect-results.sh             # Output collection & merging
```

## Quick Reference

### First Time Setup

```bash
# Clone repos (if not already done)
git clone https://github.com/NimblePros/eShopOnWeb.git
git clone https://github.com/medplum/medplum.git

# Navigate to sandbox
cd developer-sandbox

# Build eShopOnWeb sandbox
./scripts/run-sandbox.sh eshopweb build

# Build Medplum sandbox  
./scripts/run-sandbox.sh medplum build
```

### Agent Harness Integration

```bash
#!/bin/bash

# Agent generates code, makes changes...
# Then validates via sandbox:

for project in eshopweb medplum; do
    # Reset to clean state
    ./scripts/sandbox-reset.sh $project
    
    # Run full sequence
    ./scripts/run-sandbox.sh $project run
    
    # Collect results
    ./scripts/collect-results.sh $project > results-$project.json
    
    # Check success
    if [ $(jq '.exit_code' results-$project.json) -eq 0 ]; then
        echo "$project: PASS"
    else
        echo "$project: FAIL"
        jq '.test_results' results-$project.json
    fi
done
```

### Port Reference

| Service | Port | Sandbox |
|---------|------|---------|
| eShopOnWeb (Web) | 5106 | eshopweb |
| eShopOnWeb (API) | 5200 | eshopweb |
| SQL Server | 1433 | eshopweb |
| Medplum Server | 8103 | medplum |
| Medplum App | 3000 | medplum |
| PostgreSQL | 5432 | medplum |
| Redis | 6379 | medplum |

### Output Files

Each `run` operation creates:

```
eshopweb/output/
├── build.log           # Build process output
├── test-results.json   # xUnit test results
├── health.json         # HTTP healthcheck response
└── exit_code.txt       # 0 (success) or 1 (failure)

medplum/output/
├── build.log           # Build process output
├── test-results.json   # Jest test results
├── health.json         # API healthcheck response
└── exit_code.txt       # 0 (success) or 1 (failure)
```

## Architecture Decisions at a Glance

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Structure** | Two isolated sandboxes | Different DBs, runtimes, dependencies; failure isolation |
| **Databases** | SQL Server + PostgreSQL separate | No consolidation; incompatible protocols |
| **State Reset** | Cold-start (full rebuild) | Deterministic, reproducible; ~30-45s overhead worth it |
| **Execution** | Non-interactive scripts | AI agents can't click dialogs |
| **Output** | Structured JSON | Machine-readable for agent harness |
| **Images** | Reuse existing Dockerfiles | Less maintenance; upstream changes flow through |
| **Scaling** | Sandboxes on single Docker host | Sufficient for agent validation; K8s not needed yet |

## Common Operations

### Debug a Sandbox Run

```bash
# Stop and inspect containers
docker-compose -f eshopweb/docker-compose.yml ps
docker-compose -f eshopweb/docker-compose.yml logs --tail=50

# Connect to container shell
docker-compose -f eshopweb/docker-compose.yml exec eshopwebmvc bash

# Query database
docker-compose -f eshopweb/docker-compose.yml exec sqlserver \
  sqlcmd -S localhost -U sa -P '@someThingComplicated1234' \
  -Q "SELECT * FROM sys.databases"
```

### Monitor Resources

```bash
# Docker stats (live resource usage)
docker stats

# See image sizes
docker images | grep -E "eshopweb|medplum|mssql|postgres|redis"
```

### Manual Cleanup

```bash
# Stop all containers
docker-compose -f eshopweb/docker-compose.yml down
docker-compose -f medplum/docker-compose.yml down

# Remove all volumes
docker volume prune -f

# Full reset (removes images, containers, volumes)
docker system prune -a --volumes -f
```

## Performance Notes

- **First build**: ~2 minutes (download base images, compile)
- **Subsequent runs**: ~1-2 minutes (reuse cached layers)
- **Cold-start reset**: ~45 seconds
- **Database migration**: ~5 seconds
- **Tests**: ~30 seconds (eShopOnWeb), ~60 seconds (Medplum)

## Next Steps

1. Ensure both project repos are cloned to parent directory
2. Install Docker Desktop or Docker Engine
3. Run `./scripts/run-sandbox.sh eshopweb build` to verify setup
4. Integrate with agent harness via `run-sandbox.sh` interface
