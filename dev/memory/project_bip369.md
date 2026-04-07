---
name: BIP 369 project state
description: OP_CHECKSPHINCSVERIFY — post-quantum SPHINCS+ signature verification in Tapscript
type: project
---

## BIP 369: Post-Quantum Signature Verification Using the Taproot Annex in Tapscript

**Branch:** `feat/bip-0361-draft`
**Spec:** `repos/bips/bip-0369.mediawiki`
**Status:** PoC complete, 43 functional tests, review-ready

### Core design

- Redefines OP_NOP4 (0xB3) as OP_CHECKSPHINCSVERIFY (CLTV/CSV precedent, not OP_SUCCESSx)
- SPHINCS+ signatures carried in Taproot annex with type byte **0x04**
- Annex format: `0x50 || 0x04 || compact_size(N) || sig_1 || ... || sig_N`
- Each signature is **4080 bytes** (standard SLH-DSA FIPS 205, not W+C_P+FP optimized)
- SPHINCS+ sighash: BIP 342 Tapscript sighash with sha_annex **omitted** (breaks circular dependency)
- spend_type = 0x03 (annex bit = 1 for domain separation)
- Only SIGHASH_DEFAULT (0x00) supported
- Signing order: SPHINCS+ first, then Schnorr (normative)

### Cryptographic parameters

- Standard SLH-DSA (FIPS 205) with custom tree params: n=16, h=32, d=4, w=256, k=10, a=14
- WOTS+ (standard, len=18 with checksum chains) + FORS (standard, k=10, a=14)
- W+C_P+FP optimization (3408-byte sigs) documented in addendum as future upgrade path
- Vendored slhdsa-c library in `src/crypto/sphincsplus/`
- Custom parameter set: `slh_dsa_bitcoin` defined in `slh_sha2.c`
- Benchmark: verification ~1.8ms (~64x Schnorr), VALIDATION_WEIGHT_PER_SPHINCS_SIGOP = 3200

### Key files

| File | Purpose |
|------|---------|
| `src/script/script.h` | OP_CHECKSPHINCSVERIFY, SPHINCS constants |
| `src/script/interpreter.h` | SCRIPT_VERIFY flag, ScriptExecutionData (cursor, annex data) |
| `src/script/interpreter.cpp` | Opcode handler, annex parsing, SignatureHashSphincs |
| `src/crypto/sphincsplus.h/.cpp` | VerifySphincsSignature / SphincsKeygen / SphincsSign wrapper |
| `src/crypto/sphincsplus/` | Vendored slhdsa-c (Apache/ISC/MIT triple license) |
| `test/functional/feature_sphincs.py` | 43 functional tests (36 post-activation + 7 activation) |
| `test/functional/test_framework/sphincs.py` | SphincsKey, SphincsSigner, build_sphincs_annex |
| `test/functional/test_framework/sphincs_signer.cpp` | Standalone keygen/sign binary |
| `src/bench/sphincs.cpp` | SphincsVerify, SphincsSign benchmarks |
| `src/test/fuzz/sphincs.cpp` | sphincs_verify, sphincs_annex_parse fuzz targets |
| `repos/bips/bip-0369/test-vectors.json` | 7 test vector sections |

### Deployment

- Buried deployment: DEPLOYMENT_SPHINCS, BIP369Height
- `-testactivationheight=sphincs@N` for regtest
- Dynamic mempool flag via DeploymentActiveAfter
- Regtest default: active at height 1

### Design decisions

- OP_NOP4 not OP_SUCCESSx: because OP_SUCCESSx pre-scan bypasses ALL script validation (Schnorr checks skipped on old nodes)
- sha_annex omitted from SPHINCS+ sighash: breaks circular dependency (sig in annex can't hash itself)
- Standard FIPS 205 not W+C_P+FP: NIST-reviewed algorithms, same security level, drop-in upgrade path
- Annex type byte 0x04 (not 0x01): leaves room for 0x02 (BIP 368 key-path) and 0x03 (reserved)
- VALIDATION_WEIGHT cost = 3200 (64x Schnorr's 50): based on benchmark measurements
