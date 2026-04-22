# Implementation Summary

## Objective

Build a Docker-based sandbox system that allows an AI coding agent to safely build, run, reset, and validate changes against two real-world open-source applications with very different stacks:

- `eShopOnWeb`
- `Medplum`

The solution needed to be practical, reproducible, and suitable for non-interactive execution.

## What Was Implemented

I implemented a sandbox framework with:

- separate Docker Compose environments for each project
- helper scripts for `build`, `run`, `reset`, and `health`
- project-specific runtime configuration where required
- output capture through mounted `output` directories
- clean-state reset behavior for repeatable execution

## Architecture Decision

### Decision

Use two isolated sandboxes instead of a single shared environment.

### Why

The two applications have materially different requirements:

`eShopOnWeb`

- ASP.NET Core application stack
- SQL Server dependency
- .NET build and startup flow

`Medplum`

- Node.js application stack
- PostgreSQL and Redis dependencies
- configuration-file-driven startup

Trying to force both systems into one shared sandbox would create unnecessary complexity around:

- dependency isolation
- service startup ordering
- data store management
- debugging
- failure containment

### Result

Each sandbox is simpler to understand, easier to reset, and easier to validate independently.

## Core Components

### `scripts/run-sandbox.sh`

Provides a consistent interface for both projects:

- `build`
- `run`
- `reset`
- `health`

This gives a reviewer or automation harness one predictable entry point regardless of project.

### `scripts/sandbox-reset.sh`

Provides a cold-start reset flow:

- stop containers
- remove volumes
- clear sandbox output
- rebuild images

This favors deterministic validation over the fastest possible restart time.

### `scripts/collect-results.sh`

Collects sandbox output artifacts and returns a single JSON payload that includes:

- exit code
- build log
- test results
- health output

That makes the sandbox easier to integrate with an AI-agent workflow or external runner.

## eShopOnWeb Work

### Problem

`eShopOnWeb` initially had runtime and startup issues in the sandboxed environment.

Observed issues included:

- application startup failure caused by missing Seq configuration
- SQL Server readiness and health sensitivity
- API health verification targeting a path that was not appropriate for the running container

### Fixes Implemented

- added `Seq__ServerUrl=http://localhost:5341` to the relevant container environment
- updated SQL Server healthchecking to use `sqlcmd` with `-C`
- increased SQL Server health retries
- aligned API health verification to `swagger/index.html`

### Outcome

Validated in the VM:

- Web returned `200`
- API returned `200`
- SQL Server became healthy

There is still room to improve health reporting consistency, but the application endpoints were confirmed working.

## Medplum Work

### Problem

`Medplum` initially failed because the server expected `medplum.config.json` at runtime and could not find it in the container.

### Root Cause

The server image starts using a default configuration path. Without mounting the config into the expected location, the service repeatedly restarted with `ENOENT`.

### Fixes Implemented

- created a sandbox-local `medplum.config.json`
- updated database host to `postgres`
- updated Redis host to `redis`
- mounted the config file into `/usr/src/medplum/medplum.config.json`

### Outcome

Validated in the VM:

- server health endpoint returned `200`
- app returned `200`
- PostgreSQL became healthy
- Redis became healthy

This was the most important Medplum-specific fix because it turned a crash-looping container into a working sandbox service.

## Validation Approach

Validation was performed in a Linux VM to confirm that the sandbox behaved correctly outside the local authoring environment.

The validation flow was:

1. reset sandbox
2. run sandbox
3. inspect container status
4. verify service endpoints
5. confirm supporting services were healthy

### Verified Results

`eShopOnWeb`

- Web: `200`
- API: `200`
- DB: healthy

`Medplum`

- Server: `200`
- App: `200`
- PostgreSQL: healthy
- Redis: healthy

## Tradeoffs

### Isolation over consolidation

Pros:

- cleaner architecture
- easier debugging
- lower coupling between projects
- simpler reasoning for reviewers and automation

Cons:

- duplicated configuration in some places
- separate health logic for each project
- slightly more setup overhead

This was the right tradeoff for reliability and clarity.

### Deterministic reset over fastest startup

Pros:

- more repeatable validation
- less hidden state between runs
- better fit for AI-agent workflows

Cons:

- slower than reusing warm containers

For an interview deliverable focused on correctness and reproducibility, this tradeoff is worth it.

## What I Would Improve Next

If given more time, I would:

- refine `eShopOnWeb` container health reporting so Docker status more closely matches verified service behavior
- reduce duplication across helper scripts
- add lightweight automated validation in CI
- standardize output artifacts further across both sandboxes

## Final Outcome

The final solution provides:

- isolated execution environments for both target projects
- repeatable reset and run workflows
- working VM-validated runtime behavior for both sandboxes
- a practical foundation for AI-agent-driven code validation

## Files Most Relevant To The Submission

- `README.md`
- `QUICKSTART.md`
- `IMPLEMENTATION.md`
- `scripts/run-sandbox.sh`
- `scripts/sandbox-reset.sh`
- `scripts/collect-results.sh`
- `eshopweb/docker-compose.yml`
- `medplum/docker-compose.yml`
- `medplum/medplum.config.json`
