# Quantroot Technical Explainer

A deep dive into the design decisions behind the Quantroot soft fork,
aimed at developers reviewing the BIP specifications and implementation.

---

## 1. The Problem

A sufficiently powerful quantum computer running Shor's algorithm can
solve the Elliptic Curve Discrete Logarithm Problem (ECDLP) in
polynomial time. For Bitcoin, this means:

- **Any exposed public key can be compromised.** Given a secp256k1 public
  key, a quantum adversary can derive the corresponding private key.
- **Taproot key-path spending is the primary attack surface.** The output
  key Q is on-chain in the scriptPubKey. A quantum attacker can compute
  Q's private key and key-path spend any Taproot UTXO without needing
  the script tree.
- **Script-path protections are bypassed.** Even if a SPHINCS+ tapleaf
  exists in the MAST tree, the attacker doesn't need it — they simply
  key-path spend using Q's private key.

This is why Quantroot requires **two** companion BIPs: BIP 369 adds
post-quantum signature verification, and BIP 368 hardens key-path
spending so it can't bypass the quantum-resistant script path.

## 2. The Approach: Deploy Today, Activate Later

Quantroot uses a **forward-compatible** design based on OP_NOP4 redefinition,
following the same pattern as OP_CHECKLOCKTIMEVERIFY (BIP 65) and
OP_CHECKSEQUENCEVERIFY (BIP 112):

1. **Before activation**: `OP_CHECKSPHINCSVERIFY` is `OP_NOP4` — a no-op.
   Non-upgraded nodes skip it. But `OP_CHECKSIG` in the same script is
   always enforced. Funds are protected by Schnorr.

2. **After activation**: `OP_CHECKSPHINCSVERIFY` verifies the SPHINCS+
   signature from the annex. Both Schnorr and SPHINCS+ are now enforced.
   Funds are protected by hash-based cryptography.

The key insight: you can create quantum-insured outputs **today** on mainnet.
The hybrid tapleaf is valid under current consensus. When a quantum threat
emerges and the soft fork activates, your existing outputs are already
protected — no migration needed.

## 3. The Hybrid Script

The quantum-insured tapleaf uses a simple 5-opcode script:

```
<sphincs_pk>  OP_CHECKSPHINCSVERIFY  OP_DROP  <schnorr_pk>  OP_CHECKSIG
```

### Pre-activation evaluation

```
Stack: [schnorr_sig]

<sphincs_pk>             → push 32 bytes onto stack
OP_NOP4                  → does nothing (non-upgraded nodes skip it)
OP_DROP                  → removes sphincs_pk from stack
<schnorr_pk>             → push 32 bytes onto stack
OP_CHECKSIG              → verifies schnorr_sig against schnorr_pk ← ALWAYS ENFORCED
```

The SPHINCS+ public key is pushed, ignored, and dropped. The Schnorr
signature is verified as usual. Security is equivalent to a standard
`pk()` tapleaf.

### Post-activation evaluation

```
Stack: [schnorr_sig]
Annex: [0x50, 0x04, compact_size(1), sphincs_sig (4080 bytes)]

<sphincs_pk>             → push 32 bytes onto stack
OP_CHECKSPHINCSVERIFY    → consume sphincs_sig from annex, verify against sphincs_pk
OP_DROP                  → removes sphincs_pk from stack
<schnorr_pk>             → push 32 bytes onto stack
OP_CHECKSIG              → verifies schnorr_sig against schnorr_pk
```

Both signatures are verified. An attacker must break both Schnorr (ECDLP)
and SPHINCS+ (hash-based) simultaneously to spend.

## 4. The Two-Round Signing Problem

The hybrid script requires both SPHINCS+ and Schnorr signatures. But the
BIP 342 Schnorr sighash includes `sha_annex` — a hash of the annex where
the SPHINCS+ signature lives. This creates a circular dependency:

> The SPHINCS+ signature is IN the annex.
> The Schnorr signature commits to a hash OF the annex.
> Therefore, the SPHINCS+ signature would need to be its own input.

### How BIP 369 breaks the cycle

The SPHINCS+ sighash uses the standard BIP 342 Tapscript construction with
one modification: `sha_annex` is **omitted** despite the annex-present bit
being set.

| Sighash context | spend_type | sha_annex |
|----------------|------------|-----------|
| Non-annex Tapscript (BIP 342) | `0x01` | not present |
| Schnorr with annex (BIP 342) | `0x03` | appended |
| SPHINCS+ with annex (BIP 369) | `0x03` | **omitted** |

The signing order is:

1. **SPHINCS+ signs first** — sighash uses `spend_type=0x03` but does NOT
   include `sha_annex`. The signature is computed without knowledge of the
   annex contents.
2. **Build the annex** — the SPHINCS+ signature is placed in the annex
   (`0x50 || 0x04 || compact_size(1) || sphincs_sig`).
3. **Schnorr signs second** — sighash uses `spend_type=0x03` WITH `sha_annex`
   appended. The Schnorr signature commits to the annex (and thus to the
   SPHINCS+ signature).

This ensures the Schnorr signature locks the annex contents while the
SPHINCS+ signature avoids the circularity.

## 5. Key Derivation

SPHINCS+ keys are derived deterministically from the wallet's BIP 32 master
key, so the mnemonic phrase is the only backup needed.

```
master_ext_privkey = HMAC-SHA512("Bitcoin seed", seed)   // standard BIP 32
sphincs_material   = HMAC-SHA512("Sphincs seed",
                                  master_ext_privkey || account_path_bytes)

sk_seed = sphincs_material[0:16]    // 16 bytes
sk_prf  = sphincs_material[16:32]   // 16 bytes
pk_seed = sphincs_material[32:48]   // 16 bytes
// Bytes 48-63 unused

(secret_key, public_key) = SLH-DSA-Keygen(sk_seed, sk_prf, pk_seed)
```

### Design choices

- **One key per account** (`m/395'/coin_type'/account'`). SPHINCS+ is
  stateless — the same key can sign unlimited messages without security
  degradation. Unlike XMSS where key reuse is catastrophic.
- **Purpose index 395'** matches BIP 395's assigned number.
- **Domain separation**: `"Sphincs seed"` vs BIP 32's `"Bitcoin seed"` ensures
  the SPHINCS+ derivation is cryptographically independent.
- **Full 64-byte master key**: both the private key (32B) and chain code (32B)
  are inputs. The chain code is secret material never exposed in account-level
  xpubs, providing additional entropy.

## 6. The qr() Descriptor

`qr()` is a drop-in replacement for `tr()` that auto-constructs the hybrid
SPHINCS+ tapleaf:

```
qr(Q1.../0/*)
```

This expands to:

```
Internal key: BIP32_Derive(qpub.xpub, child_index)
Tapleaf:      <qpub.sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP
              <child_xonly> OP_CHECKSIG
Output key:   child_xonly + H(TapTweak, child_xonly || leaf_hash) * G
```

### qpub/qprv serialization

| Format | Size | Prefix | Contents |
|--------|------|--------|----------|
| qpub | 110 bytes | Q1... | BIP 32 xpub (78B) + SPHINCS+ pubkey (32B) |
| qprv | 142 bytes | Q1... | BIP 32 xprv (78B) + SPHINCS+ secret (64B) |

Distinguished by payload size (110 vs 142 bytes after base58 decoding).

### Watch-only support

A `qpub` can derive all quantum-insured addresses without private key
access. Import into a watch-only wallet:

```
bitcoin-cli importqpub "Q1..."
```

## 7. Emergency Spending

When a quantum threat materializes:

```
bitcoin-cli sphincsspend "destination_address" amount
bitcoin-cli sphincsspend "destination_address"          # sweep all
```

### What happens internally

1. **QI UTXO selection** — only quantum-insured UTXOs are selected
   (matched via `GetScriptPubKeyMans` to SPKMs with `HasSphincsKey()`)
2. **Coin control** — `m_allow_other_inputs=false` prevents mixing non-QI UTXOs
3. **Create unsigned transaction** via `CreateTransaction`
4. **Two-pass FillPSBT** with `sphincs_emergency=true`:
   - Pass 1: QI SPKMs sign first (script-path with SPHINCS+)
   - Pass 2: Non-QI SPKMs handle remaining inputs (key-path)
5. **Finalize and broadcast**

### Witness format

```
[schnorr_sig (64B)]
[hybrid_script (69B)]
[control_block (33B)]
[annex (4083B): 0x50 || 0x04 || 0x01 || sphincs_sig (4080B)]
```

## 8. Validation Weight

SPHINCS+ verification is ~64x more expensive than Schnorr verification
(~1,756 µs vs ~27 µs). To prevent DoS attacks via cheap SPHINCS+ inputs,
each `OP_CHECKSPHINCSVERIFY` deducts validation weight:

```
VALIDATION_WEIGHT_PER_SPHINCS_SIGOP = 3200  (= 64 × Schnorr's 50)
```

For a single-input transaction with one SPHINCS+ signature:

- Witness size: ~4,180 bytes
- Validation budget: 4,180 + 50 = 4,230
- SPHINCS+ cost: 3,200
- Remaining budget: 1,030 (room for Schnorr checks but not a second SPHINCS+)

A second SPHINCS+ signature requires 6,400 weight — the witness must be
larger (more inputs) to provide sufficient budget.

## 9. Forward Compatibility

Quantum-insured outputs work on all networks today:

| Network | Key-path spend | Script-path spend | sphincsspend |
|---------|---------------|-------------------|-------------|
| Mainnet | Works (standard Taproot) | OP_NOP4 skipped, OP_CHECKSIG enforced | Not available (BIP 369 inactive) |
| Testnet/Signet | Same as mainnet | Same as mainnet | Not available |
| Regtest | Works + BIP 368 annex | Both signatures verified | Works |

On mainnet/testnet/signet:
- `createsphincskey`, `getquantumaddress`, `exportqpub` all work
- Addresses are standard bech32m Taproot — indistinguishable on-chain
- Key-path spending works normally (no annex required pre-activation)
- The hybrid tapleaf is embedded but dormant

When the soft fork activates:
- Key-path spends require BIP 368 annex (internal key disclosure)
- Script-path spends via the hybrid leaf require both signatures
- `sphincsspend` becomes available for emergency redemption
- **No migration needed** — existing outputs are already covered

---

## Further Reading

- [BIP 368](../repos/bips/bip-0368.mediawiki) — Taproot Key-Path Hardening
- [BIP 369](../repos/bips/bip-0369.mediawiki) — OP_CHECKSPHINCSVERIFY
- [BIP 395](../repos/bips/bip-0395.mediawiki) — Quantum-Insured Extended Keys
- [BIP 377](../repos/bips/bip-0377.mediawiki) — PSBT Extensions for SPHINCS+
- [Architecture](ARCHITECTURE.md) — data flow and file map
- [Website](https://www.quantroot.org) — visual explainer
