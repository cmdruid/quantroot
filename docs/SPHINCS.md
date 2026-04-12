# Understanding SPHINCS+ Signatures

**SPHINCS+** (standardized as SLH-DSA in NIST FIPS 205) is a
post-quantum digital signature scheme. It replaces the elliptic-curve
math behind ECDSA and Schnorr with nothing but **hash functions** —
the one-way primitives behind `SHA-256` — which is what makes it safe
against quantum computers.

This guide walks through the internals of SPHINCS+ from the bottom
up: WOTS+ hash chains, Merkle-tree aggregation into XMSS, the
stateful-signing problem, stateless leaf selection via a PRF, the
hypertree, FORS, and Quantroot's concrete parameter choices.

---

## What is SPHINCS+?

At the highest level, SPHINCS+ is built from a handful of cryptographic
pieces stacked on top of each other. You will see these names repeatedly:

| Name | Role |
|------|------|
| **WOTS+** | One-time signature made from hash chains. Signs a single message. |
| **Merkle tree** | Binary tree of hashes that commits to many values under one root. |
| **XMSS** | A Merkle tree of WOTS+ keys — multi-time signing, but *stateful*. |
| **FORS** | A "few-time" signature over a forest of small Merkle trees. Signs the message hash. |
| **Hypertree** | A tree of XMSS trees that lets one small public key authenticate billions of signatures. |

A few terms you will bump into along the way:

- **One-time** — the key can safely sign exactly one message.
- **Few-time** — the key can safely sign a small number of messages.
- **Stateful** — the signer must remember which sub-keys have been used.
- **Stateless** — no counter, no memory — the same key and same message
  always produce the same signature.
- **Authentication path** — the sibling hashes needed to re-derive a
  Merkle root from a leaf.

---

## Prerequisites

This guide assumes passing familiarity with a few cryptographic
primitives. If you'd like a refresher, the links below go to
general-purpose introductions:

- **Digital signatures** — a piece of math that proves *"I, holder of
  this private key, authorized this exact message."* See
  [Wikipedia: Digital signature](https://en.wikipedia.org/wiki/Digital_signature).
- **Cryptographic hash functions** — one-way fingerprints over
  arbitrary data, like `SHA-256`. See
  [Wikipedia: Cryptographic hash function](https://en.wikipedia.org/wiki/Cryptographic_hash_function).
- **Merkle trees** — binary hash trees that commit to many values
  under a single root. See
  [Wikipedia: Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree).
  We'll revisit these below, since XMSS is built on them.

Two things worth keeping in mind as you read on:

- Hash functions are **one-way**. Computing `H(x)` from `x` is
  trivial; going backwards from `H(x)` to `x` is infeasible. That
  asymmetry is the *only* hard problem SPHINCS+ depends on.
- In Bitcoin, a broken signature scheme means an attacker can spend
  coins from any address whose public key has been revealed on-chain
  — i.e., any address that has been spent from. Post-quantum
  signatures exist to keep that window closed.

---

## Why Hash-Based Signatures?

Bitcoin's current signatures — ECDSA and Schnorr — rest on the
**elliptic curve discrete logarithm problem** (ECDLP). A private key
is a random 256-bit integer `d`. The public key is a point `P = d·G`
on the `secp256k1` curve. Computing `P` from `d` is fast; recovering
`d` from `P` takes roughly `2¹²⁸` operations on a classical computer —
effectively infinite.

In 1994 Peter Shor published a quantum algorithm that solves
discrete-log (and integer factoring) in polynomial time. A large,
fault-tolerant quantum computer running Shor's could recover `d`
from `P` in hours. This would break ECDSA, Schnorr, RSA, and every
other scheme whose security reduces to discrete-log or factoring.
Nobody has built such a machine yet, but cryptographic standards
move slowly, and coins safe today need to stay safe in a decade.

Hash functions don't have the algebraic structure Shor's exploits.
The best known quantum attack against a hash function is **Grover's
algorithm**, a general-purpose speedup for brute-force search. Grover
only provides a *quadratic* speedup (`2ⁿ → 2^(n/2)`), which is easy
to absorb by using a larger hash output. A 256-bit hash still
provides 128-bit security against a quantum attacker — the same
level Bitcoin's Schnorr already targets.

Build a signature scheme whose only hard problem is "invert a hash
function," and you get post-quantum security for free.

---

## Building Block 1: WOTS+ (Hash Chains)

The Winternitz One-Time Signature (WOTS+) scheme is the first
primitive we'll build from scratch. The core idea is a **hash chain**:
pick a random secret `s` and hash it `w` times in a row. The end of
the chain is the public key.

```
s → H(s) → H²(s) → H³(s) → ... → H^w(s)
↑                                 ↑
secret                            public key
```

To sign a digit `d` (where `0 ≤ d < w`), reveal the intermediate hash
`H^d(s)`. A verifier applies `H` an additional `w − d` times; if the
result matches the public key, the signature is valid.

### A concrete example

Chain of length `w = 16`, sign digit `d = 5`:

1. Hash your secret `s` sixteen times. Publish `H¹⁶(s)` as the public key.
2. To sign `d = 5`, reveal `H⁵(s)`. That one value is your signature.
3. The verifier hashes your `H⁵(s)` eleven more times. If the result
   equals `H¹⁶(s)`, the signature is valid.

Security comes from hash-function asymmetry. The verifier can
trivially hash forward; a forger trying to sign a *lower* digit would
need to run `H` backwards, which is exactly what hash functions are
built to prevent.

But an attacker who sees `H⁵(s)` *can* hash forward and claim a
*higher* digit. WOTS+ closes this hole with a **checksum chain**
whose digits move in the opposite direction of the message digits.
Any forward move on a message chain forces a backward move on the
checksum chain — and forging in both directions at once is infeasible.

### Parameters and one-time use

One chain signs a single `log₂(w)`-bit digit; a full message hash
needs several chains in parallel plus the checksum chain. The
Winternitz parameter `w` trades signature size against hashing work:
higher `w` gives shorter signatures but more hashing. Quantroot uses
`w = 256`, the maximum FIPS 205 allows, for the smallest possible
signature.

The catch: **one WOTS+ key signs exactly one message**. Signing a
second message with the same key exposes two intermediate hashes in
the same chain, letting an attacker hash either of them forward to
forge signatures on many other messages. WOTS+ is one-time by
construction, which is why we need the next building block.

---

## Building Block 2: Merkle Trees

XMSS is just "put WOTS+ keys at the leaves of a Merkle tree," so it's
worth spelling out exactly what property we're going to use from
Merkle trees. (If the construction itself is new to you, see
[Wikipedia: Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree)
first.)

A Merkle tree is a binary tree where each internal node is the hash
of its two children concatenated. The single **root** hash commits
to every value at the leaves.

```
                Root = H(H01 || H23)
                 /                \
        H01 = H(H0||H1)      H23 = H(H2||H3)
         /        \            /         \
       H0          H1        H2           H3
```

Any individual leaf can be proven in the tree with `log₂(n)` sibling
hashes — the **authentication path**. To prove leaf 1 is in the tree,
supply `[H0, H23]`; the verifier hashes up from the leaf and checks
against the published root. That logarithmic proof size is the only
property XMSS cares about.

---

## Building Block 3: XMSS (Merkle Tree of WOTS+ Keys)

XMSS — the eXtended Merkle Signature Scheme — is exactly what the
name suggests: a Merkle tree whose leaves are WOTS+ public keys. The
XMSS public key is the Merkle root, a single hash that commits to
every WOTS+ keypair underneath.

```
                      Root
                     /    \
                  H01      H23
                  / \      / \
                H0  H1    H2  H3       ← leaf = hash of WOTS+ pubkey
                |   |     |   |
              WOTS WOTS WOTS WOTS      ← one-time keypairs
               0    1    2    3
```

To sign message `i`, use `WOTS+ keypair i` and attach the
authentication path from leaf `i` to the root. The resulting
signature is `(i, WOTS+ signature, auth path)`. A verifier
reconstructs the WOTS+ public key from the signature, walks the auth
path, and checks the recomputed root against the XMSS public key.

A tree of height `h` gives `2^h` one-time keypairs, so you can sign
up to `2^h` messages under a single XMSS key — one-time signatures
turned into many-time signatures. But every leaf is still a WOTS+
key, and WOTS+ is still one-time, which brings us to the problem the
next section is about.

---

## The State Problem

XMSS requires the signer to remember which leaves have already been
used. In practice, that means maintaining a counter: *"I've signed `k`
messages, the next signature uses leaf `k`, then increment to `k+1`."*
That counter is called **state**, and keeping it correct is suddenly
part of the signer's job.

State is poison for Bitcoin wallets. Consider how a Bitcoin private key
actually gets used:

1. **Restore from seed.** The mnemonic can regenerate the private key,
   but it cannot regenerate "which leaves did I already use." Your first
   post-restore signature might reuse leaf 5 — the same leaf you used
   last week. Silent break.

2. **Two devices, one key.** Laptop and phone both hold the same seed.
   Both maintain their own counter. Both think the next free leaf is 7.
   Each signs a different transaction with leaf 7. An observer who sees
   both signatures can forge a third.

3. **Backup restored.** You restore a backup taken a week ago. The
   counter rewinds. Every signature you make today reuses a leaf you
   used since the backup was taken.

Worst of all, **none of these failures are visible**. A signature made
with a reused leaf is structurally valid. Wallets and nodes will accept
it. The compromise becomes apparent only once an attacker publishes a
forgery — and by then it's too late.

This is why "just use XMSS" was never acceptable for Bitcoin. The scheme
assumes a counter that wallets cannot reliably maintain. We need
something that doesn't require remembering anything at all.

---

## SPHINCS+: Stateless via PRF

The insight that makes SPHINCS+ work: instead of remembering which
leaf you've used, **derive the leaf from the message itself**.

SPHINCS+ uses a **pseudorandom function** (PRF) keyed by a secret —
a function whose output looks random without the key but is perfectly
deterministic with it. Same inputs always produce the same output.

```
leaf_index = PRF(sk_prf, message_hash)
```

```
XMSS (stateful):                    SPHINCS+ (stateless):
  counter = load_from_disk()          leaf = PRF(sk_prf, message)
  leaf    = counter                   sign(message, leaf)
  sign(message, leaf)                 // no state to save
  counter += 1
  save_to_disk(counter)
```

Every failure mode from the previous section evaporates. The same
seed reproduces the same PRF and picks the same leaves. Two devices
with the same key land on the same leaf for the same message.
Restored backups don't affect leaf selection. There is simply nothing
for the signer to track.

### But one XMSS tree isn't big enough

Deterministic leaf selection has one cost: if two messages collide
on the same leaf, you get WOTS+-style reuse. To keep that collision
probability astronomically small, SPHINCS+ needs a *huge* number of
possible leaves — Quantroot targets `2³²`, roughly four billion. A
single XMSS tree of height 32 is impractical to build: generating
the root alone requires hashing every one of its four billion
leaves. The fix is to compose the tree out of smaller trees.

---

## The Hypertree

SPHINCS+ stacks `d` smaller XMSS trees into a **hypertree** — a tree
of trees — with a dedicated few-time signer at the very bottom.

```
Layer d-1 (top):     [XMSS tree]              ← root is the SPHINCS+ public key
                       /        \
Layer d-2:      [XMSS tree]  [XMSS tree]      ← signed by WOTS+ leaves above
                  /    \       /    \
                ...    ...   ...    ...

Layer 0 (bottom):  [XMSS]  [XMSS]  ...  [XMSS]
                     |       |            |
                 [few-time] [few-time] [few-time]  ← signs the message hash
```

Each XMSS tree has small height `h/d`, so its root is cheap to
compute. The "signature" at each layer above 0 is really a WOTS+
signature on the root of the tree directly below. At the very bottom,
each leaf of the lowest XMSS tree points to a fresh instance of a
special few-time scheme that actually signs the message hash. The
next section covers that scheme.

### Signing

1. Use `PRF(sk_prf, message)` to pick a bottom-layer instance.
2. The few-time scheme at that instance signs the message hash.
3. Provide the authentication path from the instance's leaf up to
   the bottom-XMSS root.
4. That root is WOTS+-signed in the layer above; provide its auth
   path.
5. Repeat until you reach the top-XMSS root — the SPHINCS+ public
   key.

Verification runs the chain in reverse: verify the few-time
signature, hash its public key into a leaf, walk the auth path to a
root, verify that root as a WOTS+-signed message in the layer above,
and continue until the top root matches the SPHINCS+ public key.

The `2^h` leaf capacity is spread across `d` layers, so no single
tree is ever bigger than `2^(h/d)`. Signing and verification each
touch one small tree per layer, not one giant tree.

---

## Building Block 4: FORS (Forest of Random Subsets)

FORS — Forest Of Random Subsets — is the few-time scheme at the
bottom of the hypertree. Unlike WOTS+, it signs the full message
hash directly, and it tolerates a small number of reuses before
collapsing.

A FORS key is `k` small Merkle trees, each of height `a`. Each leaf
is a secret value. The FORS public key is the hash of all `k` tree
roots concatenated.

```
Tree 0          Tree 1       ...    Tree k-1
  R₀              R₁                  R_{k-1}
  / \             / \                  / \
 .   .           .   .                .   .
 |   |           |   |                |   |
[*]  .          .   [*]              [*]  .
 ↑                   ↑                ↑
secret              secret           secret
```

To sign a message hash `m`, split it into `k` indices, one per tree.
Each index points at a specific leaf. The FORS signature reveals
**one leaf per tree** (the secret value itself) plus the
authentication path from that leaf up to its tree's root.

```
message_hash → split → (i₀, i₁, ..., i_{k-1})
FORS signature: [ leaf(i₀) + auth₀, ..., leaf(i_{k-1}) + auth_{k-1} ]
```

### Why few-time?

If two messages overlap in *some* but not all trees, an attacker can
mix revealed leaves from both signatures and forge a third message.
The probability of overlap grows quickly with the number of messages
signed under one FORS key, so a single FORS instance is only safe
for a handful of signatures.

SPHINCS+ sidesteps this by using a **fresh FORS key per signature**.
The PRF picks a different bottom-XMSS leaf for almost every message,
and each leaf points to its own FORS instance. The few-time safety
budget resets every time.

---

## Bitcoin's SPHINCS+ Parameters

Quantroot tunes SPHINCS+ parameters for Bitcoin's constraints. Bigger is
not always better — we care about signature size, verification speed,
and how many signatures a single key can safely make.

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `n` | 16 | Hash output size in bytes — security parameter |
| `h` | 32 | Total hypertree height (`2³²` possible signatures) |
| `d` | 4 | Number of XMSS layers (8 levels per layer) |
| `w` | 256 | Winternitz parameter — maximum, shortest WOTS+ sig |
| `k` | 10 | Number of FORS trees |
| `a` | 14 | FORS tree height (`2¹⁴ = 16,384` leaves per tree) |

This produces:

- **32-byte public key** — `pk_seed || pk_root`
- **64-byte secret key** — `sk_seed || sk_prf || pk_seed || pk_root`
- **4,080-byte signature**
- **NIST Category 1 security** — 128-bit classical, 64-bit quantum (Grover's)

### Why these numbers?

- **`n = 16`** (not 32). Halves the signature size vs. the FIPS 205
  defaults. 128-bit classical security is enough — Bitcoin's Schnorr
  already targets the same level.
- **`h = 32`**. Four billion signatures per key. Any realistic Bitcoin
  account will run out of UTXOs before it runs out of leaves.
- **`d = 4`**. Four XMSS layers keeps verification fast — fewer tree
  traversals per signature.
- **`w = 256`**. Maximum Winternitz parameter. Each WOTS+ chain is 256
  hashes long but only three chains are needed (`n/log₂(w) + 1 = 3`).
  Smallest possible signature at the cost of more hashing.

---

## Signature Anatomy

A 4,080-byte SPHINCS+ signature breaks down like this:

```
SPHINCS+ Signature (4,080 bytes)
├── Randomizer R               16 bytes
│   └── used for randomized message hash input
├── FORS signature          2,400 bytes
│   ├── 10 revealed leaves         (10 × 16   =   160 bytes)
│   └── 10 authentication paths    (10 × 14 × 16 = 2,240 bytes)
└── Hypertree signature      1,664 bytes
    ├── Layer 0: WOTS+ sig (48) + auth path (8 × 16 =  128)
    ├── Layer 1: WOTS+ sig (48) + auth path (128)
    ├── Layer 2: WOTS+ sig (48) + auth path (128)
    └── Layer 3: WOTS+ sig (48) + auth path (128)

Total: 16 + 2,400 + 1,664 = 4,080 bytes
```

For comparison, a Schnorr signature is 64 bytes (a 32-byte `R` point plus
a 32-byte `s` scalar). SPHINCS+ is about 64× larger. That's the price of
building a signature out of nothing but hashing.

---

## How Quantroot Uses SPHINCS+

SPHINCS+ is not used alone in Bitcoin. Quantroot's soft fork pairs it
with Schnorr in a **hybrid** Tapscript leaf:

```
<sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG
```

The SPHINCS+ signature itself (all 4,080 bytes) is carried in the
Taproot **annex** — a dedicated witness field — rather than on the script
stack, which has a 520-byte element limit.

Before the soft fork activates, `OP_CHECKSPHINCSVERIFY` is a no-op: the
script still passes or fails based on the Schnorr `OP_CHECKSIG`. That
keeps quantum-insured outputs spendable on today's mainnet and lets
wallets opt in now. After activation, the SPHINCS+ check becomes
mandatory and the output is protected against both classical *and*
quantum key recovery.

For the full integration story — key derivation, sighash construction,
annex encoding, validation weight, the `qr()` descriptor — see
[ARCHITECTURE.md](ARCHITECTURE.md) and [EXPLAINER.md](EXPLAINER.md).

---

## Further Reading

- [NIST FIPS 205](https://csrc.nist.gov/pubs/fips/205/final) — SLH-DSA standard
- [SPHINCS+ paper](https://sphincs.org/) — original research
- [BIP 369](../repos/bips/bip-0369.mediawiki) — `OP_CHECKSPHINCSVERIFY` specification
- [BIP 368](../repos/bips/bip-0368.mediawiki) — Taproot key-path hardening
- [ARCHITECTURE.md](ARCHITECTURE.md) — Quantroot signing pipeline
- [EXPLAINER.md](EXPLAINER.md) — design decisions and tradeoffs
