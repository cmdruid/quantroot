# Workflows

Common bootstrap, debugging, validation, and release flows for Quantroot.

## First-Time Bootstrap

```bash
git clone <repo-url> && cd quantroot
make init
cp .env.example .env
# Edit .env with your values
make start
make health
```

## Manual Deployment / Network Bootstrap

{{Document manual deployment or network bootstrap procedures here as needed.}}

## Starting the Stack

```bash
# Core services in foreground
make start

# Core services in background
BG=1 make start

# All services (including optional)
ALL=1 BG=1 make start

# Development mode (with local repo mounts)
make dev
```

## Inspecting Health

```bash
make health          # Container status
make logs            # All logs
make logs-<service>  # Specific service
```

## Choosing Validation Depth

| Speed | Command | Use when |
|-------|---------|----------|
| Fast | `make check` | Quick static check |
| Full | `make test-demo` | Pre-merge validation (requires Docker) |

## Refreshing Dependencies

```bash
make update    # Refresh service dependencies
make build     # Rebuild images after changes
```

## Release Handoff

See [RELEASE.md](RELEASE.md) for the full release workflow.
