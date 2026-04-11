# Understanding SPHINCS+ Signatures

SPHINCS+ (standardized as SLH-DSA in NIST FIPS 205) is a post-quantum
digital signature scheme. It replaces the elliptic-curve math behind ECDSA
and Schnorr with nothing but **hash functions** — the same primitives you
already know from `SHA-256`, HMAC, and block explorers. That substitution
is what makes it safe against quantum computers.

This guide walks from the ground up: what's wrong with today's signatures,
how hashing can authenticate a message, how hash chains become a real
signature scheme, and how SPHINCS+ stitches them all together into a
practical, stateless construction suitable for Bitcoin wallets.

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

## Why Hash-Based Signatures?

Every signature scheme rests on some math problem that is hard to reverse.
For Bitcoin's current signatures — ECDSA and Schnorr — that problem is the
**elliptic curve discrete logarithm problem** (ECDLP).

### How ECDSA works (at a glance)

A private key is a random 256-bit integer `d`. The public key is a point
`P = d·G` on the `secp256k1` curve — you multiply the generator point `G`
by the secret scalar `d`. Multiplication on the curve is fast. But the
reverse direction — given `P` and `G`, recover `d` — is believed to be
infeasible on classical computers. The best known classical attack takes
roughly `2¹²⁸` operations, which is out of reach.

When you sign a message, you combine `d` with a per-message nonce and the
message hash in a way that lets a verifier check, using only `P`, that the
signer knew `d` without revealing it. The whole scheme's security reduces
to "recovering `d` from `P` is hard."

### The quantum problem

In 1994 Peter Shor published an algorithm that runs on a quantum computer
and solves discrete-log (and integer factoring) in **polynomial time**. A
sufficiently large, fault-tolerant quantum computer running Shor's
algorithm could recover the private key `d` from the public key `P` in
hours instead of `2¹²⁸` operations.

This doesn't just break ECDSA — it breaks everything in the same family:
Schnorr, DSA, Diffie-Hellman, RSA. Any scheme whose security depends on
discrete-log or factoring is at risk the moment a large quantum computer
exists.

### Why hashing survives

Hash functions like SHA-256 don't rely on algebraic structure. They are
designed to be:

- **Preimage-resistant**: given `H(x)`, find `x` → infeasible.
- **Second-preimage-resistant**: given `x`, find `x' ≠ x` with `H(x') = H(x)` → infeasible.
- **Collision-resistant**: find any `x ≠ x'` with `H(x) = H(x')` → infeasible.

The best known quantum attack is **Grover's algorithm**, which speeds up
brute-force search by only a **quadratic** factor — `2ⁿ` becomes `2^(n/2)`.
That's a real effect but easy to absorb: double the hash output size and
you're back where you started. A 256-bit hash still provides 128-bit
security against a quantum attacker.

So the plan is: build a signature scheme where the only hard problem is
"invert a hash function," and we get post-quantum security for free.

---

## Building Block 1: WOTS+ (Hash Chains)

The Winternitz One-Time Signature (WOTS+) scheme is the first real
hash-based signature we'll meet. It starts from an idea you have
probably already seen in Bitcoin: a **hash commitment**.

### Starting point: hash commitments

To prove later that you knew a secret `s`, publish `H(s)` today. When
you eventually reveal `s`, anyone can compute `H(s)` and check it
against the value you committed to. Nobody can forge this because
inverting `H` is infeasible.

```
commit → H(s)       (published today, keeps s secret)
reveal → s          (published later)
verify → H(s) == commit ?
```

Lightning Network invoices work exactly this way. The receiver picks a
random preimage `s`, hashes it, and puts `H(s)` — the *payment hash* —
into the invoice. A payment is routed across the network with the
condition "release funds only against a preimage that hashes to `H(s)`."
When the receiver reveals `s` to claim the payment, every routing node
along the path can independently verify `H(s)` and forward the
settlement. No signature, no key exchange — just a hash.

A single commitment like this isn't yet a digital signature: it only
proves knowledge of one pre-agreed secret, once. WOTS+ takes the same
primitive and stretches it into something much more powerful by
chaining many hashes together and using the *position* in the chain to
encode a message.

### The core trick: a hash chain

Pick a random secret `s`. Apply the hash function `H` to it `w` times in
a row:

```
s → H(s) → H(H(s)) → ... → H^w(s)
```

The secret key is `s`. The public key is `H^w(s)` — the end of the chain.
Because hashing is one-way, publishing `H^w(s)` reveals nothing about `s`.

Now here is the clever part. To "sign" a digit `d` (where `0 ≤ d < w`),
you reveal the intermediate hash `H^d(s)`:

```
signature for digit d:   H^d(s)
```

A verifier receives your signature and applies `H` an additional `w - d`
times:

```
H^(w-d)( H^d(s) ) = H^w(s) = public_key   ✓
```

If it matches the known public key, the signature is valid. A forger who
wants to sign a higher digit `d' > d` would have to **invert** `H` to move
backwards along the chain, which is infeasible.

### What is `w`?

The **Winternitz parameter** `w` controls the chain length and the
tradeoff between signature size and computation:

- **Higher `w`** → longer chains → fewer chains needed → shorter
  signatures, but more hashing to sign and verify.
- **Lower `w`** → shorter chains → more chains needed → larger
  signatures, but less hashing.

For Quantroot, `w = 256`, the maximum allowed by FIPS 205. Each chain is
256 hashes long, and fewer chains are needed, giving the smallest
signature at the cost of more hashing per sign/verify.

### Signing a whole message

One chain signs one `log₂(w)`-bit digit. To sign a full `n`-byte message
hash, WOTS+ runs several chains in parallel — one per digit — plus a
short **checksum** chain whose digits move in the opposite direction, so
any forger who tries to advance one message digit would also have to
hash *backward* on the checksum chain, which is infeasible. The
signature is the collection of intermediate hashes `H^dᵢ(sᵢ)`, one per
chain. The public key is the collection of chain endpoints.

The catch is: **you can only ever sign one message**. If you sign a
second message with the same WOTS+ key, an attacker sees two
intermediate hashes in the same chain and can hash either of them
forward to any further digit — enough to forge a signature on many
other messages. WOTS+ is **one-time by construction**.

One-time signatures are not very useful by themselves. We need a way to
combine many WOTS+ keys behind a single public key.

---

## Building Block 2: Merkle Trees

Merkle trees are a general-purpose primitive, older than Bitcoin itself.
XMSS — the next building block — is simply "put WOTS+ keys at the leaves
of a Merkle tree," so it's worth a brief refresher.

### The construction

A Merkle tree is a binary tree where:

- **Leaves** contain hashes of arbitrary values (in our case, WOTS+ public keys).
- **Internal nodes** contain the hash of their two children concatenated.
- **Root** is a single hash that commits to every leaf.

```
                Root = H(H01 || H23)
                 /                \
        H01 = H(H0||H1)      H23 = H(H2||H3)
         /        \            /         \
       H0          H1        H2           H3
       |           |          |           |
     value_0    value_1    value_2     value_3
```

### Authentication paths

To prove that a specific leaf `value_1` is included in the tree, you
provide the **authentication path**: the sibling hashes at each level on
the way from the leaf to the root.

```
Proving leaf 1 (value_1):

   Auth path = [H0, H23]

   Verifier computes:
     leaf_hash = H(value_1)           (hash the claimed leaf)
     node      = H(H0 || leaf_hash)   (combine with sibling H0)
     root'     = H(node || H23)       (combine with sibling H23)

   Check: root' == known_root ?  ✓
```

The proof size is `log₂(n)` hashes for a tree with `n` leaves. A million
leaves costs twenty hashes. That logarithmic scaling is why Merkle trees
show up anywhere you need to commit to lots of data under a single root:
Bitcoin blocks, Git objects, certificate transparency logs — and XMSS.

---

## Building Block 3: XMSS (Merkle Tree of WOTS+ Keys)

XMSS — the eXtended Merkle Signature Scheme — is exactly what the section
heading says: a Merkle tree whose leaves are WOTS+ public keys.

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

The XMSS public key is just the **Merkle root**. That one hash commits to
every WOTS+ public key at the leaves.

### Signing with XMSS

To sign message number `i`:

1. Pick an unused leaf — say, leaf `i`.
2. Sign the message with `WOTS+ keypair i`.
3. Include the **authentication path** from leaf `i` to the root.

The signature is `(i, WOTS+ signature, auth path)`. To verify:

1. Reconstruct the WOTS+ public key from the signature.
2. Hash it to get `leaf_hash`.
3. Walk up the auth path, hashing sibling-by-sibling, until you reach a root.
4. Compare against the known XMSS root.

A tree of height `h` gives you `2^h` one-time keypairs, so you can sign
up to `2^h` messages under a single public key. You've turned one-time
signatures into many-time signatures.

### What could go wrong

Every leaf is still a WOTS+ key. WOTS+ is still one-time. Which brings
us to the problem the next section is about.

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

Here's the insight that makes SPHINCS+ work:

> Instead of remembering which leaf you've used, derive the leaf from the
> message itself.

Specifically, SPHINCS+ uses a pseudorandom function keyed by a secret:

```
leaf_index = PRF(sk_prf, message_hash)
```

The same message always maps to the same leaf. Different messages map to
essentially random, uncorrelated leaves. No counter. No disk. No
synchronization between devices.

### Stateful vs stateless, side by side

```
XMSS (stateful):                    SPHINCS+ (stateless):
  counter = load_from_disk()          leaf = PRF(sk_prf, message)
  leaf    = counter                   sign(message, leaf)
  sign(message, leaf)                 // no state to save
  counter += 1
  save_to_disk(counter)
```

This one change gets us past every failure mode from the previous
section. Same seed reproduces the same PRF and picks the same leaves.
Two devices with the same key pick the same leaf for the same message.
Restored backups don't affect leaf selection. There is simply nothing
for the signer to track.

### But one XMSS tree isn't big enough

A deterministic leaf selection has a price: if two messages happen to
collide on the same leaf, you do get WOTS+-style reuse, with all the
forgeability that implies. To make that collision probability
astronomically small you need a *huge* number of possible leaves —
Quantroot targets `2³²`, roughly four billion.

A single XMSS tree of height 32 is impractical: generating the root
requires hashing every one of its four billion leaves. Signing the first
message would take forever.

The fix is to build the tree out of smaller trees.

---

## The Hypertree

SPHINCS+ stacks multiple XMSS trees into a **hypertree** — a tree of
trees — with FORS instances at the very bottom:

```
Layer d-1 (top):     [XMSS tree]            ← root is the SPHINCS+ public key
                       /        \
Layer d-2:      [XMSS tree]  [XMSS tree]    ← each signed by a leaf in the layer above
                  /    \       /    \
                ...    ...   ...    ...

Layer 0 (bottom): [XMSS]   [XMSS]   ...   [XMSS]   ← each leaf signs a FORS key
                    |        |               |
                  [FORS]   [FORS]         [FORS]   ← signs the actual message hash
```

Each XMSS tree is small (height `h/d`), so computing its root is cheap.
The "signature" at each layer above 0 is really a WOTS+ signature on the
root hash of the tree directly below. A leaf in the bottom XMSS tree is
the hash of a FORS public key; that FORS key is what actually signs the
message.

### Signing

1. Hash the message and use `PRF(sk_prf, ·)` to pick:
   - a FORS instance (determines which bottom-XMSS leaf to land on), and
   - a message hash for FORS to sign.
2. FORS signs the message hash, producing a FORS signature.
3. The FORS public key is a leaf in the bottom XMSS tree. Provide the
   authentication path up to that tree's root.
4. That root is signed by a WOTS+ key in the XMSS tree one layer up.
   Provide the authentication path up to *its* root.
5. Repeat until you reach the top XMSS root — the SPHINCS+ public key.

### Verifying

Run the same chain in reverse:

1. Verify the FORS signature against the message hash → FORS public key.
2. Hash it into a leaf → walk the bottom XMSS auth path → get a root.
3. Verify that root as a WOTS+ signed message in the layer above → get a leaf → walk *that* auth path → get another root.
4. Continue until you reach the top root. It must equal the SPHINCS+
   public key.

The genius of the construction is that a single `2^h` leaf capacity is
spread across `d` layers, so no single tree is ever bigger than `2^(h/d)`.
Signing touches one small tree per layer, not one giant tree. Verification
does the same amount of work.

The one remaining piece is the thing at the very bottom — the scheme
that actually signs the message hash.

---

## Building Block 4: FORS (Forest of Random Subsets)

FORS — Forest Of Random Subsets — is the signature scheme at the bottom
of the hypertree. It signs the message hash directly, and it is a
**few-time** signature: safe to sign a small number of messages rather
than exactly one.

### Structure

A FORS key is `k` small Merkle trees, each of height `a`. Each tree has
`2^a` leaves, and each leaf is a secret value. The FORS public key is the
hash of all `k` tree roots concatenated.

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

### Signing

To sign a message hash `m`, split `m` into `k` indices, one per tree.
Each index points at a specific leaf. To produce the FORS signature,
reveal **one leaf per tree** (the secret value itself), plus the
authentication path to its tree's root.

```
message_hash → split → (i₀, i₁, ..., i_{k-1})
FORS signature: [ leaf(i₀) + auth₀, leaf(i₁) + auth₁, ..., leaf(i_{k-1}) + auth_{k-1} ]
```

### Why "few-time"?

Different messages typically produce different indices — a different
leaf revealed in each tree. But if two messages happen to overlap in
*some* but not all trees, an attacker can mix revealed leaves from both
signatures and cobble together a forgery for a third message.

The probability of that happening grows quickly with the number of
messages signed, so FORS is only safe for a small number of signatures
under the same key. SPHINCS+ handles this by using a **fresh FORS key
per signature** — which is exactly what the hypertree provides. Each
bottom-XMSS leaf points to its own FORS instance, and the PRF makes
sure that different messages almost always land on different leaves.
The few-time safety budget resets with every signature.

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
