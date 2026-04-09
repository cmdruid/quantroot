# Tests

Cross-service tests for the Quantroot monorepo. Tests that validate a
single repo's own code live in that repo (e.g., `repos/bitcoin/test/`).

## Demo E2E Test

The primary test is the demo environment E2E (`test/scripts/test-demo.sh`),
which exercises the full pipeline against a Docker-hosted regtest node:

```bash
make build-bitcoin    # Build binaries (first time only)
make start BG=1       # Start regtest container
make test-demo        # Run all 6 phases (22 checks)
make stop             # Clean up
```

### Phases

| Phase | Checks | Coverage |
|-------|--------|----------|
| 1. Infrastructure | 5 | Binaries, container, regtest |
| 2. Wallet Operations | 5 | createsphincskey, listsphincskeys, getquantumaddress, exportqpub |
| 3. Key-Path Spend | 4 | Fund QI address, receive, key-path spend, confirm |
| 4. SPHINCS+ Emergency | 2 | sphincsspend, confirm on-chain |
| 5. PSBT Key-Path | 3 | walletcreatefundedpsbt, walletprocesspsbt, finalize + confirm |
| 6. PSBT SPHINCS+ Emergency | 3 | PSBT creation, sphincs_emergency signing, confirm |

### Functional Tests (in repos/bitcoin)

These run directly against `test_bitcoin` without Docker:

```bash
cd repos/bitcoin
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini
```

### Unit Tests (in repos/bitcoin)

```bash
cd repos/bitcoin
build/bin/test_bitcoin --run_test=sphincskeys_tests,qextkey_tests,qis_descriptor_tests,sphincskeys_db_tests
```

## Files

```
test/
├── README.md                   This file
└── scripts/
    ├── lib/
    │   └── common.sh           Shared bash helpers (colors, logging, wait_for_service)
    └── test-demo.sh            Demo E2E test (6 phases, 22 checks)
```
