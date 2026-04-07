# Wallet Support — Phase 4+ Roadmap & PR Preparation

- Status: complete
- Date: 2026-04-05 (completed 2026-04-05)
- Owner: cmdruid

## Summary

Phases 1-3 of wallet support are complete (155 tests passing). The wallet can
create SPHINCS+ keys, register QI descriptors, generate addresses, fund, and
key-path spend with BIP 368 annex. qpub/qprv export/import, watch-only wallets,
encrypted wallets, change addresses, and descriptor checksums all work.

This plan covers: remaining production gaps, PR preparation, and post-merge
polish.

---

## Phase 4: Production Readiness

### 4.1 End-to-end hybrid tapleaf spend test (CRITICAL)

The SPHINCS+ signing key now flows through the pipeline, but no test forces
script-path spending to verify the full two-round signature (SPHINCS+ annex +
Schnorr). This is the core quantum emergency feature.

**Approach**: Create a test that removes the internal key from the signing
provider so `SignTaproot` falls through to script-path. Or add an RPC option
`force_script_path=true` to `sendtoaddress`/`walletcreatefundedpsbt`.

**Simpler approach**: Construct a raw transaction spending the QI UTXO via
script-path using the test framework's low-level TX building, bypassing the
wallet's key-path preference. Use `test_framework/sphincs.py` for SPHINCS+
signing and manually assemble the witness.

**Files**: `test/functional/wallet_sphincs.py` or new
`test/functional/feature_sphincs_wallet_spend.py`

**Acceptance**: Witness `[schnorr_sig] [script] [control_block] [annex]`
where annex = `0x50 || 0x04 || 0x01 || <4080-byte SPHINCS+ sig>`. Transaction
accepted by mempool and confirmed.

### 4.2 Multi-account in single wallet

`createsphincskey` returns early if any descriptor manager has a SPHINCS+ key.
Fix: track account index → descriptor manager mapping, or check only the
Taproot descriptor managers and compare derivation paths.

**Files**: `src/wallet/rpc/sphincs.cpp`

### 4.3 Rescan on importqpub

Add optional `timestamp` parameter (default `"now"`). After descriptor
registration, call `pwallet->chain().findFirstBlockWithTimeAndHeight()` and
`pwallet->ScanForWalletTransactions()`.

Follow the `importdescriptors` pattern in `src/wallet/rpc/backup.cpp`.

**Files**: `src/wallet/rpc/sphincs.cpp`

### 4.4 Make BIP 368/369 annex standard in policy

Currently the wallet needs `-acceptnonstdtxn=1` for annex transactions.

**Approach**: In `src/policy/policy.cpp`, update `IsStandardTx()` and related
checks to accept annex data when BIP 368/369 deployment is active. The annex
is already consensus-valid — this is purely a relay policy change.

**Files**: `src/policy/policy.cpp`, `src/policy/policy.h`

---

## Phase 5: PR Preparation

### 5.1 Code review cleanup

- Remove debug/placeholder comments
- Ensure all new code follows Bitcoin Core style (clang-format)
- Verify all new files have correct copyright headers
- Remove any `TODO` or `FIXME` comments that aren't intentional
- Check for unused includes

### 5.2 Commit organization

Split the changes into logical, reviewable commits:

1. **Consensus: BIP 368/369 co-activation** — `validation.cpp` change
   (gating `SCRIPT_VERIFY_CHECKSPHINCSVERIFY` on both deployments)

2. **Wallet: SphincsKey class** — `sphincskeys.h/.cpp`, `walletdb.h/.cpp`
   changes, `sphincskeys_tests.cpp`

3. **Wallet: QExtPubKey/QExtKey** — `qextkey.h/.cpp`, `chainparams.h/.cpp`
   changes, `qextkey_tests.cpp`

4. **Script: qis() descriptor** — `descriptor.cpp`, `signingprovider.h/.cpp`
   changes, `qis_descriptor_tests.cpp`

5. **Script: Annex-aware signing** — `sign.h/.cpp` changes (annex in
   SignatureData, ComputeSchnorrSignatureHash with annex, BIP 368 key-path
   annex construction, SPHINCS+ pre-signing in SignTaproot)

6. **PSBT: SPHINCS+ field types** — `psbt.h/.cpp` changes (new field
   constants, serialization, deserialization, bridge functions)

7. **Wallet: RPCs** — `rpc/sphincs.cpp`, `rpc/wallet.cpp` registration

8. **Tests: Functional tests** — `wallet_sphincs.py`, `wallet_sphincs_psbt.py`,
   `wallet_sphincs_activation.py`

9. **Docs** — `doc/quantum-insured-wallet.md`

### 5.3 Test coverage audit

- Verify all new RPCs have functional test coverage
- Verify all new code paths have unit test coverage
- Run `test_runner.py` with all quantroot tests enabled
- Check for test flakiness (run 3x)

### 5.4 PR description

Write a comprehensive PR description:
- Link to all four BIP specs
- Summary of changes with file counts
- Test results (unit + functional)
- Breaking changes (none — additive only)
- Review guidance (suggest reviewing in commit order)

---

## Phase 6: Post-Merge Polish

### 6.1 BIP test vectors with concrete hex values

Generate full hex chain from known seed:
```
seed → master CExtKey → SPHINCS+ keypair → qpub/qprv bytes →
base58 → child derivation → hybrid script → leaf hash →
merkle root → output key Q → bech32m address
```

Output as JSON in `repos/bips/bip-0395/`.

### 6.2 Wallet backup/restore test

Functional test:
1. Create wallet, fund QI addresses
2. Export mnemonic / seed
3. Create new wallet from same seed
4. `createsphincskey` → same SPHINCS+ key (deterministic from seed)
5. Verify same addresses and balance

### 6.3 Performance benchmarks

Add to `src/bench/sphincs.cpp`:
- `SphincsWalletSign` — full wallet signing path (key lookup + sighash + sign)
- `QIAddressDerivation` — derive address from qpub at index
- Document results in `doc/quantum-insured-wallet.md`

### 6.4 Website interactive demo

Add to `services/website/src/pages/`:
- `demo.astro` — interactive qpub → address derivation
- Pure client-side JavaScript (no private keys)
- Shows hybrid script anatomy for each address

---

## Dependency Graph

```
Phase 4 (production):
  4.1 (hybrid spend test) — CRITICAL, independent
  4.2 (multi-account) — independent
  4.3 (rescan) — independent
  4.4 (annex policy) — independent

Phase 5 (PR prep):
  5.1 (cleanup) → 5.2 (commits) → 5.3 (test audit) → 5.4 (PR description)
  Can start 5.1 while Phase 4 is in progress

Phase 6 (post-merge):
  All independent, lower priority
```

---

## Current Test Coverage

| Category | Tests | Status |
|----------|-------|--------|
| Unit: sphincskeys | 13 | Pass |
| Unit: sphincskeys_db | 2 | Pass |
| Unit: qextkey | 13 | Pass |
| Unit: qis_descriptor | 6 | Pass |
| Unit: script/transaction | 34 | Pass |
| Functional: feature_sphincs | 43 | Pass |
| Functional: feature_keypath_hardening | 13 | Pass |
| Functional: wallet_sphincs | 21 | Pass |
| Functional: wallet_sphincs_psbt | 6 | Pass |
| Functional: wallet_sphincs_activation | 4 | Pass |
| **Total** | **155** | **All pass** |

## Files Modified/Created (repos/bitcoin)

### New files (12)
- `src/wallet/sphincskeys.h/.cpp` — SphincsKey class
- `src/wallet/qextkey.h/.cpp` — QExtPubKey/QExtKey + base58 encode/decode
- `src/wallet/rpc/sphincs.cpp` — 7 RPCs
- `src/wallet/test/sphincskeys_tests.cpp` — 13 unit tests
- `src/wallet/test/sphincskeys_db_tests.cpp` — 2 DB tests
- `src/wallet/test/qextkey_tests.cpp` — 13 unit tests
- `src/wallet/test/qis_descriptor_tests.cpp` — 6 unit tests
- `test/functional/wallet_sphincs.py` — 21 functional tests
- `test/functional/wallet_sphincs_psbt.py` — 6 functional tests
- `test/functional/wallet_sphincs_activation.py` — 4 functional tests
- `doc/quantum-insured-wallet.md` — Documentation

### Modified files (12)
- `src/script/descriptor.cpp` — QISDescriptor class + qis() parser
- `src/script/sign.h` — SignatureData fields (annex, sphincs_key, include_annex)
- `src/script/sign.cpp` — Annex-aware signing, SPHINCS+ pre-signing, BIP 368 annex
- `src/script/signingprovider.h` — TaprootSpendData sphincs_keys field
- `src/script/signingprovider.cpp` — Merge sphincs_keys
- `src/psbt.h` — PSBT field types + SignPSBTInput sphincs_key param
- `src/psbt.cpp` — Serialization, bridge, merge, sphincs_key injection
- `src/validation.cpp` — Co-activation (BIP 369 requires BIP 368)
- `src/kernel/chainparams.h` — EXT_QI_PUBLIC_KEY/EXT_QI_SECRET_KEY enum
- `src/kernel/chainparams.cpp` — Version bytes for all networks
- `src/wallet/scriptpubkeyman.h/.cpp` — SPHINCS+ key storage, SetupSphincsKey, FillPSBT
- `src/wallet/walletdb.h/.cpp` — DB constants, write/load handlers
- `src/wallet/rpc/wallet.cpp` — RPC registration
- `src/wallet/CMakeLists.txt` — Build system
- `src/wallet/test/CMakeLists.txt` — Test build system
- `test/functional/test_runner.py` — Test runner registration

## Archive Condition

Move this plan to `../archive/` when the PR is merged or superseded.
