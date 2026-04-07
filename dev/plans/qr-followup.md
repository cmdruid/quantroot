# qr() Descriptor Follow-Up Tasks

- Status: proposed
- Date: 2026-04-06
- Owner: cmdruid

## Context

The `qr()` descriptor is implemented and all 170 tests pass. Seven follow-up
tasks remain: BIP spec update, unit tests, force push, ToString roundtrip,
script tree test, PR description, and website design doc.

---

## Task 1: Update BIP 395 spec with qr() descriptor section

**File**: `repos/bips/bip-0395.mediawiki`

Add a new `==qr() Output Descriptor==` section before `==Backward Compatibility==`:

```mediawiki
==qr() Output Descriptor==

The <code>qr()</code> output descriptor defines a quantum-insured Taproot
output using a qpub extended key:

<source>
qr(KEY)
qr(KEY, SCRIPT_TREE)
</source>

Where KEY is a qpub or qprv with optional BIP 32 derivation path. The
descriptor auto-constructs a hybrid SPHINCS+ tapleaf using the derived EC
child key and the SPHINCS+ pubkey from the qpub.

Expansion at child index i:

<source>
child_xonly    = BIP32_Derive(qpub.xpub, i)
hybrid_script  = <qpub.sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP
                 <child_xonly> OP_CHECKSIG
leaf_hash      = TapLeaf(0xC0, hybrid_script)
Q = child_xonly + hash(TapTweak, child_xonly || leaf_hash) * G
</source>

Example:

<source>
qr(Q1CFYH2UTfN9JFK.../0/*)
</source>

For advanced use cases requiring custom Taproot trees, the <code>qis()</code>
script fragment remains available:

<source>
tr(xpub/0/*, qis(SPHINCS_HEX, xpub/0/*))
</source>
```

---

## Task 2: Add qr() unit tests

**File**: `repos/bitcoin/src/wallet/test/qis_descriptor_tests.cpp`

Add test cases:

- `qr_parse_qpub`: Parse `qr(Q1.../0/*)` — produces valid Taproot output
- `qr_parse_qpub_no_path`: Parse `qr(Q1...)` (no derivation) — should work
  for non-ranged descriptor
- `qr_expansion_matches_qis`: Expand `qr(qpub/0/*)` at index 0, compare
  output with `tr(xpub/0/*, qis(HEX, xpub/0/*))` at same index — must match
- `qr_child_derivation`: Expand at index 0, 1, 2 — different addresses, same
  SPHINCS+ key in hybrid script
- `qr_top_context_only`: `qr()` inside `wsh()` or `sh()` → parse error
- `qr_invalid_qpub`: `qr(invalidbase58/0/*)` → parse error

Build the qpub test key using `MakeTestQExtKey()` from existing `qextkey_tests.cpp`,
then encode to base58 via `EncodeQExtPubKey()`.

---

## Task 3: Force push updated branch

```bash
cd repos/bitcoin
git push --force origin quantroot
```

---

## Task 4: QRDescriptor ToString() roundtrip

**File**: `repos/bitcoin/src/script/descriptor.cpp`

Currently `QRDescriptor::ToStringExtra()` returns the SPHINCS+ hex, which
produces `qr(xpub/0/*,abcd...1234)` — not parseable as `qr()`.

The `ToString()` method needs to produce `qr(Q1.../0/*)` format. This requires
reconstructing the qpub from the stored EC xpub + SPHINCS+ pubkey.

**Problem**: The descriptor stores the EC key as a `PubkeyProvider` (which
serializes as xpub with derivation path) and the SPHINCS+ pubkey as raw bytes.
To produce `qr(Q1...)`, we need to combine them into a qpub base58 string.

**Approach**: Override `ToStringHelper()` instead of just `ToStringExtra()`.
In the override:
1. Get the xpub string from the PubkeyProvider (via the base `ToString`)
2. Decode it to `CExtPubKey`
3. Combine with `m_sphincs_pubkey` into a `QExtPubKey`
4. Encode as base58 qpub
5. Append the derivation path suffix

This is complex because the PubkeyProvider may include derivation info
(origin, path) that needs to be preserved. For v1, we can use `ToStringExtra`
to emit the SPHINCS+ hex and have the qr() name imply the format. The
full roundtrip can be a follow-up.

**Simpler approach**: Store the qpub base58 string as a member of
QRDescriptor during parsing, and use it in ToString:

```cpp
class QRDescriptor {
    std::string m_qpub_str;  // stored during parsing for ToString
    // ...
    std::string ToStringExtra() const override {
        return m_qpub_str;  // produces qr(Q1.../0/*)
    }
};
```

But this breaks Clone() and requires storing the full string. Better to
reconstruct from parts.

**Recommended**: For now, skip full roundtrip. The descriptor works for
wallet operations (parse → expand → sign). ToString roundtrip is a polish
item. Add a note in the tests that ToString doesn't produce parseable qr()
format yet.

---

## Task 5: qr() with script tree test

**File**: `repos/bitcoin/src/wallet/test/qis_descriptor_tests.cpp`

Add test:
```cpp
BOOST_AUTO_TEST_CASE(qr_with_user_script_tree)
{
    // qr(qpub/0/*, pk(KEY)) — hybrid leaf + user pk leaf
    // Verify both leaves are in the Taproot tree
}
```

This depends on the parser correctly handling the comma + script tree after
the qpub key expression.

---

## Task 6: Update PR description

**File**: `dev/plans/pr-description.md`

Add `qr()` descriptor to the summary:
- New `qr()` top-level descriptor (drop-in for `tr()` with qpub)
- `QExtPubKey`/`QExtKey` moved to common layer
- `qis()` retained for advanced use

Update file counts (now 10 commits, ~74 files).

---

## Task 7: Update website DESIGN.md

**File**: `services/website/DESIGN.md`

Update the wallet guide section description to reference `qr()` as primary
descriptor syntax instead of `qis()`.

---

## Execution Order

```
Task 1 (BIP spec) — independent
Task 2 (unit tests) — independent
Task 3 (force push) — after 1+2
Task 4 (ToString) — deferred (polish)
Task 5 (script tree test) — after 2
Task 6 (PR description) — independent
Task 7 (website DESIGN.md) — independent
```

Tasks 1, 2, 6, 7 can proceed in parallel. Task 3 after 1+2. Task 4 deferred.

---

## Verification

```bash
cmake --build build -j$(nproc)
build/bin/test_bitcoin --run_test=qis_descriptor_tests,qextkey_tests,sphincskeys_tests,script_tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
cd services/website && npx astro build
```
