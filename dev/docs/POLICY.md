# Policy

Workflow, boundary, documentation, and test-selection rules for Quantroot.

## Primary Interfaces

All common operations go through `make` targets. Raw `docker compose` commands
are implementation details.

## Documentation Ownership

| Area | Owner | Entrypoint |
|------|-------|-----------|
| Domain and protocol | `docs/` | `docs/INDEX.md` |
| Developer workflow | `dev/` | `dev/README.md` |
| Testing and debugging | `test/` | `test/README.md` |
| Project routing | root | `README.md` |

## Boundary Rules

- Do not duplicate content across knowledge bases
- Root docs hand off to deeper KBs; they do not restate
- Cross-KB handoffs are allowed when they clarify a real boundary
- Submodule docs stay self-contained by default
- Prefer relative links inside the same knowledge base

## Test Selection Policy

| Gate | When to use | What it proves |
|------|------------|---------------|
| `make check` | Every change | Static correctness, doc consistency |
| `make test-smoke` | During development | Services start and respond |
| `make test-e2e` | Before merge | Full cross-service behavior |

## Planning and Decision Policy

- Use `dev/reports/` to capture investigation findings
- Promote findings to `dev/plans/` or `dev/adr/` before implementation
- Archive completed or superseded documents promptly

## Release Policy

See [RELEASE.md](RELEASE.md) for the full release workflow.
