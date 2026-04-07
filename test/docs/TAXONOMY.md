# Test Taxonomy

Definitions for test types used in Quantroot.

## Unit

- Scope: single function or module, no external dependencies
- Location: inside the owning repo
- Speed: milliseconds
- Mocking: allowed for isolation

## Integration

- Scope: interaction between two internal components
- Location: inside the owning repo or `test/` if cross-repo
- Speed: seconds
- Mocking: external services only

## Smoke

- Scope: service is up and responds correctly to basic requests
- Location: `test/smoke/`
- Speed: seconds (stateful but fast)
- Mocking: none — hits real services

## E2E (End-to-End)

- Scope: full cross-service workflows and user-facing scenarios
- Location: `test/e2e/`
- Speed: minutes
- Mocking: none — full stack required
