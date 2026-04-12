# Repository Guidelines

## Project Structure & Module Organization

`quantroot` is a monorepo centered on a Bitcoin Core fork and supporting docs/demo tooling.

- `repos/bitcoin/`: primary codebase, built from the `quantroot` branch.
- `repos/bips/`: BIP specifications and test vectors; treat this as the canonical BIP knowledge base.
- `services/website/`: Astro-based project website.
- `docs/`: published guides and reference material.
- `dev/`: plans, working notes, and internal resource docs.
- `test/`: demo scripts and end-to-end test assets.
- `scripts/`, `config/`, `build/`, `data/`: launchers, configuration, exported binaries, and runtime data.

## Build, Test, and Development Commands

- `make help`: list supported top-level tasks.
- `make build-bitcoin`: export `bitcoind`, `bitcoin-cli`, and `bitcoin-qt` to `build/bitcoin/bin/`.
- `make start BG=1`: start the demo node stack in Docker.
- `make qt-regtest`: launch `bitcoin-qt` on regtest using `data/demo-qt`.
- `make qt-signet`: launch `bitcoin-qt` on signet with default user settings.
- `make dev-website`: run the Astro site locally.
- `make test-demo`: run the demo end-to-end test.
- `cd repos/bitcoin && build/bin/test_bitcoin --run_test=qis_descriptor_tests`: run targeted wallet/unit coverage.

## Coding Style & Naming Conventions

Follow the style of the area you are editing.

- `repos/bitcoin/`: match upstream Bitcoin Core C++ conventions and existing naming.
- Shell scripts: use `bash`, `set -euo pipefail`, and descriptive target names.
- Markdown: keep sections short, command-focused, and repository-specific.
- Prefer hyphenated filenames for docs (`demo-environment.md`) and lowercase Make targets (`qt-signet`).

## Testing Guidelines

Run the smallest relevant test first, then broader checks if the change crosses boundaries.

- Docs/config changes: `make check`
- Demo flow changes: `make test-demo`
- Bitcoin wallet/descriptor/RPC changes: targeted `test_bitcoin` and relevant functional tests under `repos/bitcoin/test/functional/`
- Website changes: build or run the Astro site before finishing

## Commit & Pull Request Guidelines

Recent history uses short prefixes such as `doc:`, `fix:`, `build:`, `test:`, and `demo:`. Keep commit subjects imperative and specific, for example: `fix: write canonical qr() descriptors to wallet db`.

PRs should include:

- a brief problem/solution summary
- touched areas (`repos/bitcoin`, `services/website`, docs, demo)
- exact verification commands run
- screenshots for website/UI changes
- linked issue or rationale when changing protocol, wallet, or demo behavior

## Security & Configuration Tips

Do not commit runtime data from `data/` or secrets from local configs. For signet/mainnet testing, prefer normal user config in `~/.bitcoin/bitcoin.conf`; for demo regtest, use the repo launchers and isolated `data/demo-*` directories.
