# Conventions

Naming, terminology, formatting, and code style conventions for Quantroot.

## File and Directory Naming

| Location | Convention | Examples |
|----------|-----------|---------|
| Root docs | `SCREAMING_SNAKE_CASE.md` | `README.md`, `CLAUDE.md` |
| `docs/` | `SCREAMING_SNAKE_CASE.md` | `OVERVIEW.md`, `GLOSSARY.md` |
| `dev/docs/` | `SCREAMING_SNAKE_CASE.md` | `CONVENTIONS.md`, `POLICY.md` |
| Lifecycle docs (adr, reports, plans) | `kebab-case-YYYY-MM-DD.md` | `validator-boundary-2026-04-01.md` |
| `services/`, `repos/` | `kebab-case` directories | `validator-ts/`, `core-lib/` |
| Shell scripts | `kebab-case.sh` | `setup-dev.sh`, `test-e2e.sh` |
| Docker files | lowercase | `dockerfile`, `entrypoint.sh` |
| Config files | lowercase with extension | `bitcoin.conf`, `.env.example` |

## Function and Variable Naming

{{Define language-specific naming conventions as the codebase grows.}}

## Domain Terminology

See [docs/GLOSSARY.md](../../docs/GLOSSARY.md) for shared terms.

## Shell Style

- Shebang: `#!/usr/bin/env bash`
- Default to `set -euo pipefail`
- Quote all variable expansions
- Derive repo paths from script location, not `$PWD`
- Prefer small helper functions over long flat scripts

## Formatting

- Indentation: 2 spaces for YAML, shell, and markdown. 4 spaces for Python.
- Imports: stdlib first, then third-party, then local
- Comments: explain why, not what
- Error messages: lowercase, no trailing punctuation

## Docker Naming

- Service directory names match Compose service names
- Container names: `quantroot-<service>`
- Image tags: `quantroot/<service>:latest`
