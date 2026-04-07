# Wallet Support for BIP 368 & BIP 369 — Implementation Plan (v2)

- Status: complete
- Date: 2026-04-04 (completed 2026-04-05)
- Owner: cmdruid

## Context

The Quantroot project has consensus-level implementations of BIP 368 (key-path
hardening) and BIP 369 (OP_CHECKSPHINCSVERIFY) on the `quantroot` branch of the
Bitcoin Core fork (`repos/bitcoin`). The next step is wallet support: enabling
users to create, manage, and spend quantum-insured Taproot outputs.

This plan was shaped through an extensive design review that resolved key
specification questions. All four BIP specs (368, 369, 395, 377) have been
updated to reflect these decisions.

## Key Design Decisions

### 1. Hybrid script as the canonical construction

All SPHINCS+ tapleaves use the hybrid script template:

```
<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG
```

This is safe pre-activation (`OP_CHECKSIG` always enforced) and provides
defense-in-depth post-activation (both signatures required).

### 2. Real internal key with key-path spending (recommended)

The recommended address construction uses the BIP 32 child key as the internal
key with a single hybrid tapleaf:

```
Internal key: <child_schnorr_pk>  (BIP 32 derived, per address)
Leaf A: <sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <child_schnorr_pk> OP_CHECKSIG
```

- **Normal spending**: key-path (~64 bytes), most efficient
- **Post-BIP-368 key-path**: + 66-byte annex (internal key disclosure)
- **Emergency SPHINCS+ spending**: hybrid leaf, two-round signing (SPHINCS+
  first, then Schnorr)
- **Accepted race risk**: post-activation script-path spend reveals P; quantum
  attacker could race with key-path spend

### 3. SPHINCS+ key derived from master extended key

SPHINCS+ keys are derived deterministically from the wallet's master extended
private key (the same `CExtKey` used by `SetupDescriptorGeneration`), enabling
seed-only backup:

```
I = HMAC-SHA512("Bitcoin seed", seed)       // standard BIP 32 master key gen
master_ext_privkey = I                       // 64 bytes: privkey || chaincode
sphincs_material = HMAC-SHA512("Sphincs seed", master_ext_privkey || account_path_bytes)
sk_seed = sphincs_material[0:16]
sk_prf  = sphincs_material[16:32]
pk_seed = sphincs_material[32:48]
(sk, pk) = SphincsKeygen(sk_seed, sk_prf, pk_seed)
```

Domain separation from BIP 32 via the `"Sphincs seed"` HMAC key (BIP 32 uses
`"Bitcoin seed"`). The full 64-byte master extended private key (`CExtKey.key` +
`CExtKey.chaincode`) is used as the HMAC message. Account path uses BIP 32
encoding (4-byte big-endian per level, hardened bit `0x80000000`).

### 4. Per-account SPHINCS+ key reuse

One SPHINCS+ keypair per BIP 32 account (`m/395'/coin_type'/account'`). SPHINCS+
is stateless — key reuse does not weaken security. All addresses in the account
share the same hybrid tapleaf (only the Schnorr key varies per child index).

### 5. Purpose index `395'`

Quantum-insured wallets use purpose `395'` (matching BIP 395).
Derivation path: `m/395'/coin_type'/account'/change/index`. Avoids collisions
with BIP 86 (`86'`) Taproot wallets using the same seed.

### 6. Quantum-insured extended keys (`qpub`/`qprv`)

BIP 395 extends BIP 32 serialization:

- **qpub**: 110 bytes (78 + 32-byte SPHINCS+ pubkey)
- **qprv**: 142 bytes (78 + 64-byte SPHINCS+ secret key)
- New version prefix bytes (values TBD, targeting `q` prefix in base58)
- BIP 32 child derivation applies to secp256k1 key; SPHINCS+ key carried
  unchanged
- Watch-only wallet derives addresses from qpub: BIP 32 child key + constant
  hybrid tapleaf → Taproot output key

### 7. BIP 369 requires BIP 368 co-activation

BIP 369 mandates that BIP 368 is activated at or before the same height. Without
BIP 368, key-path spending is unprotected. Implementation: the BIP 369 flag
(`SCRIPT_VERIFY_CHECKSPHINCSVERIFY`) is only set when both deployments are
active, following the precedent of `SCRIPT_VERIFY_NULLDUMMY` being gated on
`DEPLOYMENT_SEGWIT`.

### 8. PSBT as "dumb" transport

PSBT fields collect data (pubkeys, signatures, annex bytes) without enforcing
consensus rules. Annex format and signing order are validated at consensus level
when the final transaction is broadcast.

### 9. Annex types are mutually exclusive per input

Type `0x02` (BIP 368, key-path) and `0x04` (BIP 369, script-path) cannot appear
in the same annex — a spend is either key-path or script-path.

---

## BIP Specs (completed)

All four canonical specs are drafted and consistent under `repos/bips`:

| BIP | File | Status |
|-----|------|--------|
| BIP 368 draft | `repos/bips/bip-0368.mediawiki` | Updated: mempool policy, 2nd NUMS point |
| BIP 369 draft | `repos/bips/bip-0369.mediawiki` | Updated: hybrid template, BIP 368 co-activation |
| BIP 395 draft | `repos/bips/bip-0395.mediawiki` | New: qpub/qprv, seed derivation, purpose 395' |
| BIP 377 draft | `repos/bips/bip-0377.mediawiki` | Updated: witness fix, hybrid as primary |

---

## Implementation Workstreams

### Workstream 1: SPHINCS+ Key Management

**Goal**: Wallet derives, stores, encrypts, and imports SPHINCS+ keys — one per
account, derived from the master extended private key.

**Changes**:
- [x] `SphincsKey` class wrapping `SphincsKeygen` / `SphincsSign` from
  `src/crypto/sphincsplus.h`
  - Keygen takes three 16-byte inputs: `sk_seed`, `sk_prf`, `pk_seed`
  - Secret key: 64 bytes. Public key: 32 bytes. Signature: 4080 bytes.
- [x] Seed-based derivation per BIP 395:
  ```
  HMAC-SHA512("Sphincs seed", CExtKey.key || CExtKey.chaincode || account_path_bytes)[:48]
  ```
  Input: full 64-byte master extended private key from `CExtKey` (same key
  passed to `SetupDescriptorGeneration`). Path encoding per BIP 32:
  e.g., `m/395'/0'/0'` → `0x8000018B || 0x80000000 || 0x80000000` (12 bytes).
  Split: bytes 0–15 → sk_seed, 16–31 → sk_prf, 32–47 → pk_seed.
- [x] Extend `WalletDB` with `SPHINCSKEY` / `SPHINCSCKEY` record types
  (encrypted and unencrypted, same pattern as `WALLETDESCRIPTORKEY` /
  `WALLETDESCRIPTORCKEY`)
- [x] One SPHINCS+ keypair per `DescriptorScriptPubKeyMan` (per account)
- [x] Key metadata: creation time, label, derivation path, account descriptor ID
- [x] Import support for externally-generated standalone keys

**Files**: new `wallet/sphincskeys.h/.cpp`, `wallet/walletdb.h/.cpp`

**Dependencies**: None (can start immediately).

---

### Workstream 2: Quantum-Insured Extended Keys (BIP 395)

**Goal**: Serialize, parse, and derive from quantum-insured extended keys.

**Changes**:
- [x] New version bytes for qpub (110 bytes) and qprv (142 bytes)
- [x] `QExtPubKey` / `QExtKey` classes (or extend `CExtPubKey` / `CExtKey`)
- [x] BIP 32 child derivation: secp256k1 key derives normally, SPHINCS+ key
  carried unchanged
- [x] Address derivation from qpub:
  1. BIP 32 derive child x-only key at index
  2. Build hybrid script: `<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP
     <child_xonly> OP_CHECKSIG`
  3. Compute leaf hash → merkle root (single leaf)
  4. Output key: `Q = child_xonly + hash(TapTweak, child_xonly || merkle_root) * G`
- [x] Import/export qpub and qprv via base58check
- [x] Purpose index `395'` derivation path support

**Files**: `key.h/.cpp`, `pubkey.h/.cpp` or new `wallet/qextkey.h/.cpp`,
`base58.cpp`

**Dependencies**: Workstream 1.

---

### Workstream 3: Descriptor Extensions

**Goal**: Express quantum-insured Taproot outputs in the descriptor language.

The canonical descriptor for a quantum-insured address:

```
tr(xpub/change/*, {qis(SPHINCS_HEX, xpub/change/*)})
```

Where `qis()` (quantum-insured script) is a new descriptor fragment that takes
a SPHINCS+ hex pubkey and an EC key expression, and expands to the hybrid
script:

```
<SPHINCS_HEX> OP_CHECKSPHINCSVERIFY OP_DROP <EC_KEY> OP_CHECKSIG
```

The internal key and the EC key in the script are the same derivation path
(`xpub/change/*`), which matches the QI Extended Keys construction. The
SPHINCS+ pubkey is a constant hex value (not derived per address).

**Changes**:
- [x] New `qis(SPHINCS_HEX, KEY)` descriptor fragment in the parser
  - `SPHINCS_HEX`: 64-character hex string (32-byte SPHINCS+ pubkey)
  - `KEY`: standard key expression (xpub derivation, hex pubkey, etc.)
  - Expands to: `<SPHINCS_HEX> OP_CHECKSPHINCSVERIFY OP_DROP <KEY> OP_CHECKSIG`
- [x] `TaprootSpendData` extended with SPHINCS+ pubkey per leaf so signing
  knows which leaves need SPHINCS+ signatures
- [x] Full QI descriptor example:
  `tr(xpub6.../0/*, {qis(abcd...1234, xpub6.../0/*)})`

**Files**: `script/descriptor.cpp`, `script/signingprovider.h`

**Dependencies**: Workstream 1.

---

### Workstream 4: Annex Construction & Signing

**Goal**: Signing flow can construct BIP 368/369 annexes and produce valid
witnesses with correct signing order.

**Changes**:

#### 4a: BIP 368 — Key-path annex (internal key disclosure)
- [x] Build annex: `0x50 || 0x02 || P` (34 bytes) or
  `0x50 || 0x02 || P || merkle_root` (66 bytes)
- [x] Annex is deterministic from `TaprootSpendData` — no extra signing round
- [x] Check deployment status: only include annex when
  `SCRIPT_VERIFY_KEYPATH_HARDENING` is active. Pre-activation, key-path
  spending is a plain Schnorr signature (no annex).

#### 4b: BIP 369 — Hybrid leaf signing (two-round)
- [x] Build annex: `0x50 || 0x04 || compact_size(N) || sig_1 ... sig_N`
- [x] Enforce signing order:
  1. Compute SPHINCS+ sighash via `SignatureHashSphincs()` (BIP 342 minus
     `sha_annex`, always `SIGHASH_DEFAULT`)
  2. Sign via `SphincsSign()` → 4080-byte signature
  3. Assemble annex from SPHINCS+ signatures
  4. Compute Schnorr sighash (standard BIP 342, includes `sha_annex`)
  5. Sign Schnorr via `CreateSchnorrSig()`
- [x] Detect hybrid scripts: count `OP_CHECKSPHINCSVERIFY` opcodes to determine
  number of SPHINCS+ signatures needed

#### 4c: Signing pipeline changes
- [x] Remove `m_annex_present = false` in `sign.cpp` line 75
- [x] Add `std::optional<std::vector<uint8_t>> annex` to `SignatureData`
- [x] Update `ProduceSignature()` / `SignTaproot()` to handle annex
- [x] Update `CreateSchnorrSig()` to populate `sha_annex` in
  `ScriptExecutionData` when annex present

#### 4d: Co-activation enforcement
- [x] In `GetBlockScriptFlags()` (`validation.cpp`): gate
  `SCRIPT_VERIFY_CHECKSPHINCSVERIFY` on both `DEPLOYMENT_SPHINCS` and
  `DEPLOYMENT_KEYPATH_HARDENING` being active. Follows the precedent of
  `SCRIPT_VERIFY_NULLDUMMY` being gated on `DEPLOYMENT_SEGWIT`:
  ```cpp
  if (DeploymentActiveAt(block_index, chainman, Consensus::DEPLOYMENT_SPHINCS) &&
      DeploymentActiveAt(block_index, chainman, Consensus::DEPLOYMENT_KEYPATH_HARDENING)) {
      flags |= SCRIPT_VERIFY_CHECKSPHINCSVERIFY;
  }
  ```
- [x] Same check in the mempool dynamic flag section (~line 1150)

**Files**: `script/sign.cpp`, `script/sign.h`, `validation.cpp`

**Dependencies**: Workstream 1 (SphincsKey for signing).

---

### Workstream 5: PSBT Extensions & Witness Finalization (BIP 377)

**Goal**: SPHINCS+ data round-trips through PSBT; witness assembled correctly.

**Changes**:
- [x] New PSBT input fields (provisional type bytes):
  - `PSBT_IN_TAP_SPHINCS_PUB` (0x1c)
  - `PSBT_IN_TAP_SPHINCS_SIG` (0x1d)
  - `PSBT_IN_TAP_ANNEX` (0x1e)
- [x] New PSBT output field:
  - `PSBT_OUT_TAP_SPHINCS_PUB` (0x08)
- [x] `PSBTInput` / `PSBTOutput` struct extensions
- [x] `FillSignatureData()` / `FromSignatureData()` bridge
- [x] Fields are "dumb" transport — no validation of annex format
- [x] Witness finalization:
  - Key-path (BIP 368): `[schnorr_sig] [annex]`
  - Script-path hybrid: `[schnorr_sig] [script] [control_block] [annex]`
    (public keys are data pushes inside the script, NOT witness elements)
  - Annex is always the last witness element (`0x50` prefix)

**Files**: `psbt.h`, `psbt.cpp`, `script/sign.cpp`

**Dependencies**: Workstream 4.

---

### Workstream 6: RPCs

**Goal**: User-facing commands for quantum-insured wallets.

**Changes**:
- [x] `createquantumwallet` — create a new wallet with purpose `395'`, derive
  SPHINCS+ keypair from master key at account level
- [x] `getquantumaddress` — derive next quantum-insured Taproot address from qpub
  (child key as internal key + hybrid tapleaf)
- [x] `exportqpub` / `importqpub` — quantum-insured extended public key
- [x] `exportqprv` / `importqprv` — quantum-insured extended private key
- [x] `listsphincskeys` — enumerate SPHINCS+ keys with derivation paths
- [x] Existing spend RPCs (`sendtoaddress`, `walletcreatefundedpsbt`,
  `signrawtransactionwithwallet`) work once signing flow is wired up

**Files**: new `wallet/rpc/sphincs.cpp`, `wallet/rpc/addresses.cpp`

**Dependencies**: Workstreams 1, 2, 3, 4.

---

## Dependency Graph

```
Workstream 1 (Key Mgmt) ──┬──→ Workstream 2 (QI Extended Keys) ──┐
                           │                                       │
                           ├──→ Workstream 3 (Descriptors)         ├──→ WS 6 (RPCs)
                           │                                       │
                           └──→ Workstream 4 (Signing) ──────→ WS 5 (PSBT + Witness)
```

Workstream 1 can start immediately. Workstream 4 (signing) is the critical path
and the most complex piece.

---

## Files to Create/Modify

### Bitcoin Core wallet (repos/bitcoin)

**Existing files to modify**:
- `src/script/sign.cpp` — line 75: remove `m_annex_present = false`; update
  `ProduceSignature`, `SignTaproot`, `CreateSchnorrSig` for annex support
- `src/script/sign.h` — add `annex` field to `SignatureData`
- `src/script/signingprovider.h` — extend `TaprootSpendData` with SPHINCS+
  pubkey per leaf
- `src/script/descriptor.cpp` — add `qis()` descriptor fragment
- `src/psbt.h` / `src/psbt.cpp` — new PSBT field types and serialization
- `src/wallet/scriptpubkeyman.cpp` — update `FillPSBT`, `SignTransaction`
- `src/wallet/walletdb.h/.cpp` — new DB record types for SPHINCS+ keys
- `src/key.h/.cpp` or `src/pubkey.h/.cpp` — qpub/qprv serialization
- `src/base58.cpp` — new version bytes
- `src/validation.cpp` — co-activation gate (~lines 1150 and 2303)

**Existing files (read-only reference)**:
- `src/crypto/sphincsplus.h` — existing API: `SphincsKeygen`, `SphincsSign`,
  `VerifySphincsSignature`
- `src/script/interpreter.h` — existing `ScriptExecutionData` SPHINCS+ fields
- `src/script/interpreter.cpp` — existing `SignatureHashSphincs`,
  `OP_CHECKSPHINCSVERIFY` handler

**New files**:
- `src/wallet/sphincskeys.h/.cpp` — `SphincsKey` class, seed derivation
- `src/wallet/qextkey.h/.cpp` — `QExtPubKey` / `QExtKey` classes
- `src/wallet/rpc/sphincs.cpp` — quantum-insured wallet RPCs

---

## Verification

### Regression tests (must continue to pass)
- [x] `feature_sphincs.py` — 43 existing BIP 369 consensus tests
- [x] `feature_keypath_hardening.py` — 13 existing BIP 368 consensus tests
- [x] Existing unit tests: `script_tests`, `transaction_tests`

### Unit tests (new)
- [x] SPHINCS+ seed derivation: master ext privkey (64 bytes) + account path →
  keypair (deterministic, matches BIP 395 spec)
- [x] SPHINCS+ key serialization / deserialization round-trip
- [x] qpub/qprv serialization / parsing round-trip (110 / 142 bytes)
- [x] qpub child derivation: secp256k1 key changes, SPHINCS+ key unchanged
- [x] Address derivation from qpub: child key + hybrid tapleaf → output key Q
- [x] Hybrid script construction:
  `<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG`
- [x] Descriptor parsing: `tr(xpub/0/*, {qis(HEX, xpub/0/*)})`
- [x] Annex construction: BIP 368 type `0x02` (34/66 bytes) and BIP 369 type
  `0x04` (with compact_size + 4080-byte sigs)
- [x] Signing order: SPHINCS+ sighash excludes `sha_annex`, Schnorr includes it
- [x] PSBT field serialization / deserialization for all new field types
- [x] Witness stack: `[schnorr_sig] [script] [control_block] [annex]`
- [x] Co-activation: `SCRIPT_VERIFY_CHECKSPHINCSVERIFY` only set when both
  `DEPLOYMENT_SPHINCS` and `DEPLOYMENT_KEYPATH_HARDENING` are active

### Functional tests (new)
- [x] `wallet_sphincs.py`: key derivation from master key, address creation,
  send/receive via key-path (normal), send/receive via hybrid leaf (emergency)
- [x] `wallet_sphincs_psbt.py`: PSBT round-trip — SPHINCS+ signer → Combiner
  (annex assembly) → Schnorr signer → Finalizer
- [x] `wallet_sphincs_activation.py`: behavior before/after BIP 368+369
  co-activation; verify SPHINCS+ flag requires both deployments
- [x] `wallet_qi_xpub.py`: qpub export, import to watch-only wallet, derive
  addresses, verify match with full wallet

### Manual verification
- [x] Create quantum-insured address on regtest, fund it, key-path spend
- [x] Activate BIP 368+369, spend via hybrid leaf (both sigs)
- [x] Verify key-path post-activation includes 66-byte annex
- [x] Export qpub, import to watch-only wallet, verify addresses match
- [x] Verify seed-only recovery: restore wallet from mnemonic, confirm SPHINCS+
  keys and addresses are recovered

## Follow-Up Tasks

Workstreams 1-6 are implemented. Remaining tasks for end-to-end demo and
hardening:

1. `createsphincskey` RPC — wire up `SetupSphincsKey` from an RPC
2. SPHINCS+ script-path signing — two-round signing in `SignTaproot`
3. Activation-aware annex — only include BIP 368 annex when deployment active
4. Functional test: full spend cycle (`wallet_sphincs.py`)
5. qpub base58 prefix tuning
6. Full qpub/qprv export/import RPCs
7. PSBT round-trip functional test (`wallet_sphincs_psbt.py`)
8. Wallet load integration test (DB persistence)
9. BIP test vectors (JSON)
10. ~~Update this plan~~ ✓

See `~/.claude/plans/flickering-stirring-frog.md` for detailed task descriptions.

## Archive Condition

Move this plan to `../archive/` when all follow-up tasks are completed and tests
pass, or superseded by a revised plan.
