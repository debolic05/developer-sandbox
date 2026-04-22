# Developer Sandbox

A Docker-based sandbox environment for validating AI-agent-generated changes against two real-world open-source applications with different technology stacks:

- `eShopOnWeb` - ASP.NET Core, SQL Server
- `Medplum` - Node.js, PostgreSQL, Redis

The goal of this project is to provide isolated, repeatable, non-interactive execution environments that an AI coding agent can use to build, run, reset, and health-check changes safely.

## Overview

This solution uses two isolated sandboxes rather than one shared environment.

Why that decision:

- the applications use different runtimes and toolchains
- the applications require different databases
- startup and health behavior are different for each stack
- failures in one sandbox should not affect the other
- each sandbox can be reset independently to a clean state

That keeps the execution model simple for both a reviewer and an automation harness.

## Supported Sandboxes

### `eshopweb`

Services:

- `eshopwebmvc`
- `eshoppublicapi`
- `sqlserver`

Published ports:

- Web: `5106`
- API: `5200`
- SQL Server: `1433`

Highlights:

- SQL Server container healthcheck uses `sqlcmd` with certificate trust enabled
- ASP.NET services are configured for Docker execution
- Seq configuration is supplied so the web processes can start successfully
- Web and API containers expose HTTP healthchecks

### `medplum`

Services:

- `medplum-server`
- `medplum-app`
- `postgres`
- `redis`

Published ports:

- Server: `8103`
- App: `3000`
- PostgreSQL: `5432`
- Redis: `6379`

Highlights:

- explicit `medplum.config.json` is mounted into the container
- database and Redis hosts are aligned to Docker service names
- server health is verified through `/healthcheck`
- app startup is gated on server health

## Repository Structure

```text
developer-sandbox/
├── README.md
├── QUICKSTART.md
├── IMPLEMENTATION.md
├── VALIDATION.md
├── quickstart.sh
├── quickstart-run.sh
├── setup-vm.sh
├── setup-and-run.sh
├── scripts/
├── eshopweb/
└── medplum/
```

## Key Scripts

- `scripts/run-sandbox.sh`
  Unified entry point for `build`, `run`, `reset`, and `health`
- `scripts/sandbox-reset.sh`
  Cold-start reset for a sandbox
- `scripts/collect-results.sh`
  Aggregates sandbox output files into one JSON payload

## Prerequisites

- Docker Engine or Docker Desktop
- Bash-compatible shell
- sibling project checkouts available to the sandbox

Expected sibling repositories:

- `../eShopOnWeb`
- `../medplum`

## Usage

### Build

```bash
./scripts/run-sandbox.sh eshopweb build
./scripts/run-sandbox.sh medplum build
```

### Run

```bash
./scripts/run-sandbox.sh eshopweb run
./scripts/run-sandbox.sh medplum run
```

### Health

```bash
./scripts/run-sandbox.sh eshopweb health
./scripts/run-sandbox.sh medplum health
```

### Reset

```bash
./scripts/run-sandbox.sh eshopweb reset
./scripts/run-sandbox.sh medplum reset
```

## Validation Summary

Validation was completed in a Linux VM environment.

### `eShopOnWeb`

Validated outcomes:

- Web endpoint returned `200`
- API endpoint returned `200`
- SQL Server reached healthy state
- startup issues related to missing Seq configuration were resolved

### `Medplum`

Validated outcomes:

- Server health endpoint returned `200`
- App returned `200`
- PostgreSQL reached healthy state
- Redis reached healthy state
- runtime failure caused by missing `medplum.config.json` was resolved

## Important Implementation Notes

### `eShopOnWeb`

The sandbox was adjusted to accommodate the validated runtime setup:

- service healthchecks were tuned
- SQL Server readiness checking was corrected
- required runtime configuration for Seq was added
- API health validation was aligned to an endpoint that actually exists

### `Medplum`

The main issue encountered was configuration discovery inside the container.

The fix was:

- create and maintain a sandbox-local `medplum.config.json`
- mount it into the path expected by the runtime
- point database and Redis configuration to Docker service names

## Known Limitations

- `eShopOnWeb` service functionality was validated through working endpoints, but Docker health reporting may still need refinement depending on startup timing and the upstream application behavior
- the sandbox depends on upstream repositories being present as sibling directories
- upstream project changes may require future adjustments to compose configuration or runtime settings

## Documentation

- `QUICKSTART.md` - command-oriented quick guide
- `IMPLEMENTATION.md` - design decisions, fixes, and tradeoffs
- `VALIDATION.md` - validation notes and proof steps

## Submission Notes

This repository contains the sandbox implementation and supporting automation only.

The upstream applications are intentionally not included in full here. They were validated separately and are expected to exist locally as sibling repositories when running the sandbox.
