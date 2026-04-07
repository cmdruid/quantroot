# Quantroot

> Post-quantum security for Bitcoin Taproot — a soft-fork upgrade path using SPHINCS+ signatures.

Quantroot is a Docker Compose monorepo for developing and testing two companion
consensus drafts that together provide comprehensive post-quantum defense for
Taproot. The canonical specification knowledge base lives in `repos/bips`:

- **[OP_CHECKSPHINCSVERIFY draft](repos/bips/bip-0369.mediawiki)** — Redefines `OP_NOP4` as
  `OP_CHECKSPHINCSVERIFY`, a new Tapscript opcode for verifying SPHINCS+
  (SLH-DSA) signatures carried in the Taproot annex.
- **[Taproot key-path hardening draft](repos/bips/bip-0368.mediawiki)** — Hardens key-path spending by
  requiring internal key disclosure via the annex and banning the BIP 341 NUMS
  point, closing the quantum ECDLP attack vector on key-path spends.

The proof-of-concept implementation lives in a
[Bitcoin Core fork](https://github.com/cmdruid/bitcoin) (branch `quantroot`)
included as a submodule at `repos/bitcoin`.

## Why Quantroot?

A quantum computer capable of solving the Elliptic Curve Discrete Logarithm
Problem (ECDLP) could forge Schnorr signatures and spend any Taproot output via
key-path — bypassing any post-quantum protections hidden in the script tree.

Quantroot's approach is a **quantum insurance policy** you can deploy today at
zero cost:

1. **Create Taproot outputs** with a hidden SPHINCS+ tapleaf in the MAST tree.
   No on-chain overhead — the tapleaf is just a hash nobody can see.
2. **Spend normally** with fast Schnorr key-path or script-path spends. Business
   as usual.
3. **If a quantum threat emerges**, the community activates the soft fork. BIP
   368 hardens key-path spends; BIP 369 enables SPHINCS+ script-path
   verification.
4. **Redeem via SPHINCS+** through your post-quantum tapleaf. Your funds are
   protected by hash-based cryptography that doesn't rely on elliptic curves.

## Project Status

Both BIPs are **implemented as proof-of-concept** on a Bitcoin Core fork with:

- 56 functional tests (activation, success/failure paths, hybrid security,
  interaction tests)
- NIST FIPS 205 SLH-DSA verification with custom Bitcoin parameter set
- Benchmarks (~1.8 ms verify, 64x Schnorr) and calibrated sigop costs
- Test vectors and fuzz targets for both BIPs
- BIP 9 versionbits activation with buried deployment for regtest

| Metric | Value |
|--------|-------|
| SPHINCS+ signature size | 4,080 bytes |
| SPHINCS+ public key size | 32 bytes |
| Schnorr P2TR verify | ~27 µs (baseline) |
| SPHINCS+ verify | ~1,756 µs (~64x Schnorr) |
| SPHINCS+ sign | ~918 ms (offline, doesn't affect validation) |
| Sigop weight | 3,200 (64x Schnorr's 50) |
| Security level | NIST Category 1 (128-bit classical) |

## Roadmap

### Ready Now
- Community review — post BIPs to bitcoin-dev mailing list
- Update status reports in `dev/reports/`

### Medium-Term
- W+C_P+FP optimization (3,408-byte signatures) — drop-in crypto library swap,
  same security level, ~16% size reduction
- Wallet support — key management, NUMS address generation, "full insurance"
  construction UX

### Long-Term
- External security audit
- BIP 9 versionbits activation parameters (currently TBD in both BIPs)

## Prerequisites

- Docker Engine 24+
- Docker Compose v2
- Git 2.30+
- 8 GB RAM recommended
- 20 GB disk recommended

## Quick Start

```bash
# Clone the repository (with submodules)
git clone --recurse-submodules <repo-url> && cd quantroot

# Initialize and build containers
make init

# Copy and configure environment
cp .env.example .env

# Start the stack
make start

# Verify services are healthy
make health
```

## Building the Bitcoin Core Fork Directly

If you want to build and test the consensus code outside of Docker:

```bash
cd repos/bitcoin

# Build
cmake -B build && cmake --build build -j$(nproc)

# Unit tests
build/bin/test_bitcoin --run_test=script_tests,transaction_tests

# BIP 369 functional tests
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini

# BIP 368 functional tests
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini

# Activation tests
python3 test/functional/feature_sphincs.py --activation --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --activation --configfile=build/test/config.ini

# Benchmarks (requires -DBUILD_BENCH=ON)
build/bin/bench_bitcoin -filter="Sphincs"
```

## Key Commands

| Command | Description |
|---------|-------------|
| `make help` | Print all available commands |
| `make init` | Initialize submodules and build containers |
| `make start` | Start core services |
| `make stop` | Stop all services |
| `make health` | Check service health |
| `make test-e2e` | Run full E2E test suite |
| `make test-smoke` | Run fast smoke tests |
| `make check` | Static checks and doc consistency |
| `make logs` | Follow all service logs |
| `make reset` | Stop and remove all runtime data |

## Repository Layout

| Directory | Contents |
|-----------|----------|
| `repos/bitcoin` | Bitcoin Core fork (submodule, `quantroot` branch) |
| `repos/bips` | Canonical local knowledge base for BIP specifications and vectors |
| `services/` | Docker service wrappers |
| `docs/` | Domain guides, overview, glossary, and navigation into `repos/bips` |
| `dev/` | Developer workflow, conventions, ADRs |
| `test/` | Cross-service test infrastructure |
| `scripts/` | Runtime helpers (mounted into containers) |
| `config/` | Shared runtime configuration |

## Knowledge Base

| I want to... | Go to |
|--------------|-------|
| Understand the domain and BIPs | [docs/INDEX.md](docs/INDEX.md) |
| Set up my dev environment | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Learn conventions and structure | [dev/README.md](dev/README.md) |
| Run or debug tests | [test/README.md](test/README.md) |
| Operate as an AI agent | [CLAUDE.md](CLAUDE.md) |

## License

This monorepo infrastructure is MIT licensed. The Bitcoin Core fork retains its
upstream MIT license. The vendored SLH-DSA library (`slhdsa-c`) is triple
licensed under Apache-2.0 / ISC / MIT. BIP specifications in `repos/bips` are
BSD-3-Clause.
