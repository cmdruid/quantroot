# E2E Test Package

Layout and ownership for the Quantroot E2E test suite.

## Structure

```
test/e2e/
  conftest.py         Shared fixtures, stack context, configuration
  pytest.ini          pytest configuration
  requirements.txt    Test dependencies
  cases/              Test modules organized by suite
  helpers/            Utilities, actions, clients
  fixtures/           Test data setup and bootstrapping
```

## Ownership

The E2E package is owned by the infra team. Tests here validate cross-service
behavior against the full running stack.

## Boundary Rules

- E2E tests must not mock internal service boundaries
- E2E tests require the full stack running (`make start`)
- Test data setup belongs in `fixtures/`, not inline in test cases
- Shared utilities belong in `helpers/`, not duplicated across cases
