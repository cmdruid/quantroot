# Test Scripts

Script routing table for Quantroot test infrastructure.

## Make Target → Script Mapping

| Make target | Script | Purpose |
|-------------|--------|---------|
| `make test-e2e` | `test/scripts/test-e2e.sh` | Full E2E suite runner |
| `make test-smoke` | `test/scripts/test-smoke.sh` | Smoke test runner |
| `make test-check` | `test/scripts/check-e2e-workspace.sh` | Workspace verification |
| *(direct)* | `test/scripts/e2e.sh` | Single scenario reproduction |
| *(direct)* | `test/scripts/wait-e2e-ready.sh` | Stack readiness check |

## Shared Library

`test/scripts/lib/common.sh` — colors, paths, Docker helpers shared across
test scripts.
