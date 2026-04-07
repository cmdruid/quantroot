---
name: BIP 368 project state
description: Quantum-resistant key-path hardening for Taproot — internal key disclosure and NUMS ban
type: project
---

## BIP 368: Quantum-Resistant Key-Path Hardening for Taproot

**Branch:** `feat/bip-0361-draft` (same as BIP 369)
**Spec:** `repos/bips/bip-0368.mediawiki`
**Status:** Implemented with 13 functional tests

### Core design

- All key-path spends must include annex with type byte **0x02** containing internal key
- Annex format: `0x50 || 0x02 || P (32 bytes)` = 34 bytes (no script tree)
- Annex format: `0x50 || 0x02 || P (32 bytes) || merkle_root (32 bytes)` = 66 bytes (with script tree)
- No parity byte needed: parity derived via `CreateTapTweak` comparison
- Verifies P reconstructs output key Q via taproot tweak formula
- Bans BIP 341 NUMS point H (`50929b74...`) as internal key
- Bare-key spending (no annex) is **disabled** post-activation (not grace-period, outright ban)
- Randomized NUMS (H + rG) is NOT banned (unique DL per instance)

### Security model

- SHA-256 preimage resistance (128-bit quantum via Grover's) prevents fake internal key
- Attacker who breaks ECDLP can forge signatures but cannot find alternative P' that reconstructs same Q
- Combined with BIP 369: NUMS outputs force script-path spending → SPHINCS+ enforced

### Key files

| File | Purpose |
|------|---------|
| `src/script/interpreter.cpp` | Key-path verification in VerifyWitnessProgram (~line 2129) |
| `src/script/script.h` | KEYPATH_ANNEX_TYPE = 0x02 |
| `src/script/interpreter.h` | SCRIPT_VERIFY_KEYPATH_HARDENING flag |
| `test/functional/feature_keypath_hardening.py` | 13 functional tests |
| `repos/bips/bip-0368.mediawiki` | Canonical BIP specification |

### Deployment

- Buried deployment: DEPLOYMENT_KEYPATH_HARDENING, BIP368Height
- `-testactivationheight=keypath_hardening@N` for regtest
- Regtest default: active at height 1

### Design decisions

- Internal key in annex (not extra witness element): preserves BIP 341's element-count key-path/script-path distinction
- No parity byte: derive via CreateTapTweak, compare x-coordinates directly
- Bare-key spending disabled outright: grace period/rate limiting removed because it undermines the entire security model
- Only exact NUMS point H banned: randomized H+rG has unique DL per instance, banning infeasible
- Banned NUMS list is extensible by future soft forks
- BIP stands alone: enforcement rules don't reference BIP 369 by number

### Annex type byte namespace

| Type byte | BIP | Purpose |
|-----------|-----|---------|
| 0x02 | 368 | Key-path internal key disclosure |
| 0x04 | 369 | SPHINCS+ signatures (script-path) |
