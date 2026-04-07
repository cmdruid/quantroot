# E2E Runbook

Operator guide for running the Quantroot E2E test suite.

## Prerequisites

- Stack running: `make start`
- All services healthy: `make health`
- Test dependencies installed: `pip install -r test/e2e/requirements.txt`

## Suite Selection

```bash
# Run all E2E tests
make test-e2e

# Run a specific test module
cd test/e2e && python -m pytest cases/test_<suite>.py -v

# Run a specific test
cd test/e2e && python -m pytest cases/test_<suite>.py::test_<name> -v
```

## Required Services

{{List which services must be running for each test suite.}}

## Execution Flow

1. Stack readiness check (`wait-e2e-ready.sh`)
2. Fixture setup (conftest.py session fixtures)
3. Test execution (pytest)
4. Artifact collection (logs to `logs/sessions/`)
5. Teardown (fixture cleanup)
