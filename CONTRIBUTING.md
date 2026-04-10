# Contributing to Quantroot

## Start Here

```bash
git clone --recurse-submodules https://github.com/cmdruid/quantroot.git
cd quantroot
cp .env.example .env
make build-bitcoin    # Build binaries (~10 min first time)
make start BG=1       # Start regtest node
make test-demo        # Verify everything works (22 checks)
```

For a full walkthrough, see [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md).

## Navigation

| I want to... | Go to |
|--------------|-------|
| Understand the project | [README.md](README.md) |
| Get started quickly | [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) |
| Understand the architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Learn the domain (BIPs) | [docs/INDEX.md](docs/INDEX.md) |
| Run a demo | [test/DEMO.md](test/DEMO.md) |
| Run tests | [test/README.md](test/README.md) |
| Read implementation plans | [dev/README.md](dev/README.md) |

## Common Commands

| Command | Description |
|---------|-------------|
| `make build-bitcoin` | Build Bitcoin Core binaries (including bitcoin-qt) |
| `make start` | Start regtest container (`BG=1` for background) |
| `make stop` | Stop all services |
| `make health` | Check service health |
| `make test-demo` | Run demo E2E test (22 checks, 6 phases) |
| `make qt-regtest` | Launch bitcoin-qt (regtest, peers with container) |
| `make qt-signet` | Launch bitcoin-qt (signet, public peers) |
| `make reset-demo` | Delete all demo data |
| `make check` | Static checks and doc consistency |
| `make shell-bitcoin` | Open shell in bitcoind container |

## Working With Submodules

1. `cd repos/<submodule>` and make your changes
2. Commit inside the submodule first
3. Return to the root and commit the updated submodule pointer
4. Both commits should appear in the same PR

## Development Workflow

1. Start the stack: `make start BG=1`
2. Make your changes
3. Run the demo gate: `make test-demo`
4. Verify docs: `make check`

## Conventions

### File naming

| Type | Convention | Example |
|------|-----------|---------|
| Documentation | `UPPER-CASE.md` | `GETTING_STARTED.md` |
| Shell scripts | `kebab-case.sh` | `test-demo.sh` |
| Services | `kebab-case` dirs | `services/bitcoin/` |
| Config files | lowercase with extension | `regtest.conf`, `.env.example` |

### Code style

- **Shell**: `set -euo pipefail`, quoted expansions
- **Docker**: service dirs match Compose names, containers prefixed `quantroot-`
- **Environment**: all runtime config via `.env`, never hardcoded
- **Commits**: Conventional Commits — `feat:`, `fix:`, `docs:`, `chore:`

### Documentation ownership

| Area | Location | Entrypoint |
|------|----------|-----------|
| Domain and protocol | `docs/` | `docs/INDEX.md` |
| Implementation plans | `dev/plans/` | `dev/README.md` |
| Audit reports | `dev/reports/` | `dev/README.md` |
| Testing | `test/` | `test/README.md` |
| Project routing | root | `README.md` |

## Branching

Default branch: `master`

- `feat/<description>` — new functionality
- `fix/<description>` — bug fixes
- `docs/<description>` — documentation only
- `refactor/<description>` — code restructuring

## Pull Requests

Every PR should include:

- Summary of changes
- Updated submodule hashes (if applicable)
- Test evidence (`make test-demo` passed)
