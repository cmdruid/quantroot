# Test Workflows

Command selection and common testing, reproduction, and debugging flows.

## Which Command Do I Run?

| Situation | Command |
|-----------|---------|
| Quick sanity check | `make test-smoke` |
| Pre-merge validation | `make test-e2e` |
| Reproduce a single scenario | `./test/scripts/e2e.sh <scenario>` |
| Verify workspace integrity | `make test-check` |

## Running E2E Tests

```bash
# Full suite
make test-e2e

# Single scenario
./test/scripts/e2e.sh <scenario-name>

# Wait for stack readiness first
./test/scripts/wait-e2e-ready.sh && make test-e2e
```

## Running Smoke Tests

```bash
make test-smoke
```

## Debugging a Failure

See [DEBUGGING.md](DEBUGGING.md) for detailed triage steps.

Quick checklist:

1. Check service health: `make health`
2. Check logs: `make logs-<service>`
3. Verify workspace: `make test-check`
4. Reproduce in isolation: `./test/scripts/e2e.sh <scenario>`
