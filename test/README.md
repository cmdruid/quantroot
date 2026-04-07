# Test Infrastructure

Top-level home for test infrastructure that crosses real service or repository
boundaries.

## Scope

Tests here validate behavior across multiple services or repos. If a test only
validates one repo's own code, keep it in that repo.

## Common Tasks

| I want to... | Start here |
|--------------|-----------|
| Run the fast gate | `make test-smoke` |
| Run full E2E | `make test-e2e` |
| Debug a failing test | [docs/DEBUGGING.md](docs/DEBUGGING.md) |
| Add a new test | [docs/OWNERSHIP.md](docs/OWNERSHIP.md) |
| Understand test types | [docs/TAXONOMY.md](docs/TAXONOMY.md) |

## Workspace Map

- [docs/TAXONOMY.md](docs/TAXONOMY.md) — test type definitions and boundaries
- [docs/POLICY.md](docs/POLICY.md) — gate definitions and signal strength
- [docs/OWNERSHIP.md](docs/OWNERSHIP.md) — test placement rules
- [docs/WORKFLOWS.md](docs/WORKFLOWS.md) — testing and debugging flows
- [docs/DEBUGGING.md](docs/DEBUGGING.md) — triage, health checks, recovery
- [docs/e2e/README.md](docs/e2e/README.md) — E2E package layout
- [docs/e2e/RUNBOOK.md](docs/e2e/RUNBOOK.md) — E2E execution guide
- [docs/scripts/README.md](docs/scripts/README.md) — script routing table

## Command Ladder

Ordered from fastest to most thorough:

1. `make check` — static checks, doc consistency
2. `make test-smoke` — stateful but fast service checks
3. `make test-e2e` — full cross-service validation

## Placement Rules

1. Test validates one repo only → keep it in that repo
2. Test crosses service or repo boundaries → place it here
3. Test is stateful and fast → classify as `smoke`, not `e2e`
