# Tests

## Overview

| Test | Where | Time | Coverage |
|------|-------|------|----------|
| Unit tests | `repos/bitcoin` | ~30s | 46 cases: keys, descriptors, DB |
| Consensus tests | `repos/bitcoin` | ~1m | 42 cases: opcode, annex, activation |
| Wallet tests | `repos/bitcoin` | ~2m | 66 assertions: RPCs, PSBT, spend |
| Demo E2E | `make test-demo` | ~30s | 22 checks: full Docker pipeline |

## Unit Tests

Run directly against the Bitcoin Core test binary:

```bash
cd repos/bitcoin
build/bin/test_bitcoin --run_test=sphincskeys_tests      # 17 cases
build/bin/test_bitcoin --run_test=qextkey_tests           # 16 cases
build/bin/test_bitcoin --run_test=qis_descriptor_tests    # 11 cases
build/bin/test_bitcoin --run_test=sphincskeys_db_tests    #  2 cases
```

## Consensus Functional Tests

```bash
cd repos/bitcoin
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini
```

## Wallet Functional Tests

```bash
cd repos/bitcoin
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
```

## Demo E2E Test

Runs against a Docker-hosted regtest node. Requires `make build-bitcoin` first.

```bash
make build-bitcoin    # Build binaries (first time only)
make start BG=1       # Start regtest container
make test-demo        # Run all 6 phases (22 checks)
make stop             # Clean up
```

| Phase | Checks | Coverage |
|-------|--------|----------|
| 1. Infrastructure | 5 | Binaries exist, container running, regtest network |
| 2. Wallet Operations | 5 | createsphincskey, listsphincskeys, getquantumaddress, exportqpub |
| 3. Key-Path Spend | 4 | Fund QI address, receive, key-path spend, confirm |
| 4. SPHINCS+ Emergency | 2 | sphincsspend, confirm on-chain |
| 5. PSBT Key-Path | 3 | walletcreatefundedpsbt → walletprocesspsbt → finalize → confirm |
| 6. PSBT SPHINCS+ Emergency | 3 | PSBT creation → sphincs_emergency signing → confirm |

## Manual Demo

For a step-by-step interactive demo, see [DEMO.md](DEMO.md).

## Verification Checklist

| Step | Expected Result |
|------|----------------|
| `createsphincskey` | Returns 64-char hex `sphincs_pubkey` + `qi_descriptor` |
| `getquantumaddress` | Returns `bcrt1p...` bech32m address |
| `listsphincskeys` | Shows the key with `has_private_key: true` |
| Fund QI address | `listunspent` shows the UTXO |
| Key-path spend | Confirms, witness has 2 elements (sig + BIP 368 annex) |
| Annex format | Starts with `5002` (0x50 tag + 0x02 type), 66 bytes |
| `sphincsspend` | Confirms, witness has 4 elements (sig + script + ctrl + annex) |
| SPHINCS+ annex | Starts with `5004` (0x50 tag + 0x04 type), 4083 bytes |
| `exportqpub` | Returns `Q1...` base58 string |
| `importqpub` | Watch-only wallet derives same addresses |
| Encrypted wallet | `listsphincskeys` works locked; spending requires unlock |

## Troubleshooting

**"Method not found"** — Wallet RPCs require a descriptor wallet.
Use `createwallet` (descriptors are the default).

**"No master key found"** — Wallet doesn't have private keys or is locked.

**"Key-path spend requires annex"** — Expected on regtest where BIP 368
is always active. The wallet includes the annex automatically.

## Files

```
test/
├── README.md            This file
├── DEMO.md              Step-by-step interactive demo guide
└── scripts/
    ├── lib/common.sh    Shared bash helpers
    └── test-demo.sh     Automated demo E2E (6 phases, 22 checks)
```
