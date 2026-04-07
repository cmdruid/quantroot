# Glossary

Shared terminology used across Quantroot documentation.

## Cryptographic Primitives

| Term | Definition |
|------|------------|
| **ECDLP** | Elliptic Curve Discrete Logarithm Problem — the mathematical assumption underlying Schnorr/ECDSA. Broken by Shor's algorithm on a quantum computer. |
| **Schnorr signature** | The signature scheme used by Taproot ([BIP 340](../repos/bips/bip-0340.mediawiki)). 64-byte signatures over secp256k1. Quantum-vulnerable. |
| **SPHINCS+** | A hash-based post-quantum signature scheme. Stateless, relies only on hash function security. Standardized as SLH-DSA in [FIPS 205](https://csrc.nist.gov/pubs/fips/205/final). |
| **SLH-DSA** | Stateless Hash-Based Digital Signature Algorithm — the NIST standard name for SPHINCS+. |
| **WOTS+** | Winternitz One-Time Signature Plus — the one-time signature scheme used inside SLH-DSA's hypertree layers. |
| **FORS** | Forest of Random Subsets — the few-time signature scheme used at the bottom of SLH-DSA's hypertree. |
| **Hypertree** | A tree-of-trees structure in SLH-DSA. Each layer is an XMSS tree of WOTS+ signatures; the bottom layer authenticates FORS keys. |
| **Shor's algorithm** | A quantum algorithm that solves the discrete logarithm problem exponentially faster than classical methods. The primary threat to elliptic-curve cryptography. |
| **Grover's algorithm** | A quantum algorithm providing quadratic speedup for unstructured search. Reduces SHA-256 security from 256 bits to ~128 bits. |

## Taproot Concepts

| Term | Definition |
|------|------------|
| **Taproot** | Bitcoin's witness version 1 spending rules ([BIP 341](../repos/bips/bip-0341.mediawiki)). Combines Schnorr signatures, MAST, and key aggregation. |
| **Tapscript** | The script validation rules for Taproot script-path spends ([BIP 342](../repos/bips/bip-0342.mediawiki)). |
| **Key-path spend** | Spending a Taproot output with a single Schnorr signature for the output key. Most efficient and private. |
| **Script-path spend** | Spending a Taproot output by revealing a script from the MAST tree and satisfying it. |
| **Internal key (P)** | The public key used in the taproot tweak construction: `Q = P + hash(TapTweak, P \|\| m) * G`. |
| **Output key (Q)** | The tweaked public key committed to in a Taproot output's witness program. |
| **MAST** | Merkelized Alternative Script Tree — a Merkle tree of script conditions; only the executed branch is revealed on-chain. |
| **Annex** | An optional `0x50`-prefixed witness element in Taproot spends. Stripped before script execution but committed to in the sighash. Used by BIP 368/369 to carry data. |
| **NUMS point** | "Nothing Up My Sleeve" — a public key with no known discrete logarithm. BIP 341 defines `H = lift_x(SHA-256(G))` for script-only outputs. |
| **Taproot tweak** | The formula `Q = P + hash(TapTweak, bytes(P) \|\| merkle_root) * G` that binds the internal key to the output key. |

## BIP 369 Concepts

| Term | Definition |
|------|------------|
| **OP_CHECKSPHINCSVERIFY** | The new Tapscript opcode (`0xB3`, formerly `OP_NOP4`) that verifies SPHINCS+ signatures from the annex. |
| **Annex cursor** | An internal counter tracking the next SPHINCS+ signature to consume. Advances on each executed `OP_CHECKSPHINCSVERIFY`. All signatures must be consumed by script completion. |
| **Hybrid script** | A Tapscript containing both Schnorr (`OP_CHECKSIGVERIFY`) and SPHINCS+ (`OP_CHECKSPHINCSVERIFY`) checks. Provides defense-in-depth. |
| **SPHINCS+ sighash** | The BIP 342 Tapscript sighash with `sha_annex` omitted (to break the circular dependency of a signature hashing itself). |
| **Signing order** | SPHINCS+ signatures must be created first, then the annex is built, then Schnorr signs over the sighash that includes `sha_annex`. |
| **Quantum insurance** | The strategy of embedding hidden SPHINCS+ tapleaves in Taproot outputs today, to be activated if a quantum threat emerges. |
| **Validation weight** | Per-script budget from BIP 342. Each SPHINCS+ sigop costs 3,200 (64x Schnorr's 50), reflecting actual CPU cost. |

## BIP 368 Concepts

| Term | Definition |
|------|------------|
| **Key-path hardening** | Requiring the internal key `P` to be disclosed and verified in key-path spends, preventing quantum forgery via NUMS points. |
| **NUMS ban** | After activation, key-path spends with a known NUMS point as internal key are consensus-invalid. |
| **Bare-key output** | A Taproot output where `Q` was not constructed using the taproot tweak formula. Disabled post-activation because the tweak cannot be verified. |
| **Internal key disclosure** | The annex type `0x02` payload: `0x50 \|\| 0x02 \|\| P` (34 bytes) or `0x50 \|\| 0x02 \|\| P \|\| merkle_root` (66 bytes). |

## Deployment

| Term | Definition |
|------|------------|
| **BIP 9** | Version bits signaling mechanism for soft-fork activation ([BIP 9](../repos/bips/bip-0009.mediawiki)). |
| **Speedy trial** | A BIP 9 variant with a short signaling window, used for rapid activation when there is strong consensus. |
| **Buried deployment** | A deployment that is always active from a specific height (used for regtest testing). |
| **Soft fork** | A backward-compatible consensus rule change. New rules are a subset of old rules; non-upgraded nodes accept all valid blocks. |
