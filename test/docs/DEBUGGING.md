# Debugging

Stack triage, health checks, common failure modes, artifacts, and recovery.

## Triage Checklist

1. **Check health**: `make health` — are all containers running?
2. **Check logs**: `make logs-<service>` — any errors on startup?
3. **Check env**: is `.env` populated and correct?
4. **Check workspace**: `make test-check` — are test files in order?
5. **Check disk**: is `data/` filling up? Try `make reset`.

## Common Failure Modes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Container won't start | Missing `.env` | `cp .env.example .env` |
| Port conflict | Another service on the port | Stop the conflicting service |
| Test timeout | Service not ready | Run `./test/scripts/wait-e2e-ready.sh` |
| Stale data | Corrupt runtime state | `make reset` |

## Artifacts

- Test logs: `logs/sessions/` (timestamped per run)
- Container logs: `make logs` or `docker compose logs`
- Runtime data: `data/` (inspect for corruption)

## Recovery Paths

- **Soft reset**: `make stop && make start`
- **Hard reset**: `make reset && make init && make start`
- **Full rebuild**: `make reset && make build && make start`
