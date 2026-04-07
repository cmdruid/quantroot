# Wallet Support for BIP 368 & BIP 369

- Status: proposed
- Date: 2026-04-03
- Owner: cmdruid

## Inputs

- [Taproot key-path hardening draft](../../repos/bips/bip-0368.mediawiki) — key-path hardening
- [OP_CHECKSPHINCSVERIFY draft](../../repos/bips/bip-0369.mediawiki) — OP_CHECKSPHINCSVERIFY
- [HANDOFF.md](../../HANDOFF.md) — remaining work: "Wallet support — key
  management, NUMS address generation, full insurance construction UX"
- Consensus implementation on `quantroot` branch (`repos/bitcoin`)

## Supporting BIPs

This plan requires two new draft BIPs to standardize wallet-layer features:

### BIP 395: HMAC-Based HD Key Derivation (HD-HMAC)

**Problem**: SPHINCS+ keys cannot use BIP32 derivation (no elliptic curve
algebra). Wallets need a standard way to derive SPHINCS+ keypairs from a master
seed so that keys are recoverable from a backup.

**Design**: Single-call HMAC derivation. No chained levels, no public
derivation, no chain codes. All derivation is effectively hardened.

```
child_seed = HMAC-SHA512("Bitcoin seed", master_secret || path_bytes)[:48]
(sk, pk)   = SphincsKeygen(child_seed)
```

- **Master secret**: the wallet's existing BIP39/BIP32 seed (or a dedicated
  SPHINCS+ master secret).
- **HMAC key**: the literal string `"Bitcoin seed"` (12 bytes), matching BIP 32.
  The master secret and path are concatenated as the HMAC message. Domain
  separation from BIP 32 is provided by the path bytes appended to the master
  secret (BIP 32 passes only the raw seed as the message).
- **Path encoding**: uses BIP 32's exact encoding — each level is a 4-byte
  big-endian uint32 with bit 0x80000000 set for hardened indices, concatenated.
  Path `m/86'/0'/0'/0/7` encodes as
  `0x80000056 || 0x80000000 || 0x80000000 || 0x00000000 || 0x00000007`
  (20 bytes). HD-HMAC does not distinguish hardened from unhardened (all
  derivation is equally opaque), but preserving the hardened bit ensures a
  BIP 32 path string always maps to the same byte representation. This enables
  **companion key** derivation: the same path (e.g., `m/86'/0'/0'/0/7`)
  produces a secp256k1 key via BIP 32 and a SPHINCS+ key via HD-HMAC, which
  is useful when both signatures are needed for the same UTXO.
- **HMAC-SHA512**: produces 64 bytes; truncated to 48 bytes (3n where n=16) to
  provide SK.seed (16), SK.prf (16), PK.seed (16) per FIPS 205.
- **SphincsKeygen**: standard SLH-DSA key generation from the 48-byte seed,
  using the `slh_dsa_bitcoin` parameter set.

**What this gives up (and why that's fine)**:

- **No public derivation / watch-only**: SPHINCS+ leaves are hidden in the MAST
  tree — you don't need to enumerate them for balance tracking. The Schnorr keys
  (BIP32) still support watch-only for the normal spending path.
- **No intermediate parent keys**: single HMAC is simpler and equally secure
  when you don't need to share subtree derivation capability.
- **No xpub equivalent**: there's no algebraic relationship between parent and
  child SPHINCS+ public keys. This is inherent to hash-based signatures.

**Spec contents**:

- [ ] Derivation function definition (HMAC-SHA512, domain tag, path encoding)
- [ ] Recommended derivation paths and companion key usage:
  - Same path as the Schnorr key (e.g., `m/86'/0'/0'/0/7`) — derives a
    companion SPHINCS+ key for the same UTXO via HD-HMAC while BIP 32 derives
    the secp256k1 key
  - Wallet constructs the hybrid tapleaf using both keys from the same path
- [ ] Seed compatibility: using BIP39 seed vs dedicated SPHINCS+ master secret
- [ ] Test vectors: master seed → path → child seed → keypair
- [ ] Security analysis: PRF properties of HMAC, independence of derived keys

**File**: `repos/bips/bip-0395.mediawiki`

### BIP 377: PSBT Extensions for SPHINCS+ and Annex Data

**Problem**: BIP 174 (PSBT) and BIP 371 (Taproot PSBT fields) predate BIP
368/369. There are no standard fields for SPHINCS+ public keys, SPHINCS+
signatures, or annex data. Hardware wallets and multi-party signing workflows
need these to round-trip correctly.

**Design**: New PSBT field types following the BIP 371 conventions. Initially
implemented as proprietary fields (`0xFC`), formalized as standard fields in
this BIP.

**Input fields**:

| Type | Key Data | Value | Description |
|------|----------|-------|-------------|
| `PSBT_IN_TAP_SPHINCS_PUB` | `<xonly>` &#124;&#124; `<leaf_hash>` | `<32-byte sphincs pubkey>` | SPHINCS+ public key for a tapleaf |
| `PSBT_IN_TAP_SPHINCS_SIG` | `<xonly>` &#124;&#124; `<leaf_hash>` | `<4080-byte signature>` | SPHINCS+ signature for a tapleaf |
| `PSBT_IN_TAP_ANNEX` | (none) | `<annex bytes>` | Assembled annex (BIP 368 type `0x02` or BIP 369 type `0x04`) |

**Output fields**:

| Type | Key Data | Value | Description |
|------|----------|-------|-------------|
| `PSBT_OUT_TAP_SPHINCS_PUB` | `<xonly>` &#124;&#124; `<leaf_hash>` | `<32-byte sphincs pubkey>` | SPHINCS+ public key in change output tapleaf |

**Signing roles** (extends BIP 174 roles):

- **Updater**: adds `PSBT_IN_TAP_SPHINCS_PUB` for inputs that have SPHINCS+
  tapleaves.
- **Signer (round 1)**: produces SPHINCS+ signatures → `PSBT_IN_TAP_SPHINCS_SIG`.
  Uses `SignatureHashSphincs` (BIP 342 sighash minus `sha_annex`).
- **Combiner**: collects SPHINCS+ signatures, builds annex →
  `PSBT_IN_TAP_ANNEX`.
- **Signer (round 2)**: produces Schnorr signature over sighash that includes
  `sha_annex` (which is now known because the annex is assembled).
- **Finalizer**: assembles witness with annex as last element.

**Spec contents**:

- [ ] Field type assignments and serialization format
- [ ] Signer/Combiner/Finalizer role updates for two-round SPHINCS+ signing
- [ ] Annex construction rules (which type byte, when to build)
- [ ] Compatibility: behavior when a participant doesn't understand SPHINCS+ fields
- [ ] Test vectors: complete PSBT round-trip for hybrid spend

**File**: `repos/bips/bip-0377.mediawiki`

## Goal

Enable the Bitcoin Core wallet to create, manage, and spend quantum-insured
Taproot outputs using BIP 368 and BIP 369. Success means a user can:

1. Generate a SPHINCS+ keypair and store it in the wallet.
2. Create a "full insurance" Taproot address (NUMS internal key + Schnorr leaf +
   SPHINCS+ leaf) using a descriptor or RPC.
3. Spend via Schnorr script-path (normal operation) with a BIP 368 annex.
4. Spend via SPHINCS+ script-path (post-activation) with a BIP 369 annex.
5. Round-trip through PSBT for hardware wallet / multi-party workflows.

## Implementation Changes

### Workstream 1: SPHINCS+ Key Management (BIP 395)

**Goal**: Wallet can derive, store, encrypt, import, and back up SPHINCS+ keys
using HD-HMAC derivation from the wallet's master seed.

**Context**: The wallet only knows secp256k1 keys today. SPHINCS+ keys (64-byte
secret, 32-byte public) cannot use BIP32 derivation. BIP 395 defines a simple
HMAC-SHA512 scheme to derive SPHINCS+ keys from the existing wallet seed.

**Changes**:

- [ ] Implement HD-HMAC derivation per BIP 395:
  ```
  child_seed = HMAC-SHA512("Bitcoin seed", master_secret || path_bytes)[:48]
  (sk, pk)   = SphincsKeygen(child_seed)
  ```
- [ ] New `SphincsKey` class (parallel to `CKey`/`CPubKey`) wrapping the
  `SphincsKeygen` / `SphincsSign` API in `src/crypto/sphincsplus.h`.
- [ ] HD-HMAC key provider: derives keys at path
  `m/368'/coin_type'/account'/index'` from the wallet's BIP39 seed.
- [ ] Extend `WalletDB` with new record types:
  - `SPHINCSKEY` — unencrypted SPHINCS+ secret key (64 bytes) + public key (32
    bytes).
  - `SPHINCSCKEY` — encrypted SPHINCS+ secret key (same schema as
    `WALLETDESCRIPTORCKEY`).
- [ ] Key metadata: creation time, label, derivation path, descriptor index.
- [ ] `importsphincskey` support for externally-generated standalone keys (not
  HD-derived).
- [ ] Backup/recovery: HD-derived keys are recoverable from the BIP39 seed +
  derivation path. Imported standalone keys must be backed up separately.

**Files**: `wallet/walletdb.h`, `wallet/walletdb.cpp`, new
`wallet/sphincskeys.h/.cpp`, `crypto/sphincsplus.h`

**Dependencies**: None (can start immediately).

---

### Workstream 2: Descriptor Extensions

**Goal**: Express SPHINCS+ tapleaves in the `tr()` descriptor syntax.

**Context**: `TRDescriptor` already builds MAST trees via `TaprootBuilder`. The
descriptor parser needs a new key expression for SPHINCS+ public keys, and the
script generator needs to emit `OP_CHECKSPHINCSVERIFY` scripts.

**Changes**:

- [ ] New `sphincs()` key expression provider in the descriptor parser, accepting
  a 32-byte hex SPHINCS+ public key.
- [ ] Script generation: `sphincs(KEY)` expands to
  `<KEY> OP_CHECKSPHINCSVERIFY OP_DROP 1`.
- [ ] Two canonical descriptor templates:
  - **Full insurance**:
    `tr(NUMS, {pk(schnorr_xonly), sphincs(sphincs_pub)})`
  - **Combined hybrid**:
    `tr(schnorr_xonly, {and_v(v:pk(schnorr_xonly), sphincs(sphincs_pub))})`
    or a new `hybrid()` fragment.
- [ ] Extend `TaprootSpendData` to carry SPHINCS+ public key per leaf so the
  signing flow knows which leaves need SPHINCS+ signatures.
- [ ] NUMS internal key constant available as a well-known descriptor key
  (e.g., `tr(NUMS, ...)` recognized by the parser).

**Files**: `script/descriptor.cpp`, `script/signingprovider.h`

**Dependencies**: Workstream 1 (key type must exist).

---

### Workstream 3: Annex Construction & Signing

**Goal**: The signing flow can construct BIP 368/369 annexes and produce valid
witnesses with correct signing order.

**Context**: This is the hardest workstream. The wallet currently hardcodes
`m_annex_present = false` in `sign.cpp`. The entire signing pipeline —
`SignatureData`, `ProduceSignature`, `SignStep`, `CreateSchnorrSig` — must become
annex-aware. BIP 369 also imposes a strict signing order (SPHINCS+ first, then
Schnorr).

**Changes**:

#### 3a: BIP 368 — Key-path annex (internal key disclosure)

- [ ] When key-path spending post-activation, build annex:
  `0x50 || 0x02 || P` (34 bytes, no script tree) or
  `0x50 || 0x02 || P || merkle_root` (66 bytes, with script tree).
- [ ] Internal key `P` is already in `TaprootSpendData::internal_key`; merkle
  root is in `TaprootSpendData::merkle_root`.
- [ ] Inject annex into `PrecomputedTransactionData` so the Schnorr sighash
  includes `sha_annex`.

#### 3b: BIP 369 — SPHINCS+ annex (script-path signatures)

- [ ] Build annex: `0x50 || 0x04 || compact_size(N) || sig_1 || ... || sig_N`.
- [ ] Enforce signing order:
  1. Compute SPHINCS+ sighash via `SignatureHashSphincs()` (BIP 342 sighash
     without `sha_annex`).
  2. Sign all SPHINCS+ signatures via `SphincsSign()`.
  3. Assemble annex from signatures.
  4. Compute Schnorr sighash via standard BIP 342 (includes `sha_annex`).
  5. Sign Schnorr.
- [ ] Handle hybrid scripts: detect `OP_CHECKSPHINCSVERIFY` in the spending
  script and count how many SPHINCS+ signatures are needed.

#### 3c: Signing pipeline changes

- [ ] Remove `execdata.m_annex_present = false` hardcoding in `sign.cpp`.
- [ ] Add `std::optional<std::vector<uint8_t>> annex` to `SignatureData`.
- [ ] Update `ProduceSignature()` to accept / pass through annex data.
- [ ] Update `MutableTransactionSignatureCreator::CreateSchnorrSig()` to
  populate `m_annex_*` fields in `ScriptExecutionData` when annex is present.

**Files**: `script/sign.cpp`, `script/sign.h`, `script/interpreter.cpp`

**Dependencies**: None (can start in parallel with Workstream 1).

---

### Workstream 4: PSBT Extensions (BIP 377)

**Goal**: SPHINCS+ data and annex contents can round-trip through PSBTs for
hardware wallet and multi-party signing workflows.

**Context**: No standard PSBT fields exist for annex or SPHINCS+ data. BIP 371
defines Taproot PSBT fields but predates BIP 368/369. BIP 377 defines new
field types following BIP 371 conventions.

**Changes**:

- [ ] New PSBT input fields per BIP 377:
  - `PSBT_IN_TAP_SPHINCS_PUB` — SPHINCS+ public key, keyed by `(xonly_pk,
    leaf_hash)` (same pattern as `PSBT_IN_TAP_SCRIPT_SIG`).
  - `PSBT_IN_TAP_SPHINCS_SIG` — SPHINCS+ signature (4,080 bytes), keyed by
    `(xonly_pk, leaf_hash)`.
  - `PSBT_IN_TAP_ANNEX` — assembled annex bytes (BIP 368 or 369).
- [ ] New PSBT output field:
  - `PSBT_OUT_TAP_SPHINCS_PUB` — SPHINCS+ public key in change output tapleaf.
- [ ] Extend `PSBTInput` / `PSBTOutput` structs with `m_sphincs_*` fields.
- [ ] Update `FillSignatureData()` / `FromSignatureData()` to bridge SPHINCS+
  data between PSBT and `SignatureData`.
- [ ] Implement two-round signing roles per BIP 377:
  - Round 1 (Signer): produces SPHINCS+ signatures →
    `PSBT_IN_TAP_SPHINCS_SIG`.
  - Combiner: collects SPHINCS+ sigs, builds annex → `PSBT_IN_TAP_ANNEX`.
  - Round 2 (Signer): produces Schnorr signature (sighash now includes
    `sha_annex`).
  - Finalizer: assembles witness with annex as last element.
- [ ] Start with proprietary field prefix (`0xFC`) for development; switch to
  assigned type bytes once BIP 377 is accepted.

**Files**: `psbt.h`, `psbt.cpp`

**Dependencies**: Workstream 3 (signing flow must support annex).

---

### Workstream 5: Witness Finalization

**Goal**: Final transaction witnesses are correctly assembled with annex in the
right position.

**Context**: The annex is the last witness element (identified by the `0x50`
prefix) and must appear in the correct position for both key-path and script-path
spends.

**Changes**:

- [ ] Key-path witness (BIP 368):
  `[schnorr_sig] [annex]`
  where annex = `0x50 || 0x02 || P [|| merkle_root]`.
- [ ] Script-path witness (BIP 369 hybrid):
  `[schnorr_sig] [sphincs_pk] [script] [control_block] [annex]`
  where annex = `0x50 || 0x04 || compact_size(N) || sig_1 ... sig_N`.
- [ ] Update `ProduceSignature()` witness assembly to append annex as last
  element.
- [ ] Update `SignStep()` to recognize SPHINCS+ leaves and route through the
  annex signing path.

**Files**: `script/sign.cpp`, `script/interpreter.cpp`

**Dependencies**: Workstream 3.

---

### Workstream 6: RPCs

**Goal**: Users can create and spend quantum-insured outputs via wallet RPCs.

**Changes**:

- [ ] `createsphincskey` — generate a SPHINCS+ keypair, store in wallet, return
  the 32-byte public key hex.
- [ ] `importsphincskey` — import an existing SPHINCS+ secret key.
- [ ] `getquantumaddress` (or extend `getnewaddress`) — create a quantum-insured
  Taproot address. Parameters:
  - `construction`: `"full_insurance"` (default) or `"hybrid"`
  - `schnorr_key`: optional, defaults to next HD-derived key
  - `sphincs_key`: optional, defaults to last created SPHINCS+ key
- [ ] Existing spending RPCs (`sendtoaddress`, `walletcreatefundedpsbt`,
  `signrawtransactionwithwallet`) should work once the signing flow is wired up
  — no changes expected beyond what Workstreams 3–5 provide.
- [ ] `listsphincskeys` — enumerate stored SPHINCS+ keys with labels and
  associated addresses.

**Files**: new `wallet/rpc/sphincs.cpp`, `wallet/rpc/addresses.cpp`,
`wallet/rpc/spend.cpp`

**Dependencies**: Workstreams 1, 2, 3.

---

## Dependency Graph

```
BIP 395 (HD-HMAC spec) ────→ Workstream 1 (Key Management) ──┐
                                                                   │
                                  Workstream 2 (Descriptors) ◄─────┤
                                         │                         │
                                         ├─────────────────────────┼──→ Workstream 6 (RPCs)
                                         │                         │
BIP 377 (PSBT spec) ──────────→ Workstream 4 (PSBT) ◄───────────┤
                                                                   │
                                  Workstream 3 (Signing) ──────────┤
                                         │                         │
                                         └──→ Workstream 5 (Witness)
```

**Parallel tracks**:
- BIP drafting (395 + 377) can happen before any code.
- Workstreams 1 and 3 can start in parallel once their BIP specs are drafted.
- Workstream 3 (annex construction and signing) is the critical path and the
  most complex piece.

## Validation

### BIP Specs

- [ ] BIP 395 (HD-HMAC): draft spec with derivation function, recommended
  paths, seed compatibility, test vectors, security analysis
- [ ] BIP 377 (PSBT-SPHINCS): draft spec with field types, signing roles,
  annex construction rules, compatibility, test vectors

### Unit Tests

- [ ] HD-HMAC derivation: master seed → path → child seed → keypair
  (deterministic, matches test vectors from BIP 395)
- [ ] SPHINCS+ key serialization / deserialization round-trip
- [ ] Descriptor parsing: `tr(NUMS, {pk(KEY), sphincs(KEY)})` parses and
  generates correct scriptPubKey
- [ ] Annex construction: correct format for BIP 368 (type `0x02`) and BIP 369
  (type `0x04`)
- [ ] Signing order enforcement: SPHINCS+ sighash excludes `sha_annex`, Schnorr
  sighash includes it
- [ ] PSBT round-trip: SPHINCS+ fields serialize/deserialize correctly per
  BIP 377

### Functional Tests

- [ ] `wallet_sphincs.py`: key generation, address creation, send/receive cycle
  for both construction types
- [ ] `wallet_sphincs_psbt.py`: PSBT round-trip (create, fill SPHINCS+, fill
  Schnorr, finalize, broadcast)
- [ ] `wallet_sphincs_activation.py`: spending behavior before and after
  soft-fork activation
- [ ] Integration with existing `feature_sphincs.py` and
  `feature_keypath_hardening.py` test suites

### Manual Verification

- [ ] Create full-insurance address, fund it, spend via Schnorr leaf on regtest
- [ ] Activate BIP 369, spend via SPHINCS+ leaf on regtest
- [ ] Activate BIP 368, verify key-path spend includes annex on regtest
- [ ] PSBT export/import with hardware wallet simulator

## Archive Condition

Move this plan to `../archive/` when all workstreams are completed and tests
pass, or superseded by a revised plan.
