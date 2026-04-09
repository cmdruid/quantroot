# Quantroot — Agent Operating Contract

Quantroot is a Docker Compose monorepo for developing a simple post-quantum
soft-fork upgrade path for Bitcoin Taproot. All services
run as containers orchestrated by `compose.yml`. Container names are prefixed
with `quantroot-`. Networking is internal via Docker Compose networks.

## Canonical Commands

| Command | Description |
|---------|-------------|
| `make help` | Print all available commands |
| `make init` | Initialize submodules and build containers |
| `make start` | Start core services |
| `make stop` | Stop all services |
| `make restart` | Restart all services |
| `make reset` | Stop and remove all runtime data |
| `make health` | Check service health |
| `make build` | Rebuild container images |
| `make test-demo` | Demo E2E test (22 checks, 6 phases) |
| `make check` | Static checks and doc consistency |
| `make logs` | Follow all service logs |
| `make logs-<svc>` | Follow a specific service's logs |

## Testing Expectations

- **Primary gate**: `make test-demo` — must pass before merge
- **Static gate**: `make check` — doc consistency and lint

## Documentation and Workflow Rules

| Task | Start here |
|------|-----------|
| Understanding the domain | [docs/INDEX.md](docs/INDEX.md) |
| Changing code or services | [dev/docs/CONVENTIONS.md](dev/docs/CONVENTIONS.md) |
| Debugging a failure | [test/docs/DEBUGGING.md](test/docs/DEBUGGING.md) |
| Adding a test | [test/docs/OWNERSHIP.md](test/docs/OWNERSHIP.md) |
| Preparing a release | [dev/docs/RELEASE.md](dev/docs/RELEASE.md) |
| Making an architecture decision | [dev/adr/README.md](dev/adr/README.md) |

## Key Gotchas

- `.env` is required — copy `.env.example` before running anything
- Use `docker compose` (v2), never `docker-compose` (v1)
- Never commit secrets — `.env` and `config/*/.env` are gitignored
- Commit inside submodules first, then commit the pointer in the parent
- Runtime data lives in `data/` — use `make reset` to clean up

## Agent-Specific Notes

### Claude Code

- Prefer `make` targets over raw `docker compose` commands
- Use `make health` to verify stack state before and after changes
- When creating new files, follow the naming conventions in
  [dev/docs/CONVENTIONS.md](dev/docs/CONVENTIONS.md)
