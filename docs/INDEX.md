# Documentation Index

## Reading Paths

### New here?

1. [GETTING_STARTED.md](GETTING_STARTED.md) — clone, build, demo in 5 minutes
2. [OVERVIEW.md](OVERVIEW.md) — what Quantroot does and why
3. [ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit together

### Deep Dive

1. [OVERVIEW.md](OVERVIEW.md) — problem, solution, architecture
2. [ARCHITECTURE.md](ARCHITECTURE.md) — data flow, signing pipeline, file map
3. BIP specifications (below)
4. [GLOSSARY.md](GLOSSARY.md) for reference

## BIP Specifications

Canonical BIP specifications for this repository live in [`../repos/bips/`](../repos/bips).

The core proposals implemented by this project:

| Document | Description |
|----------|-------------|
| [OP_CHECKSPHINCSVERIFY draft](../repos/bips/bip-0369.mediawiki) | `OP_CHECKSPHINCSVERIFY` — post-quantum signature verification in Tapscript |
| [Taproot key-path hardening draft](../repos/bips/bip-0368.mediawiki) | Quantum-resistant key-path hardening for Taproot |
| [OP_CHECKSPHINCSVERIFY test vectors](../repos/bips/bip-0369/test-vectors.json) | Keypairs, sighash, signatures, valid/invalid transactions |
| [Taproot key-path hardening test vectors](../repos/bips/bip-0368/test-vectors.json) | Annex encoding, NUMS rejection, tweak verification |

### Wallet-layer proposals (draft):

| Document | Description |
|----------|-------------|
| [Quantum-insured extended keys draft](../repos/bips/bip-0395.mediawiki) | Quantum-insured extended keys (`qpub`/`qprv`) for BIP 32 |
| [PSBT SPHINCS+ draft](../repos/bips/bip-0377.mediawiki) | PSBT extensions for SPHINCS+ signatures and Taproot annex data |

## Reference BIPs

Background specifications that Quantroot builds upon:

| Document | Description |
|----------|-------------|
| [BIP 340](../repos/bips/bip-0340.mediawiki) | Schnorr signatures for secp256k1 |
| [BIP 341](../repos/bips/bip-0341.mediawiki) | Taproot (SegWit v1 spending rules) |
| [BIP 342](../repos/bips/bip-0342.mediawiki) | Tapscript validation rules |
| [BIP 9](../repos/bips/bip-0009.mediawiki) | Version bits activation mechanism |
| [BIP 65](../repos/bips/bip-0065.mediawiki) | `OP_CHECKLOCKTIMEVERIFY` (NOP redefinition precedent) |
| [BIP 112](../repos/bips/bip-0112.mediawiki) | `OP_CHECKSEQUENCEVERIFY` (NOP redefinition precedent) |
| [BIP 343](../repos/bips/bip-0343.mediawiki) | Taproot activation (speedy trial precedent) |
| [BIP 360](../repos/bips/bip-0360.mediawiki) | Pay-to-Merkle-Root (related quantum-resistance proposal) |

## Document Map

| Document | Purpose |
|----------|---------|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Clone, build, demo in 5 minutes |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Data flow, signing pipeline, file map |
| [OVERVIEW.md](OVERVIEW.md) | Problem statement, solution design, architecture |
| [CHANGES.md](CHANGES.md) | Change inventory (files, lines, by area) |
| [GLOSSARY.md](GLOSSARY.md) | Shared terminology and definitions |

## Scope Boundary

This knowledge base covers:

- Domain semantics and the quantum threat model
- BIP specifications in `repos/bips` and their design rationale
- Protocol behavior, sighash construction, annex format
- Trust assumptions and activation strategy

This knowledge base does NOT cover:

- Contributing and conventions — [CONTRIBUTING.md](../CONTRIBUTING.md)
- Testing and demos — [test/](../test/README.md)
- Implementation plans — [dev/](../dev/README.md)
