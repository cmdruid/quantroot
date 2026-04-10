# Architecture

How the Quantroot soft fork is structured, from key derivation to
on-chain spending.

## Data Flow

```
Wallet Seed (BIP 39 mnemonic)
    │
    ├─→ BIP 32 Master Key (privkey + chaincode)
    │       │
    │       ├─→ m/395'/0'/0' ─→ Account Extended Key (qpub/qprv)
    │       │                       │
    │       │                       ├─→ /0/i ─→ Child EC Key (per address)
    │       │                       └─→ /1/i ─→ Change EC Key
    │       │
    │       └─→ HMAC-SHA512("Sphincs seed", master || account_path)
    │               │
    │               └─→ SPHINCS+ Key (one per account, reused across addresses)
    │
    └─→ Quantum-Insured Address
            │
            ├─→ Internal key: child EC key (BIP 32 derived)
            ├─→ Hybrid tapleaf: <SPHINCS+ pk> OP_CHECKSPHINCSVERIFY OP_DROP
            │                   <child EC pk> OP_CHECKSIG
            └─→ Output key: Q = child + H(TapTweak, child || leaf_hash) * G
```

## Spending Paths

### Key-Path (Normal Operation)

```
Witness: [schnorr_sig (64B), annex (66B)]
Annex:   0x50 || 0x02 || internal_key (32B) || merkle_root (32B)
```

- Efficient: ~130 bytes total
- BIP 368 requires internal key disclosure post-activation
- Hybrid tapleaf never revealed on-chain

### Script-Path (Quantum Emergency)

```
Witness: [schnorr_sig (64B), script (69B), control_block (33B), annex (4083B)]
Annex:   0x50 || 0x04 || compact_size(1) || sphincs_sig (4080B)
Script:  <sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG
```

- Both signatures required
- SPHINCS+ signs first (sighash excludes sha_annex)
- Schnorr signs second (sighash includes sha_annex)
- Triggered via `sphincsspend` RPC

## Signing Pipeline

```
sphincsspend RPC
    │
    ├─→ 1. Select QI UTXOs (CCoinControl, GetScriptPubKeyMans)
    ├─→ 2. CreateTransaction (unsigned)
    ├─→ 3. Build PSBT
    ├─→ 4. FillPSBT (sphincs_emergency=true)
    │       │
    │       ├─→ Pass 1: QI SPKMs sign (HasSphincsKey=true)
    │       │       │
    │       │       ├─→ SPHINCS+ pre-sign (sighash with spend_type=0x03, no sha_annex)
    │       │       ├─→ Build type 0x04 annex
    │       │       └─→ Schnorr sign (sighash with sha_annex committed)
    │       │
    │       └─→ Pass 2: Non-QI SPKMs (already-signed inputs skipped)
    │
    ├─→ 5. FinalizePSBT
    └─→ 6. Broadcast (CommitTransaction)
```

## PSBT Fields (BIP 377)

| Type | Field | Key Data | Value |
|------|-------|----------|-------|
| Input 0x1d | SPHINCS+ Pubkey | xonly + leaf_hash | 32B SPHINCS+ pubkey |
| Input 0x1e | SPHINCS+ Signature | xonly + leaf_hash | 4080B signature |
| Input 0x1f | Taproot Annex | (none) | Assembled annex bytes |
| Output 0x09 | SPHINCS+ Pubkey | xonly + leaf_hash | 32B SPHINCS+ pubkey |

## File Map

### Consensus (`repos/bitcoin/src/`)

| File | What it does |
|------|-------------|
| `script/interpreter.cpp` | OP_CHECKSPHINCSVERIFY handler, annex parsing, SPHINCS+ sighash |
| `script/script.h` | Opcode 0xB3, validation weight 3200 |
| `validation.cpp` | Co-activation enforcement |
| `policy/policy.cpp` | Annex type 0x02/0x04 standardness |
| `kernel/chainparams.cpp` | Deployment params, QI version bytes |
| `crypto/sphincsplus/` | SLH-DSA FIPS 205 C library |

### Wallet (`repos/bitcoin/src/wallet/`)

| File | What it does |
|------|-------------|
| `sphincskeys.h/.cpp` | SphincsKey class, HMAC derivation, secure memory |
| `rpc/sphincs.cpp` | 8 RPCs: createsphincskey through sphincsspend |
| `scriptpubkeyman.cpp` | FillPSBT two-pass, SPHINCS+ key storage |
| `walletdb.cpp` | DB persistence with integrity hash |

### Common (`repos/bitcoin/src/`)

| File | What it does |
|------|-------------|
| `qextkey.h/.cpp` | QExtPubKey/QExtKey, base58 encode/decode |
| `script/descriptor.cpp` | QRDescriptor (qr()), QISDescriptor (qis()) |
| `script/sign.cpp` | SPHINCS+ pre-signing, hybrid fallback, annex construction |
| `psbt.h/.cpp` | PSBT fields 0x1d-0x1f/0x09, sphincs_emergency flag |
