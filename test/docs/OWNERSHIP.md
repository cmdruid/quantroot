# Test Ownership

Placement rules and boundary decisions for tests.

## Placement Rules

| Test type | Location | Owner |
|-----------|---------|-------|
| Unit tests for a package | Inside the package repo | Package maintainer |
| Integration tests for a package | Inside the package repo | Package maintainer |
| Cross-service smoke tests | `test/smoke/` | Infra team |
| Cross-service E2E tests | `test/e2e/` | Infra team |
| Test scripts and runners | `test/scripts/` | Infra team |

## Boundary Decisions

- Tests that validate a single repo's code never belong in top-level `test/`
- Tests that require multiple services running belong in top-level `test/`
- Smoke tests are fast and stateful — use them for health verification
- E2E tests are thorough — use them for behavior validation
