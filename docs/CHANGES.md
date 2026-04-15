# Quantroot Changes Inventory

This document tracks all changes in the `quantroot` branches of
`repos/bitcoin` and `repos/bips` relative to their upstream base.

Last updated: 2026-04-15

---

## Summary

| Metric | Bitcoin | BIPs |
|--------|---------|------|
| Commits | 8 | 1 |
| Files changed | 81 | 8 |
| New files | 41 | 8 |
| Modified files | 40 | 0 |
| Lines added | 10,741 | 1,849 |
| Lines removed | 45 | 0 |
| **Total delta** | **+10,696** | **+1,849** |

---

## Bitcoin Core Changes (`repos/bitcoin`)

### Commit 1: `crypto: add SLH-DSA SPHINCS+ library and benchmarks`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/crypto/sphincsplus.h` | New | 51 | C++ wrapper for SPHINCS+ sign/verify |
| `src/crypto/sphincsplus.cpp` | New | 34 | Implementation |
| `src/crypto/sphincsplus/*.c,*.h` | New | 2,979 | SLH-DSA C library (FIPS 205) |
| `src/bench/sphincs.cpp` | New | 56 | Benchmark for sign/verify |
| `src/bench/CMakeLists.txt` | Mod | +1 | Register benchmark |
| `src/crypto/CMakeLists.txt` | Mod | +5 | Register library |
| `src/test/CMakeLists.txt` | Mod | +7 | Register test helper |
| `test/functional/test_framework/sphincs.py` | New | 128 | Python SPHINCS+ test helper |
| `test/functional/test_framework/sphincs_signer.cpp` | New | 104 | Native signer for tests |

**20 files, +3,286 lines**

### Commit 2: `consensus: add OP_CHECKSPHINCSVERIFY and key-path hardening`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/script/interpreter.cpp` | Mod | +213 | OP_CHECKSPHINCSVERIFY handler, annex parsing, key-path verification, SPHINCS+ sighash |
| `src/script/interpreter.h` | Mod | +34 | ScriptExecutionData fields, CheckSphincsSignature |
| `src/script/script.h` | Mod | +15 | OP_CHECKSPHINCSVERIFY opcode (0xB3), weight constant (3200) |
| `src/script/script_error.h` | Mod | +13 | SPHINCS+ error codes |
| `src/script/script_error.cpp` | Mod | +18 | Error code strings |
| `src/consensus/params.h` | Mod | +15 | DEPLOYMENT_SPHINCS, DEPLOYMENT_KEYPATH_HARDENING |
| `src/deploymentinfo.cpp` | Mod | +8 | Deployment names and BIP 9 config |
| `src/validation.cpp` | Mod | +26 | Co-activation enforcement (mempool + block) |
| `src/policy/policy.cpp` | Mod | +11 | Annex types 0x02/0x04 standard |
| `src/policy/policy.h` | Mod | +3 | Annex type constants |
| `src/kernel/chainparams.cpp` | Mod | +26 | QI version bytes, regtest buried deployment |
| `src/kernel/chainparams.h` | Mod | +2 | EXT_QI_PUBLIC_KEY/SECRET_KEY enum |
| `src/rpc/blockchain.cpp` | Mod | +2 | Deployment info RPC |

**13 files, +380 lines, -6 lines**

### Commit 3: `test: add BIP 368/369 consensus tests and fuzz targets`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `test/functional/feature_sphincs.py` | New | 1,031 | 33 test cases: opcode, annex, sighash, activation |
| `test/functional/feature_keypath_hardening.py` | New | 381 | 9 test cases: disclosure, NUMS, bare-key |
| `test/functional/test_runner.py` | Mod | +5 | Register test files |
| `test/functional/test_framework/script.py` | Mod | +34 | TaprootSignatureMsg SPHINCS+ sighash |
| `src/test/fuzz/CMakeLists.txt` | Mod | +1 | Register fuzz target |
| `src/test/fuzz/sphincs.cpp` | New | 138 | SPHINCS+ verify fuzz target |

**6 files, +1,590 lines**

### Commit 4: `wallet: add quantum-insured keys, descriptors, RPCs, and signing`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/wallet/sphincskeys.h` | New | 145 | SphincsKey class (secure memory, derivation) |
| `src/wallet/sphincskeys.cpp` | New | 129 | Generate, DeriveFromMaster, Sign, Load with round-trip verify |
| `src/qextkey.h` | New | 87 | QExtPubKey/QExtKey structs |
| `src/qextkey.cpp` | New | 158 | Encode/decode, base58, child derivation, address construction |
| `src/wallet/qextkey.h` | New | 22 | Wallet-layer qextkey helpers |
| `src/wallet/qextkey.cpp` | New | 6 | Implementation |
| `src/wallet/rpc/sphincs.cpp` | New | 835 | 8 RPCs: createsphincskey, getquantumaddress, export/import qpub/qprv, listsphincskeys, sphincsspend |
| `src/script/descriptor.cpp` | Mod | +269 | QISDescriptor + QRDescriptor classes, parsers |
| `src/script/sign.cpp` | Mod | +178 | SPHINCS+ pre-signing, hybrid script fallback, annex construction, activation-aware verify flags |
| `src/script/sign.h` | Mod | +12 | SignatureData: force_script_path, sphincs_signing_key, taproot_annex |
| `src/script/signingprovider.h` | Mod | +4 | TaprootSpendData sphincs_keys |
| `src/script/signingprovider.cpp` | Mod | +3 | Implementation |
| `src/psbt.h` | Mod | +118 | PSBT fields 0x1d/0x1e/0x1f/0x09, serialization |
| `src/psbt.cpp` | Mod | +44 | SignPSBTInput sphincs_secret, PSBTInputSignedAndVerified flags |
| `src/wallet/scriptpubkeyman.h` | Mod | +35 | HasSphincsKey, FillPSBT sphincs_emergency |
| `src/wallet/scriptpubkeyman.cpp` | Mod | +144 | SetupSphincsKey, GetSphincsSigningKey, FillPSBT two-pass |
| `src/wallet/external_signer_scriptpubkeyman.h` | Mod | +2 | FillPSBT signature |
| `src/wallet/external_signer_scriptpubkeyman.cpp` | Mod | +4 | Implementation |
| `src/wallet/wallet.h` | Mod | +4 | FillPSBT sphincs_emergency param |
| `src/wallet/wallet.cpp` | Mod | +35 | Two-pass SPKM iteration |
| `src/wallet/walletdb.h` | Mod | +10 | SPHINCSKEY/SPHINCSCKEY DB constants |
| `src/wallet/walletdb.cpp` | Mod | +81 | Write/load handlers with integrity hash |
| `src/wallet/rpc/wallet.cpp` | Mod | +18 | RPC registration |
| `src/wallet/rpc/spend.cpp` | Mod | +4 | walletprocesspsbt sphincs_emergency param |
| `src/wallet/CMakeLists.txt` | Mod | +3 | Build system |
| `src/CMakeLists.txt` | Mod | +1 | Register qextkey |
| `src/rpc/client.cpp` | Mod | +1 | CLI boolean param conversion |

**27 files, +2,313 lines, -39 lines**

### Commit 5: `test: add wallet unit and functional tests`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/wallet/test/sphincskeys_tests.cpp` | New | 345 | 17 unit tests: key generation, determinism, sign/verify |
| `src/wallet/test/qextkey_tests.cpp` | New | 364 | 16 unit tests: serialization, base58, child derivation |
| `src/wallet/test/qis_descriptor_tests.cpp` | New | 419 | 14 unit tests: qr()/qis() parsing, expansion, round-trip serialization |
| `src/wallet/test/sphincskeys_db_tests.cpp` | New | 103 | 2 unit tests: DB persistence |
| `src/wallet/test/CMakeLists.txt` | Mod | +4 | Register test files |
| `test/functional/wallet_sphincs.py` | New | 295 | Full RPC lifecycle + encrypted wallet |
| `test/functional/wallet_sphincs_psbt.py` | New | 100 | PSBT creation, signing, finalization |
| `test/functional/wallet_sphincs_activation.py` | New | 99 | Activation boundary tests |
| `test/functional/wallet_sphincs_scriptpath.py` | New | 177 | sphincsspend, PSBT emergency, sweep, targeted selection, errors |

**9 files, +1,886 lines**

### Commit 6: `doc: add BIP specifications, test vectors, and wallet documentation`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `dev/docs/bip-0368.mediawiki` | New | 243 | BIP 368 spec (in-repo copy) |
| `dev/docs/bip-0368-test-vectors.json` | New | 47 | BIP 368 test vectors |
| `dev/docs/bip-0369.mediawiki` | New | 623 | BIP 369 spec (in-repo copy) |
| `dev/docs/bip-0369-test-vectors.json` | New | 71 | BIP 369 test vectors |
| `dev/reports/bip-0369-status-report.md` | New | 132 | Implementation status report |
| `doc/quantum-insured-wallet.md` | New | 136 | Developer guide |

**6 files, +1,252 lines**

### Commit 7: `wallet: canonicalize qr() descriptor serialization`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/script/descriptor.cpp` | Mod | +43/−42 | `QRDescriptor::ToStringHelper` override serializes canonical `qr(qpub...)` form; parse simplification |
| `src/wallet/test/qis_descriptor_tests.cpp` | Mod | +67 | 3 new tests: round-trip serialization, reject legacy form, canonical wallet DB write |

**2 files, +123 lines, −42 lines**

### Commit 8: `wallet: select minimum QI inputs in non-sweep sphincsspend`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `src/wallet/rpc/sphincs.cpp` | Mod | +70/−12 | QICoin struct, largest-first sort, incremental selection for non-sweep; sweep unchanged |
| `test/functional/wallet_sphincs_scriptpath.py` | Mod | +26/−6 | New test 3: partial spend asserts fewer inputs than total QI UTXOs |

**2 files, +84 lines, −12 lines**

---

## BIP Specifications (`repos/bips`)

### Commit 1: `doc: add BIP 368/369/377/395 draft specifications`

| File | Status | Lines | Description |
|------|--------|-------|-------------|
| `bip-0368.mediawiki` | New | 278 | Taproot Key-Path Hardening |
| `bip-0368/test-vectors.json` | New | 47 | Annex encoding, NUMS rejection, tweak verification |
| `bip-0369.mediawiki` | New | 645 | OP_CHECKSPHINCSVERIFY |
| `bip-0369/test-vectors.json` | New | 71 | Keypairs, sighash, signatures, valid/invalid transactions |
| `bip-0377.mediawiki` | New | 276 | PSBT Extensions for SPHINCS+ |
| `bip-0377/test-vectors.json` | New | 80 | Field types, signing workflow |
| `bip-0395.mediawiki` | New | 396 | Quantum-Insured Extended Keys |
| `bip-0395/test-vectors.json` | New | 56 | Key derivation, serialization, child addresses |

**8 files, +1,849 lines**

---

## Change Weight by Area

| Area | New Files | Modified Files | Lines Added | % of Total |
|------|-----------|----------------|-------------|------------|
| SPHINCS+ library | 14 | 3 | 3,286 | 26% |
| Consensus (interpreter, validation, policy) | 1 | 12 | 380 | 3% |
| Consensus tests | 3 | 3 | 1,590 | 13% |
| Wallet (keys, descriptors, RPCs, signing) | 7 | 20 | 2,313 | 18% |
| Wallet tests | 8 | 1 | 1,886 | 15% |
| Documentation | 6 | 0 | 1,252 | 10% |
| BIP specifications | 8 | 0 | 1,849 | 15% |
| **Total** | **47** | **39** | **12,556** | **100%** |

### Consensus-only footprint

Excluding the SPHINCS+ library (which is vendored C code), tests, and
documentation, the consensus-critical changes are:

- **13 files modified**, **+380 lines**, **-6 lines**
- Concentrated in: `interpreter.cpp` (+213), `validation.cpp` (+26),
  `policy.cpp` (+11), `chainparams.cpp` (+26), `script.h` (+15)

### Wallet-only footprint

- **27 files** (7 new, 20 modified), **+2,313 lines**, **-39 lines**
- Largest new files: `sphincs.cpp` (835 lines, 8 RPCs), `sphincskeys.h/.cpp`
  (274 lines), `qextkey.h/.cpp` (245 lines)
