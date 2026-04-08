# PR: Quantum-Insured Wallet Support (BIP 368/369)

## Summary

This PR adds wallet-level support for the BIP 368 (key-path hardening) and
BIP 369 (OP_CHECKSPHINCSVERIFY) soft-fork proposals, enabling users to create,
manage, and spend quantum-insured Taproot outputs using SPHINCS+ (SLH-DSA)
post-quantum signatures.

## Specifications

- [BIP 368: Taproot Key-Path Hardening](repos/bips/bip-0368.mediawiki)
- [BIP 369: OP_CHECKSPHINCSVERIFY](repos/bips/bip-0369.mediawiki)
- [BIP 395: Quantum-Insured Extended Keys](repos/bips/bip-0395.mediawiki)
- [BIP 377: PSBT Extensions for SPHINCS+](repos/bips/bip-0377.mediawiki)

## What This Adds

### Wallet Features
- **SphincsKey**: SPHINCS+ key management with secure memory, seed-based
  derivation (`HMAC-SHA512("Sphincs seed", master_ext_privkey || path)`), and
  encrypted wallet DB storage
- **QI Extended Keys** (`qpub`/`qprv`): Extended BIP 32 serialization carrying
  SPHINCS+ key material (110/142 bytes, `Q1...`/`T4...` base58 prefixes)
- **`qr()` Descriptor**: Top-level quantum-insured output descriptor —
  drop-in replacement for `tr()` that accepts a `qpub` and auto-constructs
  the hybrid SPHINCS+ tapleaf: `qr(qpub/0/*)`
- **`qis()` Descriptor**: Low-level script fragment for advanced users who
  need custom Taproot trees with SPHINCS+ leaves
- **8 New RPCs**: `createsphincskey`, `getquantumaddress`, `exportqpub`,
  `importqpub`, `exportqprv`, `importqprv`, `listsphincskeys`, `sphincsspend`
- **Full spend cycle**: Create wallet → generate QI address → receive funds →
  key-path spend with BIP 368 annex → confirmed on chain
- **Emergency spend cycle**: `sphincsspend` → QI UTXO selection → SPHINCS+
  script-path spend with hybrid tapleaf → confirmed on chain

### Signing Pipeline
- Annex-aware Schnorr sighash (`sha_annex` included when annex present)
- BIP 368 key-path annex auto-construction (34/66 bytes, type `0x02`)
- SPHINCS+ pre-signing in `SignTaproot` for hybrid scripts (type `0x04`)
- Hybrid script fallback: direct Schnorr signing when miniscript can't parse
  the `OP_CHECKSPHINCSVERIFY` hybrid pattern
- `walletprocesspsbt` accepts `sphincs_emergency` flag for PSBT workflows
- Two-pass SPKM iteration: SPHINCS+ SPKMs sign first when emergency mode set
- Activation-aware verification flags for SPHINCS+ script-path witnesses
- Activation-aware: annex only included when BIP 368 deployment is active

### Consensus
- BIP 369 co-activation requirement: `SCRIPT_VERIFY_CHECKSPHINCSVERIFY` gated
  on both `DEPLOYMENT_SPHINCS` and `DEPLOYMENT_KEYPATH_HARDENING`

### PSBT
- 3 new input field types: `PSBT_IN_TAP_SPHINCS_PUB` (0x1d),
  `PSBT_IN_TAP_SPHINCS_SIG` (0x1e), `PSBT_IN_TAP_ANNEX` (0x1f)
- 1 new output field type: `PSBT_OUT_TAP_SPHINCS_PUB` (0x09)
- SPHINCS+ key threading: `FillPSBT` → `SignPSBTInput` → `sigdata`

### Policy
- BIP 368/369 annexes (type `0x02`/`0x04`) are standard in relay policy

## Files Changed

**12 new files**, **16 modified files** in `repos/bitcoin/`

### New
| File | Description |
|------|-------------|
| `src/wallet/sphincskeys.h/.cpp` | SphincsKey class |
| `src/wallet/qextkey.h/.cpp` | QExtPubKey/QExtKey + base58 encode/decode |
| `src/wallet/rpc/sphincs.cpp` | 7 wallet RPCs |
| `src/wallet/test/sphincskeys_tests.cpp` | 13 unit tests |
| `src/wallet/test/sphincskeys_db_tests.cpp` | 2 DB persistence tests |
| `src/wallet/test/qextkey_tests.cpp` | 13 unit tests |
| `src/wallet/test/qis_descriptor_tests.cpp` | 6 unit tests |
| `test/functional/wallet_sphincs.py` | 21 functional tests |
| `test/functional/wallet_sphincs_psbt.py` | 6 PSBT tests |
| `test/functional/wallet_sphincs_activation.py` | 4 activation tests |
| `test/functional/wallet_sphincs_scriptpath.py` | 3 script-path tests |
| `doc/quantum-insured-wallet.md` | Documentation |

### Modified
| File | Changes |
|------|---------|
| `src/script/descriptor.cpp` | QISDescriptor class + `qis()` parser |
| `src/script/sign.h/.cpp` | Annex-aware signing, SPHINCS+ pre-signing |
| `src/script/signingprovider.h/.cpp` | TaprootSpendData sphincs_keys |
| `src/psbt.h/.cpp` | PSBT field types, SignPSBTInput sphincs_key param |
| `src/validation.cpp` | Co-activation enforcement |
| `src/policy/policy.cpp` | BIP 368/369 annexes standard |
| `src/kernel/chainparams.h/.cpp` | QI version bytes |
| `src/wallet/scriptpubkeyman.h/.cpp` | SPHINCS+ key storage + FillPSBT |
| `src/wallet/walletdb.h/.cpp` | DB constants + load/write handlers |
| `src/wallet/rpc/wallet.cpp` | RPC registration |
| `src/wallet/CMakeLists.txt` | Build system |
| `test/functional/test_runner.py` | Test registration |

## Test Results

| Category | Tests | Status |
|----------|-------|--------|
| Unit: sphincskeys | 13 | Pass |
| Unit: sphincskeys_db | 2 | Pass |
| Unit: qextkey | 13 | Pass |
| Unit: qis_descriptor | 6 | Pass |
| Unit: script/transaction/scriptpubkeyman | 35 | Pass |
| Functional: feature_sphincs | 43 | Pass |
| Functional: feature_keypath_hardening | 13 | Pass |
| Functional: wallet_sphincs | 21 | Pass |
| Functional: wallet_sphincs_psbt | 6 | Pass |
| Functional: wallet_sphincs_activation | 4 | Pass |
| Functional: wallet_sphincs_scriptpath | 3 | Pass |
| **Total** | **159** | **All pass** |

## Review Guidance

Suggested review order:
1. BIP specs in `repos/bips/` for context
2. `src/wallet/sphincskeys.h/.cpp` — core key management
3. `src/wallet/qextkey.h/.cpp` — extended key serialization
4. `src/script/descriptor.cpp` — `qis()` descriptor fragment
5. `src/script/sign.h/.cpp` — annex-aware signing pipeline
6. `src/psbt.h/.cpp` — PSBT field extensions
7. `src/wallet/rpc/sphincs.cpp` — user-facing RPCs
8. Functional tests for integration behavior

## Breaking Changes

None. All changes are additive. Existing wallet behavior is unchanged.
