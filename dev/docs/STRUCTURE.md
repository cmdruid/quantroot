# Structure

Stack structure, service topology, and ownership for Quantroot.

## Top-Level Layout

```
quantroot/
  repos/          Git submodules (shared libraries, service source)
  services/       Docker service wrappers
  docs/           Domain and protocol knowledge base
  dev/            Developer knowledge base and engineering pipeline
  test/           Test infrastructure
  scripts/        Runtime and operator helpers (mounted into containers)
  config/         Shared runtime configuration
  bin/            Pre-built binaries (gitignored)
  data/           Persistent runtime state (gitignored)
  logs/           Logs and session artifacts (gitignored)
```

## Service Topology

{{Document services, their dependencies, and communication patterns here.}}

## Dependency Graph

{{Document which services depend on which, startup order, etc.}}

## Runtime Modes

| Mode | Command | Description |
|------|---------|-------------|
| Standard | `make start` | Core services from built images |
| Development | `make dev` | Local repo mounts via `compose.override.yml` |
| Background | `BG=1 make start` | Detached mode |

## Config and Data Model

- Environment: `.env` (from `.env.example` template)
- Service configs: `config/<service-config>`
- Network configs: `config/bootstrap/<network>/`
- Runtime data: `data/` (created at runtime, cleaned by `make reset`)

## Script Mount Contract

| Directory | Mounted at | Scope |
|-----------|-----------|-------|
| `scripts/` | `/dscript` | Runtime helpers, all services |
| `test/scripts/` | `/dtestscript` | Test runners only |
| `dev/scripts/` | Not mounted | Developer-only |
