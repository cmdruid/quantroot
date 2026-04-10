# Understanding SPHINCS+ Signatures

SPHINCS+ (standardized as SLH-DSA in NIST FIPS 205) is a **hash-based**
post-quantum signature scheme. Unlike Schnorr/ECDSA (which rely on the
hardness of discrete logarithms) or RSA (which relies on factoring),
SPHINCS+ derives its security entirely from hash functions.

A quantum computer running Shor's algorithm can break discrete logarithms
and factoring in polynomial time. But hash functions remain secure —
Grover's algorithm only provides a quadratic speedup against hash
preimage search, which is addressed by using larger hash outputs.

---

## Why Hash-Based Signatures?

| Property | ECDSA/Schnorr | SPHINCS+ |
|----------|--------------|----------|
| Security basis | Elliptic curve discrete log | Hash function preimage resistance |
| Quantum vulnerable? | Yes (Shor's algorithm) | No |
| Signature size | 64 bytes | 4,080 bytes |
| Public key size | 32 bytes | 32 bytes |
| Verification speed | ~27 µs | ~1,756 µs |
| Stateful? | No | **No** (unlike XMSS) |

The key advantage of SPHINCS+ over other post-quantum schemes is that it's
**stateless** — the same key can sign unlimited messages without tracking
which one-time keys have been used. This is critical for Bitcoin wallets
where key reuse across UTXOs is the norm.

---

## The Building Blocks

SPHINCS+ combines three cryptographic primitives into a single scheme:

### 1. WOTS+ (Winternitz One-Time Signature)

WOTS+ signs a single message using **hash chains**. The idea is simple:

```
Secret:  s
Public:  H(H(H(...H(s)...)))  = H^w(s)    (hash s exactly w times)
```

To sign a message digit `d` (where 0 ≤ d ≤ w-1):

```
Signature: H^d(s)              (hash s exactly d times)
```

To verify, the verifier hashes the signature `w - d` more times and checks
that it equals the public key:

```
Verify: H^(w-d)(signature) == public_key
        H^(w-d)(H^d(s))   == H^w(s)    ✓
```

Each digit of the message gets its own hash chain. The Winternitz parameter
`w` controls the tradeoff between signature size and computation:
- Higher `w` = shorter signatures, more hashing
- Lower `w` = longer signatures, less hashing

**Limitation**: each WOTS+ key can only sign ONE message. If you sign two
different messages with the same key, an attacker can combine the revealed
hash chain values to forge signatures.

### 2. XMSS (eXtended Merkle Signature Scheme)

XMSS extends WOTS+ to support **multiple** signatures by organizing many
WOTS+ keypairs into a Merkle tree:

```
            Root
           /    \
         H01    H23
        / \     / \
      H0   H1  H2  H3      ← leaf hashes
      |    |    |    |
    WOTS  WOTS WOTS WOTS    ← one-time keypairs
      0    1    2    3
```

Each leaf is the hash of a WOTS+ public key. To sign message `i`, use
WOTS+ keypair `i` and provide the **authentication path** — the sibling
hashes needed to reconstruct the root:

```
Signing with leaf 1:
  Authentication path: [H0, H23]
  
  Verifier computes:
    H01 = Hash(H0 || H1)     ← H0 from auth path, H1 from WOTS+ pubkey
    Root = Hash(H01 || H23)   ← H23 from auth path
    
  Compare computed Root with known Root → valid ✓
```

The authentication path is `log₂(n)` hashes for a tree with `n` leaves.

**Limitation**: XMSS is **stateful** — the signer must track which leaf
index to use next. Using the same leaf twice breaks security. This makes
XMSS impractical for Bitcoin wallets where state management is fragile.

### 3. FORS (Forest of Random Subsets)

FORS is a **few-time** signature scheme used at the bottom of the SPHINCS+
structure. It signs the actual message by revealing subsets of secret values
organized in multiple small Merkle trees:

```
Message hash → split into k indices → reveal one leaf from each of k trees

Tree 0:        Tree 1:        ...    Tree k-1:
  Root₀          Root₁                 Root_{k-1}
  / \            / \                    / \
 .   .          .   .                  .   .
 |   |          |   |                  |   |
[*]  .         .   [*]                [*]  .
 ↑                  ↑                  ↑
reveal             reveal             reveal
```

FORS can safely sign a few messages (the probability of collision across
the `k` trees is low for small numbers of signatures). In SPHINCS+, each
FORS instance only signs once — it's the XMSS/hypertree structure above
that provides the multi-use capability.

---

## How SPHINCS+ Combines Them: The Hypertree

SPHINCS+ builds a **hypertree** — a tree of XMSS trees stacked in layers:

```
Layer d-1 (top):     [XMSS tree]          ← signs with root as public key
                      /        \
Layer d-2:      [XMSS tree] [XMSS tree]   ← each signed by parent XMSS
                  /    \       /    \
                ...    ...   ...    ...
                  
Layer 0 (bottom): [XMSS] [XMSS] ... [XMSS]  ← each leaf signs a FORS key
                    |      |           |
                  [FORS] [FORS]     [FORS]    ← signs the actual message
```

**Signing a message**:

1. Hash the message to determine which FORS instance to use
2. FORS signs the message hash → produces FORS signature + auth path
3. The FORS public key is a leaf in the bottom XMSS tree
4. Each XMSS layer signs the root of the layer below
5. Chain of XMSS signatures from bottom to top

**Verification**:

1. Verify the FORS signature against the message hash
2. Compute the FORS public key (root of the FORS trees)
3. Verify each XMSS layer: leaf → auth path → root
4. Final root must match the known public key

---

## Bitcoin's SPHINCS+ Parameters

Quantroot uses custom parameters optimized for Bitcoin's constraints:

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `n` | 16 | Hash output size (bytes) — security parameter |
| `h` | 32 | Total hypertree height (2³² possible signatures) |
| `d` | 4 | Number of XMSS layers (h/d = 8 levels per tree) |
| `w` | 256 | Winternitz parameter (compact WOTS+ chains) |
| `k` | 10 | FORS trees |
| `a` | 14 | FORS tree height (2¹⁴ = 16,384 leaves per tree) |

These produce:
- **32-byte public key** (pk_seed ‖ pk_root)
- **64-byte secret key** (sk_seed ‖ sk_prf ‖ pk_seed ‖ pk_root)
- **4,080-byte signature**
- **NIST Category 1 security** (128-bit classical, 64-bit quantum via Grover's)

### Why these parameters?

- **n=16** (not 32): halves the signature size compared to FIPS 205 defaults.
  128-bit classical security is sufficient — Bitcoin's ECDSA already targets
  128-bit security.
- **h=32**: supports 2³² = ~4 billion signatures per key. More than enough
  for any Bitcoin account.
- **d=4**: 4 XMSS layers keeps verification fast (fewer tree traversals).
- **w=256**: maximum Winternitz parameter. Each WOTS+ chain is 256 hashes
  long but only needs `n/log₂(w) + 1 = 3` chains. Minimizes signature size
  at the cost of more hashing.

---

## What's Inside a 4,080-Byte Signature?

```
SPHINCS+ Signature (4,080 bytes)
├── Randomizer (16 bytes)
│   └── R: randomized message hash input
├── FORS Signature (~2,400 bytes)
│   ├── k=10 revealed leaves (10 × 16 = 160 bytes)
│   └── k=10 authentication paths (10 × 14 × 16 = 2,240 bytes)
├── XMSS Signatures (~1,664 bytes)
│   ├── Layer 0: WOTS+ sig (48 bytes) + auth path (8 × 16 = 128 bytes)
│   ├── Layer 1: WOTS+ sig (48 bytes) + auth path (128 bytes)
│   ├── Layer 2: WOTS+ sig (48 bytes) + auth path (128 bytes)
│   └── Layer 3: WOTS+ sig (48 bytes) + auth path (128 bytes)
└── Total: 16 + 2,400 + 1,664 = 4,080 bytes
```

For comparison, a Schnorr signature is just 64 bytes (32-byte R point +
32-byte s scalar). The 64× size increase is the cost of hash-based
quantum resistance.

---

## Stateless Security

The critical property that makes SPHINCS+ suitable for Bitcoin:

**XMSS alone is stateful** — you must never reuse a leaf index. If the
signer loses track of which indices were used (wallet restore from seed,
concurrent signing, backup restoration), security is broken.

**SPHINCS+ is stateless** because it uses the message hash to
deterministically select which FORS/XMSS leaf to use:

```
index = PRF(sk_prf, message_hash)  →  deterministic leaf selection
```

The same message always selects the same leaf. Different messages select
different leaves (with overwhelming probability given h=32). No state
tracking needed.

This means:
- Restore a wallet from seed → same SPHINCS+ key, no state to recover
- Sign the same UTXO twice → same leaf, same signature (safe)
- Sign different UTXOs → different leaves (safe, stateless)

---

## How Quantroot Uses SPHINCS+

In Bitcoin's Quantroot soft fork, SPHINCS+ is not used alone — it's
combined with Schnorr in a **hybrid** construction:

```
<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG
```

The SPHINCS+ signature (4,080 bytes) is carried in the Taproot **annex**
rather than on the script stack, avoiding the 520-byte stack element limit.

For the full picture of how SPHINCS+ integrates with Bitcoin's Taproot
signing pipeline, see [ARCHITECTURE.md](ARCHITECTURE.md) and
[EXPLAINER.md](EXPLAINER.md).

---

## Further Reading

- [NIST FIPS 205](https://csrc.nist.gov/pubs/fips/205/final) — SLH-DSA standard
- [SPHINCS+ paper](https://sphincs.org/) — original research
- [BIP 369](../repos/bips/bip-0369.mediawiki) — OP_CHECKSPHINCSVERIFY specification
- [ARCHITECTURE.md](ARCHITECTURE.md) — Quantroot signing pipeline
- [EXPLAINER.md](EXPLAINER.md) — design decisions and tradeoffs
