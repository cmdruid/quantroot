# PR Commit Reorganization

- Status: proposed
- Date: 2026-04-09
- Owner: cmdruid

## Goal

Squash 21 bitcoin commits and 6 bips commits into clean logical series
for mailing list submission. Force push both branches.

## Current Bitcoin Commits (21)

```
1d88c637 rpc: register sphincs_emergency param in bitcoin-cli conversion table
d7fdae86 test: add encrypted wallet round-trip and sphincsspend error cases
77ec6b50 refactor: polish comments, error handling, and code deduplication
b2e5617f refactor: fix high/medium audit findings
f185fdb8 refactor: fix critical audit findings (buffer safety, HMAC assert, copy assignment)
4e0fb38b wallet: fix encrypted wallet handling in createsphincskey
8eb30c85 wallet: fix SPHINCS+ script-path signing pipeline
4db7803b wallet: fix SPHINCS+ key storage on QI SPKMs, add QI UTXO filtering
95f7809e wallet: add sphincsspend RPC and SPHINCS+ emergency signing pipeline
9b23c13c refactor: update BIP references and purpose index to assigned numbers
282c61f2 test: add qr() descriptor unit tests
e2bb9817 wallet: add qr() quantum-insured output descriptor
76a49cd7 test/doc: add wallet functional tests and documentation
83141f23 test: add wallet unit tests for SPHINCS+ key management
49c5d870 wallet: add quantum-insured RPCs
829c1ebd wallet: add annex-aware signing pipeline and PSBT extensions
204a88ba wallet: add SphincsKey, QExtKey, and qis() descriptor
cece5930 doc: add BIP 368/369 specifications, test vectors, and status report
bbb333bf test: add BIP 368/369 functional tests and fuzz targets
8bd6d655 consensus: add OP_CHECKSPHINCSVERIFY and key-path hardening
5938ce85 crypto: add SLH-DSA SPHINCS+ library and benchmarks
```

## Target Bitcoin Series (7 commits)

### 1. `crypto: add SLH-DSA SPHINCS+ library and benchmarks`
- Source: 5938ce85
- Content: SPHINCS+ C library, Bitcoin parameter set, benchmarks

### 2. `consensus: add OP_CHECKSPHINCSVERIFY and key-path hardening`
- Source: 8bd6d655 + cece5930 (doc)
- Content: interpreter.cpp (opcode, annex parsing, key-path), validation.cpp
  (co-activation), policy.cpp (annex standardness), script.h (constants),
  chainparams (deployment)

### 3. `test: add BIP 368/369 consensus tests`
- Source: bbb333bf
- Content: feature_sphincs.py, feature_keypath_hardening.py, fuzz targets

### 4. `wallet: add SphincsKey, QExtKey, descriptors, and RPCs`
- Source: 204a88ba + 49c5d870 + e2bb9817 + 829c1ebd + 95f7809e + all
  fixups (4e0fb38b, 4db7803b, 8eb30c85, 77ec6b50, b2e5617f, f185fdb8,
  9b23c13c, 1d88c637)
- Content: sphincskeys.h/.cpp, qextkey.h/.cpp, descriptor.cpp (qis/qr),
  sphincs.cpp (8 RPCs), scriptpubkeyman (FillPSBT, SPHINCS key storage),
  wallet.cpp (two-pass), sign.cpp (hybrid fallback, annex), psbt.h/.cpp
  (fields, emergency flags), client.cpp

### 5. `test: add wallet unit and functional tests`
- Source: 83141f23 + 282c61f2 + 76a49cd7 + d7fdae86
- Content: sphincskeys_tests, qextkey_tests, qis_descriptor_tests,
  sphincskeys_db_tests, wallet_sphincs.py, wallet_sphincs_psbt.py,
  wallet_sphincs_activation.py, wallet_sphincs_scriptpath.py

### 6. `doc: add wallet documentation`
- Source: 76a49cd7 (doc portion)
- Content: doc/quantum-insured-wallet.md

### 7. `doc: add BIP 368/369 specifications and test vectors`
- Source: cece5930 (doc portion only — BIP files removed, they live in
  repos/bips now)
- NOTE: This commit may be empty if all BIP content was already in repos/bips.
  If so, skip it.

## Target Bips Series (2 commits)

### 1. `doc: add BIP 368/369/377/395 draft specifications`
- Source: f57d1ad + 8e03298 + 92d3e47 + 86b9838 + af0f8b3 + 90d8c0e
- Content: All 4 BIP mediawiki files + test vectors, fully updated with
  final BIP numbers, version bytes, field types, and audit fixes

## Execution

### Step 1: Bitcoin rebase
```bash
cd repos/bitcoin
git rebase -i 5938ce85^
# Mark commits for squash per the target series above
# Resolve conflicts
# Write new commit messages
```

### Step 2: Verify
```bash
cmake --build build -j$(nproc)
build/bin/test_bitcoin --run_test=sphincskeys_tests,qextkey_tests,qis_descriptor_tests,sphincskeys_db_tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
```

### Step 3: Bips rebase
```bash
cd repos/bips
git rebase -i f57d1ad^
# Squash all 6 into 1 commit
```

### Step 4: Force push
```bash
cd repos/bitcoin && git push --force origin quantroot
cd repos/bips && git push --force origin quantroot
```

### Step 5: Update monorepo pointer
```bash
cd /home/cscott/Repos/bitcoin/quantroot
git add repos/bitcoin repos/bips
git commit -m "chore: update submodule pointers after commit reorganization"
git push origin master
```
