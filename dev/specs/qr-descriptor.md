# Specification: `qr()` Quantum-Insured Descriptor

- Status: draft
- Date: 2026-04-06
- Author: cmdruid

## Summary

Define `qr()` as a top-level output descriptor for quantum-insured Taproot
addresses. It is a drop-in replacement for `tr()` that accepts a `qpub`
extended key and automatically constructs the hybrid SPHINCS+ tapleaf.

## Motivation

The current approach requires verbose, duplicated descriptor syntax:

```
tr(xpub/0/*, qis(SPHINCS_HEX, xpub/0/*))
```

This is error-prone (the xpub path appears twice), exposes implementation
details (the raw SPHINCS+ hex), and doesn't signal at the descriptor level
that the output is quantum-insured.

The `qr()` descriptor simplifies this to:

```
qr(qpub/0/*)
```

The SPHINCS+ key is embedded in the `qpub`, so no separate hex argument is
needed. The hybrid tapleaf is constructed automatically.

## Syntax

```
qr(KEY)
qr(KEY, SCRIPT_TREE)
```

Where:
- `KEY` is a quantum-insured key expression — either a `qpub`/`qprv` extended
  key with optional derivation path, or a raw key pair (32-byte EC x-only +
  32-byte SPHINCS+ pubkey in a format TBD).
- `SCRIPT_TREE` is an optional user-defined script tree, following the same
  `{left, right}` nesting syntax as `tr()`. These are additional tapleaves
  beyond the auto-generated hybrid leaf.

### Minimal form (most common)

```
qr(qpub)
qr(qpub/0/*)
qr(qprv/0/*)
```

Produces a Taproot output with:
- Internal key: the EC child key derived from the qpub at the given index
- One tapleaf: the hybrid SPHINCS+ script (auto-generated)

### Extended form (additional tapleaves)

```
qr(qpub/0/*, {pk(KEY2), multi_a(2, K3, K4)})
```

Produces a Taproot output with:
- Internal key: EC child key from qpub
- Hybrid SPHINCS+ leaf (auto-generated, always present)
- Additional user-defined tapleaves from the script tree argument

The hybrid leaf is always the first leaf in the MAST tree. User-defined
leaves are siblings.

## Expansion

Given `qr(qpub/0/*)` at child index `i`:

```
child_ec_key   = BIP32_Derive(qpub.xpub, i)
child_xonly    = XOnlyPubKey(child_ec_key)
sphincs_pubkey = qpub.sphincs_pubkey  (constant, from qpub)

hybrid_script  = <sphincs_pubkey> OP_CHECKSPHINCSVERIFY OP_DROP
                 <child_xonly> OP_CHECKSIG

leaf_hash      = TapLeaf(0xC0, hybrid_script)
merkle_root    = leaf_hash  (single leaf, or combined with user tree)

output_key     = child_xonly + hash(TapTweak, child_xonly || merkle_root) * G
```

The output is a standard Taproot (witness v1) scriptPubKey:
```
OP_1 <32-byte output_key>
```

## Key Expression

The `qr()` descriptor accepts `qpub` and `qprv` key types. These are
quantum-insured extended keys defined in BIP 395:

- `qpub`: 110 bytes (BIP 32 xpub + 32-byte SPHINCS+ pubkey), base58 `Q1...`
- `qprv`: 142 bytes (BIP 32 xprv + 64-byte SPHINCS+ secret), base58 `Q1...`

Derivation paths follow BIP 32 syntax:
```
qpub/0/*       Non-hardened child derivation (external addresses)
qpub/1/*       Non-hardened child derivation (internal/change addresses)
qpub/0/7       Specific child index
```

The EC component derives per BIP 32 (child key changes per index). The
SPHINCS+ component is carried unchanged through all derivations.

## Relationship to `tr()` and `qis()`

| Descriptor | Key type | SPHINCS+ leaf | Use case |
|------------|----------|---------------|----------|
| `tr(xpub)` | xpub | None | Standard Taproot |
| `tr(xpub, qis(HEX, xpub))` | xpub | Manual | Advanced: custom trees with SPHINCS+ |
| `qr(qpub)` | qpub | Automatic | Standard quantum-insured Taproot |
| `qr(qpub, {pk(K)})` | qpub | Automatic + extra leaves | Quantum-insured with custom scripts |

`qis()` remains available as a low-level script fragment for users who need
fine-grained control over their Taproot tree construction. `qr()` is the
high-level descriptor for the standard quantum insurance pattern.

## Output Type

`qr()` produces `OutputType::BECH32M` (Taproot, witness v1). Addresses are
standard bech32m — indistinguishable from `tr()` outputs on-chain.

## GetOutputType

```cpp
std::optional<OutputType> QRDescriptor::GetOutputType() const {
    return OutputType::BECH32M;
}
```

## IsSolvable / IsSingleType

- `IsSolvable()`: true (the descriptor provides enough information to
  construct a spending witness)
- `IsSingleType()`: true (always produces exactly one script type)

## Signing

When the wallet signs a spend from a `qr()` output:

### Key-path spend (normal operation)
Same as `tr()`. Schnorr signature for the output key. Post-BIP 368, includes
the annex with internal key disclosure (type `0x02`).

### Script-path spend (quantum emergency)
The wallet:
1. Computes the SPHINCS+ sighash (BIP 342 minus `sha_annex`)
2. Signs with the SPHINCS+ secret key from the `qprv`
3. Builds the annex (`0x50 || 0x04 || compact_size(1) || sphincs_sig`)
4. Computes the Schnorr sighash (BIP 342, includes `sha_annex`)
5. Signs with the EC private key
6. Witness: `[schnorr_sig] [hybrid_script] [control_block] [annex]`

## String Representation

```
qr(Q1CFYH2UTfN9JFK.../0/*)
qr(Q1CFYH2UTfN9JFK.../0/*)#checksum
```

The `ToString()` method produces the descriptor string with the qpub in
base58 format. Checksums follow the standard descriptor checksum algorithm
(same PolyMod as `tr()`).

## Wallet Integration

### `createsphincskey` RPC
After creating the SPHINCS+ key, registers a `qr()` descriptor:
```
qr(qpub/0/*)    → external (receiving) addresses
qr(qpub/1/*)    → internal (change) addresses
```

Both registered as active for `OutputType::BECH32M`.

### `getnewaddress bech32m`
Returns the next address from the active `qr()` descriptor.

### `importqpub`
Parses the qpub, creates a watch-only `qr()` descriptor, registers as active.

### `importqprv`
Parses the qprv, creates a signing `qr()` descriptor with private key.

## Implementation

### Parser (`descriptor.cpp`)

Add `qr()` parsing in `ParseScript()` at `ParseScriptContext::TOP`:

```cpp
if (ctx == ParseScriptContext::TOP && Func("qr", expr)) {
    // Parse qpub/qprv key expression (with derivation path)
    auto key_arg = Expr(expr);
    auto qkeys = ParseQPubKey(key_exp_index, key_arg, out, error);

    // Optional script tree (same as tr())
    std::vector<std::unique_ptr<DescriptorImpl>> subscripts;
    std::vector<int> depths;
    if (expr.size() && Const(",", expr)) {
        // Parse script tree same as tr()
        // ...
    }

    return std::make_unique<QRDescriptor>(
        std::move(qkeys), std::move(subscripts), depths);
}
```

### QRDescriptor class (`descriptor.cpp`)

```cpp
class QRDescriptor final : public DescriptorImpl {
    std::vector<int> m_depths;
    std::vector<unsigned char> m_sphincs_pubkey;  // 32 bytes, from qpub

    std::vector<CScript> MakeScripts(
        const std::vector<CPubKey>& keys,
        std::span<const CScript> scripts,
        FlatSigningProvider& out) const override
    {
        XOnlyPubKey xpk(keys[0]);

        // Build the hybrid SPHINCS+ script
        CScript hybrid;
        hybrid << m_sphincs_pubkey << OP_CHECKSPHINCSVERIFY << OP_DROP;
        hybrid << ToByteVector(xpk) << OP_CHECKSIG;

        // Build Taproot tree: hybrid leaf first, then user scripts
        TaprootBuilder builder;
        int hybrid_depth = m_depths.empty() ? 0 : 1;
        builder.Add(hybrid_depth, hybrid, TAPROOT_LEAF_TAPSCRIPT);

        for (size_t i = 0; i < m_depths.size(); ++i) {
            builder.Add(m_depths[i] + 1, scripts[i], TAPROOT_LEAF_TAPSCRIPT);
        }

        builder.Finalize(xpk);
        WitnessV1Taproot output = builder.GetOutput();
        out.tr_trees[output] = builder;
        return Vector(GetScriptForDestination(output));
    }
};
```

### ParseQPubKey (`descriptor.cpp`)

New key parser that accepts qpub/qprv base58 strings and extracts both the
EC extended key (for BIP 32 derivation) and the SPHINCS+ pubkey (stored on
the descriptor).

### Key expression in Expand

During descriptor expansion at index `i`:
- EC key: derived via BIP 32 at index `i` (same as `tr()`)
- SPHINCS+ key: constant (stored in `m_sphincs_pubkey`), not derived

## Backward Compatibility

- `qr()` is a new descriptor type. Old wallets don't recognize it.
- Outputs produced by `qr()` are standard Taproot (witness v1) — fully
  backward compatible on-chain.
- `tr()` with `qis()` continues to work for advanced users.
- Existing `qr()` wallets can be downgraded to `tr()` by stripping the
  SPHINCS+ component (losing quantum insurance but keeping funds spendable).

## Test Plan

- Parse `qr(qpub/0/*)` → produces valid Taproot output
- Parse `qr(qprv/0/*)` → same output as `qr(qpub/0/*)`
- Expand at index 0, 1, 2 → different addresses (EC key varies)
- Expand at index 0, 1, 2 → same SPHINCS+ key in all hybrid scripts
- `qr()` output matches `tr(xpub, qis(HEX, xpub))` output for same keys
- Checksum roundtrip: `ToString()` → `Parse()` → same expansion
- `qr()` at non-TOP context → parse error
- Invalid qpub → parse error
- `getnewaddress bech32m` with active `qr()` → QI address
- Fund + spend from `qr()` address → witness has BIP 368 annex
