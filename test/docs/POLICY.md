# Test Policy

Gate definitions and signal strength for Quantroot test infrastructure.

## Gates

| Gate | Command | What it proves | What it does NOT prove |
|------|---------|---------------|----------------------|
| Static | `make check` | Docs consistent, config valid | Runtime behavior |
| Smoke | `make test-smoke` | Services start and respond | Cross-service workflows |
| E2E | `make test-e2e` | Full stack behavior | Performance, edge cases |

## Signal Strength

- A passing smoke gate means services are healthy, not correct
- A passing E2E gate means the tested scenarios work, not all scenarios
- Combine gates for confidence: `make check && make test-e2e`

## Mock Semantics

- Smoke and E2E tests hit real services — no mocks
- Unit and integration tests in repos may mock external dependencies
- Never mock internal service boundaries in E2E tests
