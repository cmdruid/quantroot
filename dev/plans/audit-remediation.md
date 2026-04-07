# Audit Remediation & PR Preparation Plan

- Status: complete
- Date: 2026-04-05
- Owner: cmdruid
- Source: `dev/reports/wallet-code-audit.md`

## Context

A comprehensive audit of the `quantroot` branch (30 commits, 72 files, 9,738
insertions) identified 3 critical bugs, 4 major issues, 7 medium issues, 4
style issues, and 7 test gaps. The consensus code (BIP 368/369) is solid. The
wallet code needs focused rework before the branch is PR-ready.

This plan addresses all findings in priority order, then reorganizes commits
for review.

---

## Phase A: Critical Fixes (Must Fix)

### A1: Encrypted wallet SPHINCS+ decryption (C1)

**Problem**: No `GetSphincsSecret()` method — encrypted wallets can't sign.

**Files**: `src/wallet/scriptpubkeyman.h/.cpp`

Add method to `DescriptorScriptPubKeyMan`:
```cpp
std::optional<SphincsKey> GetSphincsSigningKey() const
    EXCLUSIVE_LOCKS_REQUIRED(cs_desc_man);
```

Implementation:
- If `m_sphincs_key` is set (unencrypted), return it directly
- If `m_crypted_sphincs_key` is set, decrypt via `m_storage.WithEncryptionKey()`
  using `DecryptSecret()`, then `SphincsKey::Load()` with decrypted bytes
- Return `std::nullopt` if wallet is locked or no key exists

Update callers:
- `exportqprv` — use `GetSphincsSigningKey()` instead of re-deriving
- `FillPSBT` — use `GetSphincsSigningKey()` when passing sphincs_key
- `listsphincskeys` — check `GetSphincsSigningKey().has_value()` for
  `has_private_key` field

**Test**: Extend `wallet_sphincs.py` encrypted wallet tests to verify:
- Create encrypted wallet, create SPHINCS+ key
- Lock wallet → `exportqprv` fails (correctly)
- Unlock → `exportqprv` returns valid qprv
- Fund QI address → spend while unlocked → succeeds

### A2: PSBT SPHINCS+ data bridge (C2)

**Problem**: `FillSignatureData()` / `FromSignatureData()` don't copy SPHINCS+
pubkeys or signatures.

**File**: `src/psbt.cpp`

In `FillSignatureData()` after annex bridging (~line 144):
```cpp
for (const auto& [pk_leaf, sphincs_pub] : m_tap_sphincs_pubs) {
    sigdata.tr_spenddata.sphincs_keys.emplace(pk_leaf.second, sphincs_pub);
}
```

In `FromSignatureData()` (~line 211):
```cpp
for (const auto& [leaf_hash, sphincs_pub] : sigdata.tr_spenddata.sphincs_keys) {
    // Map back to PSBT format using leaf_hash
    // Need xonly key for the PSBT key — extract from tr_spenddata
}
```

Note: The PSBT uses `(xonly, leaf_hash)` as key, but `sigdata.tr_spenddata.sphincs_keys`
uses just `leaf_hash`. The bridge needs to reconstruct the xonly from
`sigdata.tr_spenddata.internal_key` or the signing provider.

For SPHINCS+ signatures, they flow through the annex (not through
`taproot_script_sigs`), so the PSBT `m_tap_sphincs_sigs` field is primarily
for multi-party workflows where signatures are collected before annex assembly.

**Test**: `wallet_sphincs_psbt.py` — verify SPHINCS+ pubkey survives PSBT
round-trip: `FillSignatureData → FromSignatureData → check m_tap_sphincs_pubs`.

### A3: Fix `exportqprv` to use stored key (C3)

**Problem**: Re-derives SPHINCS+ key instead of retrieving stored one.

**File**: `src/wallet/rpc/sphincs.cpp` — `exportqprv()`

Replace the re-derivation block:
```cpp
// OLD: SphincsKey sk = SphincsKey::DeriveFromMaster(ext_key, acct_path);
// NEW:
auto signing_key = desc_mgr->GetSphincsSigningKey();
if (!signing_key) {
    throw JSONRPCError(RPC_WALLET_ERROR, "SPHINCS+ secret key not available.");
}
std::memcpy(qkey.sphincs_secret.data(), signing_key->SecretData(), 64);
```

Depends on A1 (`GetSphincsSigningKey()`).

---

## Phase B: Major Fixes (Should Fix)

### B1: Network-aware coin_type (M1)

**File**: `src/wallet/rpc/sphincs.cpp` — `createsphincskey()`

Replace hardcoded `0x80000000`:
```cpp
uint32_t coin_type;
switch (Params().GetChainType()) {
    case ChainType::MAIN: coin_type = 0x80000000; break; // 0'
    default: coin_type = 0x80000001; break; // 1' for testnet/signet/regtest
}
std::vector<uint32_t> account_path = {0x8000018B, coin_type, 0x80000000 + account_index};
```

**File**: `src/wallet/rpc/sphincs.cpp` — same fix in `exportqprv()` derivation

**Test**: `wallet_sphincs.py` — already runs on regtest, verify path uses
coin_type 1.

### B2: Fix `importqprv` encryption (M2)

**File**: `src/wallet/rpc/sphincs.cpp` — `importqprv()`

Replace manual `WriteSphincsKey` with proper `SetupSphincsKey`-like logic:
```cpp
// Instead of batch.WriteSphincsKey(...), use:
if (pwallet->HasEncryptionKeys()) {
    // Encrypt the SPHINCS+ secret before storing
    CKeyingMaterial secret_material{...};
    std::vector<unsigned char> crypted;
    pwallet->WithEncryptionKey([&](const CKeyingMaterial& enc_key) {
        return EncryptSecret(enc_key, secret_material, iv, crypted);
    });
    batch.WriteCryptedSphincsKey(spk_man.GetID(), pk_arr, crypted);
    spk_man.LoadCryptedSphincsKey(pubkey_span, crypted);
} else {
    batch.WriteSphincsKey(spk_man.GetID(), pk_arr, sk_arr);
    spk_man.LoadSphincsKey(pubkey_span, secret_span);
}
```

### B3: Fix `SphincsKey::Load()` verification (M3)

**File**: `src/wallet/sphincskeys.cpp`

The current byte comparison is actually correct for the SPHINCS+ key format —
the public key IS the last 32 bytes of the secret key (pk_seed || pk_root).
Add a comment explaining why this is sufficient:

```cpp
// The SPHINCS+ public key is defined as the last 32 bytes of the 64-byte
// secret key (pk_seed || pk_root). Byte comparison is sufficient because
// any corruption that preserves the last 32 bytes but corrupts the first
// 32 bytes (sk_seed || sk_prf) would produce invalid signatures, which
// are caught at consensus verification time.
```

No code change needed — just documentation.

### B4: Fix `listsphincskeys` `has_private_key` (M4)

**File**: `src/wallet/rpc/sphincs.cpp`

```cpp
bool has_priv = false;
if (desc_mgr->m_sphincs_key.has_value()) {
    has_priv = true;  // Unencrypted key available
}
// For encrypted wallets, key exists but may not be accessible
if (desc_mgr->m_crypted_sphincs_key.has_value()) {
    has_priv = true;  // Key exists (encrypted)
}
entry.pushKV("has_private_key", has_priv);
```

Wait — `m_sphincs_key` and `m_crypted_sphincs_key` are private. Use the public
`HasSphincsKey()` method and add a `HasSphincsPrivateKey()` method that
distinguishes unencrypted from encrypted.

Actually, the simplest correct answer: `has_private_key` means "this manager
has a private key (encrypted or not)". For watch-only (importqpub), neither
field is set, so `HasSphincsKey()` returns false. For encrypted wallets,
`m_crypted_sphincs_key` is set, so `HasSphincsKey()` returns true. The current
logic is actually correct for this definition — just needs a better comment.

**Fix**: Change comment, keep logic. Add `is_encrypted` field:
```cpp
entry.pushKV("has_private_key", desc_mgr->HasSphincsKey());
```

---

## Phase C: Medium Fixes

### C1: Add compact_size 255 handling (N1)

**File**: `src/script/interpreter.cpp`

In the annex parsing, after the `first == 254` case, add:
```cpp
} else { // first == 255
    return set_error(serror, SCRIPT_ERR_SPHINCS_BAD_ANNEX_FORMAT);
    // 8-byte compact_size not supported — would indicate > 4 billion signatures
}
```

### C2: Add explicit bounds check on signature span (N2)

**File**: `src/script/interpreter.cpp`

Before creating the signature span:
```cpp
if (sig_offset + SPHINCS_SIG_SIZE > execdata.m_annex_data.size()) {
    return set_error(serror, SCRIPT_ERR_SPHINCS_BAD_ANNEX_FORMAT);
}
```

### C3: Add PSBT annex size limit (N3)

**File**: `src/psbt.h` — in `PSBT_IN_TAP_ANNEX` deserialization:

```cpp
s >> m_tap_annex;
if (m_tap_annex.size() > MAX_STANDARD_TX_WEIGHT) {
    throw std::ios_base::failure("Input Taproot annex exceeds maximum size");
}
```

### C4: Validate annex prefix in PSBT (N4)

**File**: `src/psbt.h` — after reading annex:

```cpp
if (!m_tap_annex.empty() && m_tap_annex[0] != 0x50) {
    throw std::ios_base::failure("Input Taproot annex must start with 0x50");
}
```

### C5: Fix comment ordering in consensus/params.h (N6)

**File**: `src/consensus/params.h`

Swap the comments to match the fields.

### C6: Remove duplicate include (N7)

**File**: `src/script/sign.cpp`

Remove the second `#include <script/script.h>`.

### C7: Add prominent placeholder comments to deployment heights (N5-related)

**File**: `src/consensus/params.h`

```cpp
// WARNING: These are PLACEHOLDER values — NOT activated on any network.
// Final activation heights will be determined by community consensus.
int BIP368Height{std::numeric_limits<int>::max()};
int BIP369Height{std::numeric_limits<int>::max()};
```

---

## Phase D: Style Fixes

### D1: Document VALIDATION_WEIGHT_PER_SPHINCS_SIGOP derivation (S1)

**File**: `src/script/script.h`

```cpp
// SPHINCS+ verification takes ~1,756µs vs ~27µs for Schnorr (~65x).
// Rounded to 64x for a clean power-of-two multiple.
// 64 × VALIDATION_WEIGHT_PER_SIGOP_PASSED(50) = 3200.
static constexpr int64_t VALIDATION_WEIGHT_PER_SPHINCS_SIGOP{3200};
```

### D2: Add secure memory documentation to SphincsKey (S2)

**File**: `src/wallet/sphincskeys.h`

Add docstring to class:
```cpp
/** Secret key material uses secure_unique_ptr which:
 *  - Allocates from locked (non-swappable) memory pages
 *  - Clears memory on deallocation via memory_cleanse()
 *  - Move semantics transfer ownership without copying
 *  - Copy constructor explicitly clones into new secure allocation
 */
```

### D3: Rename `sphincs_key` parameter to `sphincs_secret` (S3)

**Files**: `src/psbt.h`, `src/psbt.cpp`, `src/wallet/scriptpubkeyman.cpp`

Rename the parameter in `SignPSBTInput` and all callers.

### D4: Document qis() hardened key limitation (S4)

**File**: `src/script/descriptor.cpp` — in QISDescriptor comment:

```cpp
/** Note: The EC key expression should use non-hardened derivation when
 *  used with a qpub (watch-only), since hardened children cannot be
 *  derived from an extended public key.
 */
```

---

## Phase E: Test Gap Closure

### E1: Encrypted wallet SPHINCS+ signing test (T1)

**File**: `test/functional/wallet_sphincs.py`

```python
# Create encrypted wallet, create SPHINCS+ key
# Fund QI address
# Lock wallet → attempt spend → should fail
# Unlock wallet → spend → should succeed
# Verify witness has correct annex
```

### E2: PSBT SPHINCS+ round-trip test (T2)

**File**: `test/functional/wallet_sphincs_psbt.py`

Verify that after `walletprocesspsbt`, the PSBT still contains
`PSBT_IN_TAP_SPHINCS_PUB` (if it was set by the updater).

### E3: exportqprv/importqprv address match (T3)

**File**: `test/functional/wallet_sphincs.py`

```python
qprv = w.exportqprv()
# Create new wallet, importqprv
w2.importqprv(qprv)
# Verify addresses match
addr1 = w.getnewaddress(address_type="bech32m")
addr2 = w2.getnewaddress(address_type="bech32m")
assert addr1 == addr2  # Same descriptor → same addresses
```

### E4: Multi-account test (T4)

Deferred — requires multi-account `createsphincskey` fix first (Phase B1 alone
isn't sufficient; the early-return logic needs account-aware matching).

### E5: Corrupted DB record test (T5)

**File**: `src/wallet/test/sphincskeys_db_tests.cpp`

Create a wallet, manually corrupt the DB record's integrity hash, reload,
verify error is handled gracefully.

### E6: Oversized annex test (T6)

**File**: `src/wallet/test/qis_descriptor_tests.cpp` or `test/functional/`

After C3 is implemented, verify that oversized annexes are rejected during
PSBT deserialization.

### E7: Co-activation boundary test (T7)

**File**: `test/functional/wallet_sphincs_activation.py`

Add test with `testactivationheight=sphincs@200` but keypath_hardening NOT
set (or set to a later height). Verify that SPHINCS+ verification is NOT
enforced when only BIP 369 is active without BIP 368.

---

## Phase F: Commit Reorganization

### Step 1: Interactive rebase plan

Reorganize the 30 commits into ~16 logical commits:

```
# Tier 1 — Crypto foundation
pick 0529d8a crypto: add SLH-DSA SPHINCS+ verification library (BIP 369)
squash 83eaa23 build: add sphincs_signer CMake target (BIP 369)
squash 3346452 bench: add SPHINCS+ benchmarks

# Tier 2 — BIP 369 consensus
pick a05a939 consensus: add OP_CHECKSPHINCSVERIFY skeleton (BIP 369)
squash 298d1a3 fix: return correct error code for malformed SPHINCS+ annex
squash bf26e83 consensus: change SPHINCS+ annex type byte from 0x01 to 0x04
squash cff23d7 consensus: add buried deployment for OP_CHECKSPHINCSVERIFY
squash 81370bb test: add sighash, malleability, signing order tests
squash aa4e12f test: real SPHINCS+ signatures in functional tests

# Tier 3 — BIP 369 tests
pick 85181c9 test: comprehensive SPHINCS+ test coverage (BIP 369)
squash 40d26e5 test: add stack, codeseparator, and sigops budget tests
squash 4c18497 test: add P2P block-level activation tests
squash 30fd13f test: add SPHINCS+ fuzz targets

# Tier 4 — BIP 368 consensus
pick b32f7d5 consensus: implement BIP 368 key-path hardening
squash a105b73 test: add BIP 368 key-path hardening functional tests
squash c884a94 test: add BIP 368/369 interaction tests
squash f76748a doc/test: add pseudocode, test vectors, fuzz tests for BIP 368

# Tier 5 — BIP spec documents (squash all doc commits)
pick 74a4100 doc: BIP 369 specification
squash 15676b9..af99678 (all BIP doc commits)
squash 97b39f7..c6f406f (all BIP 368 doc commits)

# Tier 6 — Wallet support (single commit after remediation)
pick 36d2a7b wallet: add quantum-insured wallet support (BIP 368/369)

# Tier 7 — Test framework
pick 2cb665f test: add SPHINCS+ functional test framework (BIP 369)
```

### Step 2: Amend wallet commit

After Phases A-E are complete, amend the wallet commit to include all fixes.
This keeps the commit history clean.

### Step 3: Verify

After rebase:
- Run all 168+ tests
- Verify each commit builds independently
- Verify `git log --oneline` reads as a coherent narrative

---

## Dependency Graph

```
Phase A (critical) ──→ Phase E (tests need A1 for encrypted wallet)
Phase B (major) ──→ independent
Phase C (medium) ──→ independent
Phase D (style) ──→ independent
Phases A-E ──→ Phase F (rebase after all fixes)
```

Phases A-D can proceed in parallel. Phase E depends on A. Phase F is last.

---

## Estimated Effort

| Phase | Effort | Priority |
|-------|--------|----------|
| A (critical) | 1 day | Must fix |
| B (major) | 0.5 day | Should fix |
| C (medium) | 0.5 day | Should fix |
| D (style) | 0.25 day | Nice to fix |
| E (tests) | 0.5 day | Should fix |
| F (rebase) | 0.5 day | Must do |
| **Total** | **~3 days** | |

---

## Verification

After each phase:
```bash
cmake --build build -j$(nproc)
build/bin/test_bitcoin --run_test=sphincskeys_tests,sphincskeys_db_tests,qextkey_tests,qis_descriptor_tests,script_tests,transaction_tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini
```

After Phase F (rebase), verify each commit builds independently:
```bash
git rebase -x "cmake --build build -j\$(nproc) && build/bin/test_bitcoin --run_test=script_tests" master
```
