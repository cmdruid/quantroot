# Quantroot Wallet Code Audit Report

- Date: 2026-04-05
- Scope: All changes on `quantroot` branch vs `master` in `repos/bitcoin`
- Stats: 30 commits, 72 files changed, 9,738 insertions, 23 deletions
- Tests: 168 passing (75 unit + 93 functional)

## Executive Summary

The implementation has solid cryptographic foundations and comprehensive
consensus-level test coverage (56 existing tests for BIP 368/369). However,
the wallet layer has **3 critical bugs**, **4 major issues**, and **7 medium
issues** that must be addressed before merge. The consensus code (commits 1-29)
is high quality. The wallet code (commit 30) needs significant rework.

---

## Critical Issues (Must Fix Before Merge)

### C1: Encrypted wallets cannot sign SPHINCS+ transactions

`DescriptorScriptPubKeyMan` stores the encrypted SPHINCS+ key in
`m_crypted_sphincs_key` but has **no decryption method**. There is no
`GetSphincsSecret()` that calls `DecryptSecret()` to retrieve the key when
the wallet is unlocked. This means encrypted wallets can create QI addresses
but cannot spend from them.

**Files**: `src/wallet/scriptpubkeyman.h/.cpp`
**Fix**: Add `GetSphincsSecret(const CKeyingMaterial&)` method following the
pattern in `CheckDecryptionKey()` (line 869).

### C2: SPHINCS+ pubkeys/sigs lost in PSBT round-trip

`PSBTInput::FillSignatureData()` copies `m_tap_annex` to `sigdata` but does
NOT copy `m_tap_sphincs_pubs` or `m_tap_sphincs_sigs`. Similarly,
`FromSignatureData()` copies annex back but not SPHINCS+ fields. Any PSBT
processing that goes through the SignatureData bridge loses SPHINCS+ data.

**Files**: `src/psbt.cpp` lines 140-144, 207-211
**Fix**: Add bridging for `m_tap_sphincs_pubs` and `m_tap_sphincs_sigs` in
both `FillSignatureData()` and `FromSignatureData()`.

### C3: `exportqprv` exports wrong key for encrypted wallets

`exportqprv` re-derives the SPHINCS+ key via `SphincsKey::DeriveFromMaster()`
instead of retrieving the stored `m_sphincs_key`. For encrypted wallets, the
stored key cannot be accessed (see C1), so the RPC re-derives from the master
key. If the wallet was encrypted before the SPHINCS+ key was stored, the
re-derived key may not match the stored one.

**File**: `src/wallet/rpc/sphincs.cpp` line 437
**Fix**: Retrieve the stored key via `GetSphincsSecret()` (once C1 is fixed).

---

## Major Issues (Should Fix Before Merge)

### M1: Account path hardcoded to mainnet coin_type

`createsphincskey` hardcodes coin_type as `0x80000000` (mainnet) for all
networks. Testnet wallets should use `0x80000001`. This means testnet and
mainnet wallets derive the same SPHINCS+ key from the same seed.

**File**: `src/wallet/rpc/sphincs.cpp` lines 61-65
**Fix**: Detect network via `Params().GetChainType()` and set coin_type
accordingly.

### M2: `importqprv` skips encryption path

`importqprv` directly writes the SPHINCS+ secret key to the DB via
`batch.WriteSphincsKey()` without checking if the wallet is encrypted. If the
wallet is encrypted, the key should be encrypted before storage.

**File**: `src/wallet/rpc/sphincs.cpp` lines 511-532
**Fix**: Use `SetupSphincsKey()` or check `HasEncryptionKeys()` and call
`EncryptSecret()`.

### M3: `SphincsKey::Load()` doesn't cryptographically verify

`Load()` checks that the last 32 bytes of the secret match the expected pubkey
via byte comparison. It does NOT re-derive the public key from the secret
components to verify cryptographic correctness. A corrupted secret with
matching tail bytes would pass.

**File**: `src/wallet/sphincskeys.cpp` lines 80-102
**Fix**: Call `SphincsKeygen()` with the secret's seed components and compare
the output pubkey, or accept the byte-comparison as sufficient (document why).

### M4: `listsphincskeys` always returns `has_private_key=true`

The RPC always returns `true` for `has_private_key` regardless of whether the
wallet is encrypted, locked, or watch-only.

**File**: `src/wallet/rpc/sphincs.cpp` line 583
**Fix**: Check `m_sphincs_key.has_value()` vs `m_crypted_sphincs_key.has_value()`
and whether the wallet is unlocked.

---

## Medium Issues

### N1: Missing compact_size case 255 in annex parsing

The consensus annex parser handles compact_size cases for 1, 2, and 4 byte
encodings but not the 8-byte case (first byte == 255). An attacker-crafted
annex with this prefix would leave `num_sigs` at 0.

**File**: `src/script/interpreter.cpp` (~line 2107)
**Fix**: Add explicit handling or rejection of the 8-byte compact_size case.

### N2: No explicit bounds check before signature span creation

The signature offset calculation in `OP_CHECKSPHINCSVERIFY` relies on implicit
bounds from annex parsing. An explicit `if (sig_offset + SPHINCS_SIG_SIZE >
annex_data.size())` check before creating the span would be defensive.

**File**: `src/script/interpreter.cpp` (~line 2620)

### N3: No upper bound on PSBT annex size

`PSBT_IN_TAP_ANNEX` deserialization accepts arbitrarily large annexes. A
malicious PSBT could contain a multi-MB annex causing memory exhaustion.

**File**: `src/psbt.h` (~line 867)
**Fix**: Reject annexes larger than a reasonable limit (e.g., `MAX_STANDARD_TX_WEIGHT`).

### N4: Annex validation incomplete in PSBT

PSBT deserialization doesn't validate that the annex starts with `0x50` or
that the type byte is known. This is caught later at consensus but should be
caught early.

**File**: `src/psbt.h` (~line 858)

### N5: DB record format not forward-compatible

`WriteSphincsKey` stores `(secret, hash)` with no version number. Future
metadata additions would require a migration.

**File**: `src/wallet/walletdb.cpp` line 240

### N6: Comment ordering mismatch in consensus/params.h

BIP 369 comment precedes `BIP368Height` field and vice versa.

**File**: `src/consensus/params.h` (~line 114)

### N7: Duplicate `#include <script/script.h>` in sign.cpp

The header is included twice.

**File**: `src/script/sign.cpp`

---

## Style Issues

### S1: `VALIDATION_WEIGHT_PER_SPHINCS_SIGOP` calculation not documented

The value 3200 is described as "64x Schnorr's 50" but the derivation from
benchmark measurements isn't shown.

### S2: Missing secure memory documentation on SphincsKey

No docstring explains when memory is wiped, how moves are safe, or the
security guarantees of `secure_unique_ptr`.

### S3: `sphincs_key` parameter should be named `sphincs_secret`

`SignPSBTInput`'s parameter is called `sphincs_key` but carries the 64-byte
secret key, not just a key identifier.

### S4: Descriptor `qis()` doesn't warn about hardened EC key expressions

A hardened key expression in `qis()` cannot be derived from a qpub (public-only),
which would cause silent signing failures.

---

## Test Coverage Gaps

### T1: No test for encrypted wallet SPHINCS+ signing
### T2: No test for PSBT SPHINCS+ pubkey/sig round-trip preservation
### T3: No test for `exportqprv` → `importqprv` address match verification
### T4: No test for `account_index != 0`
### T5: No test for corrupted DB record loading
### T6: No test for oversized PSBT annex rejection
### T7: No test for co-activation boundary (SPHINCS active without key-path hardening)

---

## Commit Organization Recommendation

The 30 commits should be reorganized into ~15 logical commits for PR review:

**Tier 1 — Crypto foundation** (reviewable independently):
1. `crypto: add SLH-DSA SPHINCS+ verification library`
2. `build: add sphincs_signer CMake target`
3. `bench: add SPHINCS+ benchmarks`

**Tier 2 — BIP 369 consensus** (core soft-fork):
4. `consensus: add OP_CHECKSPHINCSVERIFY (BIP 369)`
5. `consensus: add BIP 369 deployment and activation`
6. `test: add comprehensive BIP 369 functional tests`
7. `test: add BIP 369 fuzz targets`

**Tier 3 — BIP 368 consensus** (companion soft-fork):
8. `consensus: implement BIP 368 key-path hardening`
9. `consensus: require BIP 368 co-activation for BIP 369`
10. `test: add BIP 368 functional tests`

**Tier 4 — Wallet support** (application layer):
11. `wallet: add SphincsKey class and DB storage`
12. `wallet: add QExtPubKey/QExtKey and qis() descriptor`
13. `wallet: add annex-aware signing and PSBT extensions`
14. `wallet: add quantum-insured RPCs`
15. `test: add wallet functional tests`
16. `doc: add quantum-insured wallet documentation`

The 14 doc-only commits (BIP spec drafts, status reports) should be squashed
into 1-2 commits or moved to the `repos/bips` submodule.

---

## Severity Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 3 | Must fix |
| Major | 4 | Should fix |
| Medium | 7 | Should fix |
| Style | 4 | Nice to fix |
| Test gaps | 7 | Should add |
| **Total** | **25** | |

## Recommendation

The consensus code (BIP 368/369 implementation, commits 1-29) is high quality
and ready for review after minor fixes (N1, N2, N6). The wallet code (commit
30) needs a focused rework sprint to address the 3 critical issues (encrypted
wallet support, PSBT data loss, exportqprv correctness) before it's
merge-ready. Estimated effort: 2-3 days for critical fixes, 1 week for all
major + medium issues.
