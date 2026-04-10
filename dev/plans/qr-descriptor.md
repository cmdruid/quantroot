# Implementation Plan: `qr()` Descriptor

- Status: proposed
- Date: 2026-04-06
- Owner: cmdruid
- Spec: `repos/bips/bip-0395.mediawiki (qr() descriptor section)`

## Context

The current `qis()` descriptor syntax is verbose and requires duplicating the
xpub derivation path. The `qr()` descriptor replaces this with a clean
top-level descriptor that accepts a `qpub` and auto-constructs the hybrid
SPHINCS+ tapleaf. This is a hard-cut — `qis()` stays for advanced users,
`qr()` becomes the standard.

## Changes

### 1. Add `QRDescriptor` class and parser

**File**: `repos/bitcoin/src/script/descriptor.cpp`

Add `QRDescriptor` class (modeled on `TRDescriptor`):

```cpp
class QRDescriptor final : public DescriptorImpl {
    std::vector<int> m_depths;           // user script tree depths
    std::vector<unsigned char> m_sphincs_pubkey; // 32 bytes, from qpub

    MakeScripts():
      1. Get child x-only key from keys[0]
      2. Build hybrid script: <sphincs_pk> CSV OP_DROP <child_xonly> OP_CHECKSIG
      3. TaprootBuilder: add hybrid leaf at appropriate depth
      4. Add user scripts (from m_depths / scripts span) as siblings
      5. Finalize with child_xonly as internal key
      6. Store builder in out.tr_trees
      7. Return Taproot scriptPubKey
};
```

Add parser in `ParseScript()` at `ParseScriptContext::TOP`:
- `Func("qr", expr)` → parse qpub key expression + optional script tree
- Key expression: new `ParseQPubKey()` function that accepts base58 qpub/qprv
  strings, extracts `CExtPubKey` for BIP 32 derivation and stores SPHINCS+
  pubkey on the descriptor

The qpub key expression supports derivation paths: `qpub/0/*`, `qpub/1/*`.

### 2. Add `ParseQPubKey()` key parser

**File**: `repos/bitcoin/src/script/descriptor.cpp`

New function that:
1. Attempts to decode the key string as a qpub via `DecodeQExtPubKey()`
2. If that fails, attempts qprv via `DecodeQExtKey()` → neutered to qpub
3. Extracts the `CExtPubKey` component for standard BIP 32 derivation
4. Stores the 32-byte SPHINCS+ pubkey for later use by `QRDescriptor`
5. Returns a `PubkeyProvider` wrapping the `CExtPubKey`
6. Handles derivation path suffixes (`/0/*`, `/1/*`, `/0/7`, etc.)

The SPHINCS+ pubkey needs to flow from the parser to the descriptor. Options:
- Store on a custom `QRPubkeyProvider` subclass
- Pass as a separate parameter to `QRDescriptor` constructor

Simplest: `ParseQPubKey()` returns both the `PubkeyProvider` and the SPHINCS+
pubkey bytes. The caller passes both to `QRDescriptor`.

### 3. Add `QRDescriptor::ToString()` / `ToStringExtra()`

Serializes back to `qr(Q1.../0/*)` format. The qpub is reconstructed from
the stored `CExtPubKey` + SPHINCS+ pubkey.

Need `EncodeQExtPubKey()` accessible from descriptor code. It's currently in
`wallet/qextkey.cpp` — may need to move the encode/decode to a common location
or keep a forward reference.

**Option**: Move `EncodeQExtPubKey`/`DecodeQExtPubKey` to `key_io.cpp` (common
layer) since they're just base58 operations. Or keep them in wallet and add
the necessary includes.

Actually, the descriptor system is in `src/script/` which is the common layer.
The wallet code is in `src/wallet/`. For the parser to call `DecodeQExtPubKey`,
it needs access. Since `qextkey.h` only depends on `key.h` and `pubkey.h`
(common layer), it can be included from `descriptor.cpp` without creating a
circular dependency.

### 4. Update `createsphincskey` RPC

**File**: `repos/bitcoin/src/wallet/rpc/sphincs.cpp`

Replace the descriptor string construction:

```cpp
// OLD:
std::string qi_desc_str = "tr(" + xpub_str + "/0/*,qis(" + sphincs_hex + "," + xpub_str + "/0/*))";

// NEW:
std::string qpub_str = EncodeQExtPubKey(account_qpub);
std::string qi_ext_desc = "qr(" + qpub_str + "/0/*)";
std::string qi_int_desc = "qr(" + qpub_str + "/1/*)";
```

Same for the internal (change) descriptor.

### 5. Update `importqpub` RPC

**File**: `repos/bitcoin/src/wallet/rpc/sphincs.cpp`

Replace:
```cpp
// OLD:
std::string qi_desc_str = "tr(" + xpub_str + "/0/*,qis(" + sphincs_hex + "," + xpub_str + "/0/*))";

// NEW:
std::string qi_desc_str = "qr(" + qpub_str + "/0/*)";
```

### 6. Update `importqprv` RPC

Same pattern — build `qr(qprv_str/0/*)` descriptor.

### 7. Update `exportqpub` RPC

The RPC already returns the qpub base58 string. No change needed to the
export itself, but update the `descriptor` field in the response to show the
`qr()` format:

```json
{
  "qpub": "Q1CFYH...",
  "descriptor": "qr(Q1CFYH.../0/*)",
  "sphincs_pubkey": "abcd..."
}
```

### 8. Update `getquantumaddress` RPC

Already uses `GetNewDestination(BECH32M)` which will use the active `qr()`
descriptor. No change needed.

### 9. Update `QExtPubKey::DeriveAddress()`

**File**: `repos/bitcoin/src/wallet/qextkey.cpp`

Currently builds the hybrid script manually. Should be consistent with
`QRDescriptor::MakeScripts()`. Either:
- Have `DeriveAddress()` call the same construction logic
- Or keep it as-is (it already produces the same output)

No change needed if the construction is equivalent.

### 10. Update unit tests

**File**: `repos/bitcoin/src/wallet/test/qis_descriptor_tests.cpp`

Rename to `qi_descriptor_tests.cpp` or add `qr()` tests alongside existing
`qis()` tests:

- Parse `qr(qpub/0/*)` → valid Taproot output
- Parse `qr(qprv/0/*)` → same output as qpub version
- Child derivation: index 0, 1, 2 → different addresses
- SPHINCS+ key constant across all indices
- `qr()` output matches `tr(xpub, qis(HEX, xpub))` for same keys
- Checksum roundtrip: `ToString()` → `Parse()`
- `qr()` only at TOP context
- Invalid qpub → error
- `qr(qpub/0/*, {pk(KEY)})` → hybrid leaf + pk leaf in tree

### 11. Update functional tests

**File**: `repos/bitcoin/test/functional/wallet_sphincs.py`

Update `createsphincskey` tests to verify the returned descriptor uses
`qr()` format. Update any assertions that check for `qis()` or `tr()` in
descriptor strings.

### 12. Update BIP 395 spec

**File**: `repos/bips/bip-0395.mediawiki`

Add new section:

```
==qr() Output Descriptor==

The qr() output descriptor defines a quantum-insured Taproot output using
a qpub extended key:

  qr(KEY)
  qr(KEY, SCRIPT_TREE)

Where KEY is a qpub or qprv with optional derivation path. The descriptor
automatically constructs a hybrid SPHINCS+ tapleaf using the derived EC
child key and the SPHINCS+ pubkey from the qpub.

Expansion at child index i:
  internal_key = BIP32_Derive(qpub.xpub, i)
  hybrid_script = <qpub.sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP
                  <internal_key> OP_CHECKSIG
  merkle_root = TapLeaf(0xC0, hybrid_script)
  Q = internal_key + hash(TapTweak, internal_key || merkle_root) * G

The output is a standard Taproot (witness v1) scriptPubKey.

Example:
  qr(Q1CFYH2UTfN9JFK.../0/*)

For advanced use cases requiring custom Taproot tree construction, the
qis() script fragment remains available:
  tr(xpub/0/*, qis(SPHINCS_HEX, xpub/0/*))
```

### 13. Update website

**File**: `services/website/src/pages/wallet.astro`

Update the descriptor syntax section to show `qr()` as the primary format.
Move `qis()` to an "Advanced" subsection.

**File**: `services/website/src/components/QuickStart.astro`

No change needed — the RPCs don't change.

### 14. Update documentation

**File**: `repos/bitcoin/doc/quantum-insured-wallet.md`

Update the descriptor syntax section:
```
## Descriptor Syntax

Standard:  qr(qpub/0/*)
Advanced:  tr(xpub/0/*, qis(SPHINCS_HEX, xpub/0/*))
```

---

## Files Summary

| File | Action | Description |
|------|--------|-------------|
| `src/script/descriptor.cpp` | MODIFY | Add QRDescriptor class, ParseQPubKey(), parser entry |
| `src/wallet/rpc/sphincs.cpp` | MODIFY | Use qr() in createsphincskey, importqpub, importqprv |
| `src/wallet/test/qis_descriptor_tests.cpp` | MODIFY | Add qr() test cases |
| `test/functional/wallet_sphincs.py` | MODIFY | Update descriptor string assertions |
| `repos/bips/bip-0395.mediawiki` | MODIFY | Add qr() descriptor section |
| `repos/bitcoin/doc/quantum-insured-wallet.md` | MODIFY | Update descriptor syntax |
| `services/website/src/pages/wallet.astro` | MODIFY | qr() as primary, qis() as advanced |

---

## Dependency

`QRDescriptor` needs `DecodeQExtPubKey()` from `wallet/qextkey.h`. Since
`descriptor.cpp` is in the common `script/` layer, this creates a dependency
from common → wallet. Two options:

**Option A**: Move `QExtPubKey` struct and `DecodeQExtPubKey`/`EncodeQExtPubKey`
to the common layer (`src/pubkey.h` or new `src/qextkey.h`). Clean separation
but moves wallet-specific code to common.

**Option B**: Keep `QExtPubKey` in wallet, have the descriptor parser accept
the raw components (xpub bytes + sphincs pubkey bytes) rather than calling
`DecodeQExtPubKey` directly. The RPC layer does the decoding and passes
parsed components to the descriptor.

**Recommended: Option A.** The `QExtPubKey` struct is just a data container
with `Encode`/`Decode` — no wallet dependencies. Move it to the common layer.
The base58 encode/decode stays with it since it only needs `chainparams.h`
which is already common.

---

## Verification

```bash
cmake --build build -j$(nproc)

# Unit tests
build/bin/test_bitcoin --run_test=qis_descriptor_tests,qextkey_tests,script_tests

# Functional tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini

# Website
cd services/website && npx astro build
```
