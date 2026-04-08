# Quantroot

**Post-Quantum Security for Bitcoin Taproot**

Quantroot is a soft-fork upgrade path that brings [SPHINCS+](https://sphincs.org/) (SLH-DSA) post-quantum signatures to Bitcoin through Taproot — with zero cost today and full protection when you need it.

**Website:** [www.quantroot.org](https://www.quantroot.org)

## How It Works

Quantroot is a **quantum insurance policy** you can deploy today:

1. **Create Taproot outputs** with a hidden hybrid tapleaf. Zero on-chain overhead — your outputs look like ordinary Taproot.
2. **Spend normally** with fast Schnorr key-path spends (~64 bytes). The hybrid leaf stays hidden.
3. **If a quantum threat emerges**, the network activates the soft fork. BIP 368 hardens key-path spends; BIP 369 enables SPHINCS+ verification.
4. **Redeem via the hybrid tapleaf** using both Schnorr and SPHINCS+ signatures. Your funds are protected by hash-based cryptography that doesn't rely on elliptic curves.

## Four Companion BIPs

### Consensus Layer

| BIP | Title | Description |
|-----|-------|-------------|
| [368](repos/bips/bip-0368.mediawiki) | Taproot Key-Path Hardening | Requires internal key disclosure via annex, bans NUMS points, closes quantum ECDLP attack on key-path spends |
| [369](repos/bips/bip-0369.mediawiki) | OP_CHECKSPHINCSVERIFY | Redefines OP_NOP4 for SPHINCS+ signature verification in Tapscript, signatures carried in the Taproot annex |

### Wallet Layer

| BIP | Title | Description |
|-----|-------|-------------|
| [395](repos/bips/bip-0395.mediawiki) | Quantum-Insured Extended Keys | Extends BIP 32 with SPHINCS+ key material (qpub/qprv), `qr()` output descriptor, seed-only backup |
| [377](repos/bips/bip-0377.mediawiki) | PSBT Extensions for SPHINCS+ | PSBT fields for SPHINCS+ pubkeys, signatures, and annex data with two-round signing workflow |

## Quick Start

```bash
bitcoin-cli createwallet "quantum"
bitcoin-cli createsphincskey
bitcoin-cli getquantumaddress
bitcoin-cli exportqpub
bitcoin-cli listsphincskeys
```

Both BIP 368 and BIP 369 are active from block 1 on regtest.

## Benchmarks

| | Schnorr | SPHINCS+ |
|---|---------|----------|
| **Sign** | ~27 µs | ~918 ms |
| **Verify** | ~27 µs | ~1,756 µs (64x) |
| **Signature** | 64 bytes (16 vB) | 4,080 bytes (1,020 vB) |

SPHINCS+ uses NIST FIPS 205 SLH-DSA with a custom Bitcoin parameter set at NIST Category 1 (128-bit classical security).

## Test Coverage

| Category | Count |
|----------|-------|
| Consensus tests (BIP 368 + 369) | 56 |
| Wallet unit tests (key, qextkey, descriptor, DB) | 46 |
| Functional tests (RPCs, PSBT, activation, script-path) | 59 |
| **Total** | **161** |

## Building from Source

```bash
cd repos/bitcoin
cmake -B build && cmake --build build -j$(nproc)

# Unit tests
build/bin/test_bitcoin --run_test=sphincskeys_tests,qextkey_tests,qis_descriptor_tests,script_tests

# Functional tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
```

## Repository Layout

| Directory | Contents |
|-----------|----------|
| `repos/bitcoin` | Bitcoin Core fork (submodule, `quantroot` branch) |
| `repos/bips` | BIP specifications and test vectors |
| `services/website` | Project website ([www.quantroot.org](https://www.quantroot.org)) |
| `docs/` | Domain guides, overview, glossary |
| `dev/` | Plans, specs, reports, conventions |
| `test/` | Cross-service test infrastructure |

## License

This monorepo infrastructure is MIT licensed. The Bitcoin Core fork retains its upstream MIT license. The vendored SLH-DSA library is triple licensed under Apache-2.0 / ISC / MIT. BIP specifications are BSD-3-Clause.
