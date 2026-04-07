# Developer Scripts

Developer-only workflow helpers. Not mounted into containers.

## Scripts

- `setup-dev.sh` — generate `compose.override.yml` for local repo mounts
- `update.sh` — refresh service dependencies across the monorepo

Runtime and operator entrypoints: root `scripts/`.
Test-owned entrypoints: `test/scripts/`.

Prefer invoking through the root `Makefile` when a target exists.
