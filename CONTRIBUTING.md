# Contributing to Quantroot

## Start Here

```bash
git clone <repo-url> && cd quantroot
make init
cp .env.example .env
# Edit .env with your values
make start
```

## Knowledge Base Handoffs

- [README.md](README.md) — project overview and quick start
- [dev/README.md](dev/README.md) — conventions, structure, workflows
- [test/README.md](test/README.md) — testing, debugging, validation
- [docs/INDEX.md](docs/INDEX.md) — domain and protocol knowledge

## Branching

Default branch: `main`

Feature branch naming:

- `feat/<description>` — new functionality
- `fix/<description>` — bug fixes
- `docs/<description>` — documentation only
- `refactor/<description>` — code restructuring

## Common Commands

| Command | Description |
|---------|-------------|
| `make start` | Start core services |
| `make stop` | Stop all services |
| `make health` | Check service health |
| `make test-demo` | Run demo E2E test (22 checks) |
| `make check` | Run static checks and doc consistency |

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

- **Shell style**: `set -euo pipefail`, quoted expansions, `kebab-case` filenames
- **Docker naming**: service dirs match Compose service names, containers
  prefixed with `quantroot-`
- **Environment**: all runtime config via `.env`, never hardcoded
- **Commit messages**: Conventional Commits — `feat:`, `fix:`, `docs:`, `chore:`

## Pull Requests

Every PR should include:

- Summary of changes
- Updated submodule hashes (if applicable)
- Test evidence (which gates passed)
