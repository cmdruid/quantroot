# Pre-Release Audit Report

- Date: 2026-04-08
- Scope: All changes on `quantroot` branch in `repos/bitcoin` and `repos/bips`
- Purpose: Prepare for bitcoin-dev mailing list submission

## Executive Summary

Three parallel audits were performed covering consensus/signing code, wallet
code, and BIP specifications. The implementation is architecturally sound with
good separation of concerns and proper consensus safeguards. However, several
issues require attention before mailing list submission.

**Critical issues found: 4**
**High issues found: 10**
**Medium issues found: 10**
**Low issues found: 10+**

---

## Part 1: Consensus & Signing Code

### Critical

None in consensus code.

### High

**H1. Hybrid script fallback is hardcoded to one pattern** (sign.cpp:711-736)
The fallback that signs hybrid scripts when miniscript fails only recognizes
`<pk> OP_CHECKSPHINCSVERIFY OP_DROP <pk> OP_CHECKSIG`. No support for multiple
OP_CHECKSPHINCSVERIFY opcodes, additional script elements, or variant patterns.
Contains an empty `else {}` block (dead code).

*Fix:* Remove dead code. Add XOnlyPubKey validation. Document limitation.
Consider extracting to `SignHybridSphincsScript()` helper for testability.

### Medium

**M1. PSBTInputSignedAndVerified uses heuristic for flag detection** (psbt.cpp:362-369)
Detects SPHINCS+ annex by checking if last witness element starts with `0x50 0x04`.
Correct but fragile — add comments explaining why `stack.size() >= 4` is the
right threshold.

**M2. Compact size parsing edge case** (interpreter.cpp:2119-2120)
8-byte compact_size is rejected but the control flow is subtle. Add clarifying
comment about the order of operations.

**M3. SPHINCS+ secret not validated in SignPSBTInput** (psbt.cpp:442-449)
Accepts 64-byte secret without verifying it's a valid key. Verification happens
later during signing, but no early error message.

### Low

- Redundant bounds check in signature extraction (interpreter.cpp:636-638) — keep for defense-in-depth
- Hardcoded EPOCH in SphincsSignatureHash (interpreter.cpp:1652) — add future-proofing comment
- OP_NOP4 scan in SignTaproot is O(n) per signing attempt (sign.cpp:673-679) — consider caching
- Annex pointer indirection in key-path signing (sign.cpp:640-651) — simplify
- Unconsumed sigs check has 5 conditions (interpreter.cpp:2002-2006) — extract to helper

---

## Part 2: Wallet Code

### Critical

**C1. Buffer overflow in qextkey.cpp Encode/Decode** (qextkey.cpp:22,28,75,81,98)
Raw `unsigned char code[]` parameters lack compile-time bounds checking. Callers
parse untrusted Base58Check data before validating size.

*Fix:* Use `std::array<unsigned char, QI_EXTKEY_SIZE>&` or `std::span` with
explicit bounds checking.

**C2. HMAC-SHA512 key length depends on string literal size** (sphincskeys.cpp:42-49)
`sizeof("Sphincs seed") - 1` is correct (12 bytes) but fragile. If the string
changes, the derivation breaks consensus.

*Fix:* Add `static_assert(sizeof("Sphincs seed") - 1 == 12)` and define as
named constant.

**C3. SphincsKey copy assignment initialization order** (sphincskeys.h:55-68)
`m_valid` is set after `ClearKeyData()` which resets it to false, then
overwritten. The ordering could lead to transient invalid state.

*Fix:* Set `m_valid = false` first, then conditionally restore.

### High

**H2. Missing cryptographic verification in SphincsKey::Load()** (sphincskeys.cpp:84-107)
Public key byte comparison is used instead of sign/verify round-trip. Corrupted
sk_seed/sk_prf (first 32 bytes) would be silently accepted.

*Fix:* Add optional sign/verify test on a fixed message during load.

**H3. Wallet DB checksum not validated on load** (walletdb.cpp:236-247)
`WriteSphincsKey` writes a keypair hash for integrity, but `LoadSphincsKey`
never checks it. Disk corruption of unencrypted keys goes undetected.

*Fix:* Validate the hash during load.

**H4. Integer overflow in sphincsspend coin selection** (sphincs.cpp:741)
`qi_total += out.nValue` lacks overflow check. Theoretically overflowable if
wallet holds >MAX_MONEY in QI UTXOs.

*Fix:* Add `if (qi_total > MAX_MONEY - out.nValue)` check.

**H5. Deterministic IV for SPHINCS+ key encryption** (sphincs.cpp:191,231,584)
IV is `Hash(sphincs_pubkey)` — deterministic and predictable. Same key imported
into multiple wallets uses identical IV, violating encryption best practices.

*Fix:* Include descriptor ID in IV: `Hash(desc_id, pubkey)`. Or use random IV.

**H6. Missing key verification in SphincsKey::Load** (sphincskeys.cpp:80-83)
Public key byte comparison only — no cryptographic verification that the loaded
key can actually produce valid signatures.

### Medium

**M4. Race condition in two-pass FillPSBT** (wallet.cpp:2231-2257)
`GetAllScriptPubKeyMans()` called twice — list could mutate between calls.

*Fix:* Cache the SPKM list before first pass.

**M5. Ambiguous qr() descriptor parsing** (descriptor.cpp:2742-2779)
Multiple decode attempts on the same string with slash-splitting fallback.
Unclear which format takes precedence.

*Fix:* Define strict parsing order in BIP 395.

**M6. getquantumaddress returns partial result if no SPHINCS key** (sphincs.cpp:297-299)
Should throw JSONRPCError instead of returning address without sphincs_pubkey.

**M7. No account_index overflow check** (sphincs.cpp:74)
`0x80000000 + account_index` overflows if `account_index >= 0x80000000`.

*Fix:* Add range validation.

### Low

- Code duplication: encryption block repeated 3 times (sphincs.cpp) — extract to utility
- Missing `static_assert` on sphincs_secret array size (qextkey.cpp:98)
- External signer silently ignores sphincs_emergency (external_signer_scriptpubkeyman.cpp:85)
- Missing bounds assertion in seed splitting (sphincskeys.cpp:53-55)

---

## Part 3: BIP Specifications

### Critical

**C4. BIP 377: PSBT field type bytes conflict with MuSig2** (bip-0377.mediawiki)
Spec defines `PSBT_IN_TAP_SPHINCS_PUB = 0x1c` but MuSig2 already uses 0x1c for
`PSBT_IN_MUSIG2_PARTIAL_SIG`. The implementation correctly uses 0x1d/0x1e/0x1f/0x09
but the spec text is wrong.

*Fix:* Update spec to match implementation: 0x1d, 0x1e, 0x1f, 0x09.
Update test-vectors.json. Remove "provisional" language.

### High

**H7. BIP 369: SPHINCS+ sighash explanation confusing** (bip-0369.mediawiki:202-212)
The sha_annex omission rationale is unclear. `spend_type = 0x03` with
`annex_bit=1` but no `sha_annex` appended needs clearer explanation of why
the domain is distinct from Schnorr sighashes.

*Fix:* Rewrite with explicit domain separation table.

**H8. BIP 395: Both mainnet qpub and qprv share Q1 prefix** (bip-0395.mediawiki:199-208)
Wallets must deserialize fully (110 vs 142 bytes) to distinguish types.
Testnet prefixes T4/T5 are non-standard base58 patterns.

*Fix:* Clarify length-based discrimination. Verify testnet prefixes with
base58check library.

**H9. BIP 377: No disclaimer that spec is PSBT-only** (bip-0377.mediawiki)
Readers may assume it defines RPC behavior.

*Fix:* Add explicit scope statement.

### Medium

**M8. BIP 368: Repeating-byte NUMS ban lacks justification**
Why `0xabab...ab` specifically? No explanation of why this pattern is a
likely quantum attack target.

*Fix:* Add justification or remove the second NUMS point.

**M9. BIP 369: Unknown key type extensibility unclear** (bip-0369.mediawiki:295-301)
Silent signature slot consumption for non-32-byte keys needs threat model
clarification.

**M10. BIP 369: Validation weight budget values are placeholders** (bip-0369.mediawiki:500-514)
`VALIDATION_WEIGHT_PER_SPHINCS_SIGOP` not finalized. Example calculation
appears mathematically incorrect.

*Fix:* Finalize value from benchmarks. Fix example.

### Low

- BIP 368: Bare-key spending grace period not specified (immediate vs delayed)
- BIP 395: HMAC documentation should cite BIP 32 explicitly for endianness
- BIP 395: Bytes 48-63 of HMAC output are unused — should be noted
- BIP 377: Test vector field types match impl but not spec text

---

## Priority Actions Before Mailing List

### Must Fix (blockers)

1. **C4:** Fix BIP 377 PSBT field type bytes (spec vs implementation mismatch)
2. **C1:** Fix qextkey.cpp buffer overflow vulnerability
3. **C2:** Add static_assert for HMAC key length
4. **H1:** Clean up hybrid script fallback (remove dead code, add validation)
5. **H4:** Add overflow check in sphincsspend coin selection

### Should Fix (high confidence)

6. **H3:** Validate DB checksum on load
7. **H5:** Use non-deterministic IV for encryption
8. **H7:** Rewrite SPHINCS+ sighash explanation in BIP 369
9. **H8:** Clarify qpub/qprv prefix disambiguation in BIP 395
10. **M4:** Cache SPKM list in two-pass FillPSBT

### Nice to Have (polish)

11. Extract encryption code to shared utility
12. Add account_index range validation
13. Clarify NUMS ban justification in BIP 368
14. Finalize validation weight budget in BIP 369
15. Add comprehensive test coverage for edge cases

---

## Test Coverage Assessment

| Category | Count | Assessment |
|----------|-------|------------|
| Consensus (BIP 368 + 369) | 56 | Good — covers activation, success/failure, interaction |
| Wallet unit (key, qextkey, descriptor, DB) | 46 | Adequate — needs encrypted wallet edge cases |
| Functional (RPCs, PSBT, activation, script-path) | 59 | Good — covers full lifecycle including emergency spend |
| **Total** | **161** | **Solid for proof-of-concept** |

### Missing test coverage

- Malformed annexes (wrong sizes, invalid compact_size, truncated signatures)
- Encrypted wallet SPHINCS+ key round-trip (create → lock → unlock → sign)
- sphincsspend with insufficient QI funds
- qr() descriptor with multiple tapleaves
- Co-activation edge cases (one deployment active, other not)
- PSBT round-trip with SPHINCS+ fields through external tools
