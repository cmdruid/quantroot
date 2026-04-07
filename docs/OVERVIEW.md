# Overview

Quantroot is a Docker Compose monorepo for developing and testing a post-quantum
soft-fork upgrade path for Bitcoin Taproot, implemented as two companion
specification drafts whose canonical copies live in `repos/bips`.

## The Problem

Taproot ([BIP 341](../repos/bips/bip-0341.mediawiki)) key-path spending requires only a
Schnorr signature. A quantum computer capable of solving the Elliptic Curve
Discrete Logarithm Problem (ECDLP) could forge these signatures and spend any
Taproot output — bypassing post-quantum protections hidden in the script tree.

This is especially dangerous for outputs using the NUMS (Nothing Up My Sleeve)
internal key recommended by BIP 341. The NUMS point has an unknown discrete log
classically, but a quantum computer can recover it, derive the output key's
private key, and key-path spend — completely circumventing any SPHINCS+ tapleaf.

## The Solution: Two Companion BIPs

### BIP 369 — OP_CHECKSPHINCSVERIFY (Script-Path Protection)

Redefines `OP_NOP4` (`0xB3`) in Tapscript as `OP_CHECKSPHINCSVERIFY` for
verifying SPHINCS+ (SLH-DSA) post-quantum signatures carried in the Taproot
annex. Key properties:

- **OP_NOP4 redefinition** — follows the CLTV/CSV precedent. Non-upgraded nodes
  see a no-op and still enforce all Schnorr checks in the same script.
- **Annex-carried signatures** — SPHINCS+ signatures (~4 KB each) are carried in
  the annex (type byte `0x04`), keeping them out of the executing script stack.
- **Hybrid scripts** — Schnorr and SPHINCS+ checks coexist in one script. An
  attacker must break both simultaneously.
- **Cursor-based consumption** — signatures are consumed sequentially from the
  annex; all must be used by script completion.

### BIP 368 — Key-Path Hardening (Key-Path Protection)

Requires the internal public key to be disclosed in a key-path spend annex (type
byte `0x02`) and bans known NUMS points:

- **Internal key disclosure** — the spender must provide `P` in the annex;
  verifiers check `P` reconstructs the output key `Q` via the taproot tweak.
- **NUMS ban** — if `P` matches a known NUMS point (e.g., BIP 341's `H`),
  the spend is invalid. A quantum attacker who recovers `H`'s discrete log
  cannot use it.
- **Bare-key spending disabled** — outputs not constructed with a taproot tweak
  cannot be verified, so they are disabled post-activation.

### Combined Protection Matrix

| Output Type | Key-Path | Script-Path | Quantum Protection |
|-------------|----------|-------------|-------------------|
| NUMS + SPHINCS+ leaf | Banned (NUMS) | SPHINCS+ enforced | Full |
| Normal key + SPHINCS+ leaf | Allowed (P revealed) | SPHINCS+ enforced | Script-path only |
| Normal key, no SPHINCS+ | Allowed (P revealed) | Schnorr only | None |
| Bare key | Disabled | N/A | Migrate before activation |

## Architecture

### Monorepo Structure

The monorepo provides Docker Compose infrastructure around the Bitcoin Core fork:

```
quantroot/
├── repos/bitcoin/       Bitcoin Core fork (submodule, quantroot branch)
├── repos/bips/          Canonical BIP specification knowledge base
├── services/            Docker service wrappers
├── docs/                Domain guides and navigation into repos/bips
├── dev/                 Developer workflow and conventions
├── test/                Cross-service test infrastructure
├── scripts/             Runtime helpers
└── config/              Shared configuration
```

### Consensus Code (in repos/bitcoin)

The implementation modifies Bitcoin Core's script interpreter and adds a vendored
SPHINCS+ cryptographic library:

- **Script layer** — `OP_CHECKSPHINCSVERIFY` handler in `interpreter.cpp`, annex
  parsing, signature cursor, `SignatureHashSphincs` (BIP 342 sighash minus
  `sha_annex`), key-path hardening verification.
- **Crypto layer** — vendored `slhdsa-c` library in `src/crypto/sphincsplus/`
  with a custom `slh_dsa_bitcoin` parameter set (n=16, h=32, d=4, k=10, a=14).
- **Deployment** — BIP 9 versionbits with buried deployment for regtest
  (`-testactivationheight=sphincs@N`).
- **Tests** — 56 functional tests across `feature_sphincs.py` and
  `feature_keypath_hardening.py`, plus fuzz targets and benchmarks.

#### Key Files

| File | Role |
|------|------|
| `src/script/script.h` | `OP_CHECKSPHINCSVERIFY = 0xB3`, annex type constants |
| `src/script/interpreter.h` | `SCRIPT_VERIFY_CHECKSPHINCSVERIFY` / `SCRIPT_VERIFY_KEYPATH_HARDENING` flags, `ScriptExecutionData` extensions |
| `src/script/interpreter.cpp` | Opcode handler, annex parsing, `SignatureHashSphincs`, key-path verification, unconsumed-sig check |
| `src/script/script_error.h/.cpp` | Error codes for both BIPs |
| `src/crypto/sphincsplus.h/.cpp` | `VerifySphincsSignature` / `SphincsKeygen` / `SphincsSign` wrapper API |
| `src/crypto/sphincsplus/` | Vendored `slhdsa-c` library with `slh_dsa_bitcoin` parameter set |
| `src/consensus/params.h` | `DEPLOYMENT_SPHINCS`, `DEPLOYMENT_KEYPATH_HARDENING` enums |
| `src/kernel/chainparams.cpp` | Activation heights (max for mainnet/testnet, 1 for regtest) |
| `src/validation.cpp` | `DeploymentActiveAt` checks in `GetBlockScriptFlags` |
| `test/functional/feature_sphincs.py` | 43 BIP 369 tests |
| `test/functional/feature_keypath_hardening.py` | 13 BIP 368 tests |
| `test/functional/test_framework/sphincs.py` | `SphincsKey`, `SphincsSigner`, `build_sphincs_annex` |

### Annex Type Byte Namespace

| Byte | BIP | Purpose |
|------|-----|---------|
| `0x02` | 368 | Key-path internal key disclosure |
| `0x04` | 369 | SPHINCS+ signatures (script-path) |

## Key Concepts

See [GLOSSARY.md](GLOSSARY.md) for shared terminology.

### Quantum Insurance Strategy

Users can protect funds **before** the soft fork activates:

1. Create Taproot outputs with a hidden SPHINCS+ tapleaf (zero on-chain cost).
2. Spend normally via Schnorr. The SPHINCS+ leaf is never revealed.
3. If a quantum threat emerges and the fork activates, spend through the SPHINCS+
   tapleaf using `OP_CHECKSPHINCSVERIFY`.

### Hybrid Schnorr + SPHINCS+ Scripts

The canonical hybrid script template:

```
<schnorr_pk> OP_CHECKSIGVERIFY
<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP
1
```

- **Non-upgraded nodes**: `OP_NOP4` does nothing; Schnorr check runs normally.
- **Upgraded nodes**: both Schnorr and SPHINCS+ are verified.

### Why OP_NOP4 (not OP_SUCCESSx)?

`OP_SUCCESSx` triggers unconditional script success in a pre-execution scan —
Schnorr checks would never run on non-upgraded nodes. `OP_NOP4` redefinition
lets Schnorr checks execute normally, maintaining security during the activation
transition.

### Circular Sighash Dependency

SPHINCS+ signatures live in the annex. Including `sha_annex` in the SPHINCS+
sighash would create a circular dependency (signature hashes itself). The annex
bit in `spend_type` is still set (`0x03`) for domain separation, and the Schnorr
sighash still includes `sha_annex`, locking the annex contents.

### Why Standard SLH-DSA (4,080 bytes) Over W+C_P+FP (3,408 bytes)?

The tree parameters (n=16, h=32, d=4, k=10, a=14) come from Kudinov and Nick
([ePrint 2025/2203](https://eprint.iacr.org/2025/2203)), which also proposes
WOTS+C and PORS+FP optimizations that would reduce signatures by ~672 bytes.
This BIP uses the standard FIPS 205 algorithms because:

- **NIST-reviewed** — standard WOTS+ and FORS have been through the full NIST
  PQC standardization process (2016–2024). The optimized variants are newer and
  less reviewed.
- **Same security level** — both target NIST Category 1 (128-bit classical).
- **Drop-in upgrade** — W+C_P+FP uses the same hypertree structure and hash
  function. A future soft fork can tighten the accepted signature size from 4,080
  to 3,408 bytes without changing sighash, consensus rules, or deployment logic.
