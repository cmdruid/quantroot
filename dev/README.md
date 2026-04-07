# Developer Knowledge Base

Developer-only reference for conventions, infrastructure structure, release
operations, active plans, generated reports, and architecture decisions.

## Start Here

- [CONVENTIONS.md](docs/CONVENTIONS.md) — naming, terminology, formatting, code style
- [POLICY.md](docs/POLICY.md) — workflow, boundary, documentation, test-selection rules
- [WORKFLOWS.md](docs/WORKFLOWS.md) — bootstrap, debugging, validation, release handoff
- [STRUCTURE.md](docs/STRUCTURE.md) — stack structure, service topology, ownership
- [RELEASE.md](docs/RELEASE.md) — package update and release workflow

## Directory Map

| Directory | Purpose |
|-----------|---------|
| `docs/` | Developer reference documents |
| `adr/` | Architecture decision records |
| `audit/` | Audit instructions and milestone artifacts |
| `reports/` | Generated investigation reports |
| `plans/` | Active implementation plans |
| `archive/` | Completed or superseded documents |
| `scripts/` | Developer-only workflow helpers |

## Common Tasks

| I am... | Start here |
|---------|-----------|
| Changing code | [CONVENTIONS.md](docs/CONVENTIONS.md), then [STRUCTURE.md](docs/STRUCTURE.md) |
| Debugging | [WORKFLOWS.md](docs/WORKFLOWS.md) |
| Preparing a release | [RELEASE.md](docs/RELEASE.md) |
| Making an architecture decision | [adr/README.md](adr/README.md) |
| Investigating an issue | [reports/README.md](reports/README.md) |
| Planning implementation work | [plans/README.md](plans/README.md) |

## Document Lifecycle (Engineering Pipeline)

1. **Reports** — generate or collect investigation reports in `reports/`
2. **Plans and ADRs** — use reports to produce plans in `plans/` and decisions
   in `adr/`
3. **Execute** — do the work
4. **Archive** — move completed items to `archive/`
5. **Audit** — run or update audit material in `audit/` at milestones
