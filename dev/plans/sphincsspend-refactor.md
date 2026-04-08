# Refactor: Fix SPHINCS+ Key Storage in createsphincskey

- Status: proposed
- Date: 2026-04-08
- Owner: cmdruid

## Problem

`createsphincskey` stores the SPHINCS+ key on the **wrong SPKM**. It stores
on the default `tr()` BECH32M descriptor manager (line 138), then creates new
`qr()` descriptor managers without the SPHINCS+ key. This causes:

1. `sphincsspend` can't find QI UTXOs — `GetScriptPubKeyMans(script)` maps
   QI scriptPubKeys to the `qr()` SPKM, but that SPKM lacks the SPHINCS+ key
2. `sphincsspend` can't sign via script-path — the `qr()` SPKM's
   `GetSphincsSigningKey()` returns nullopt

## Reference Implementation

`importqprv` (lines 463-565) does it correctly:
1. Creates a `qr()` SPKM via `AddWalletDescriptor`
2. Stores the SPHINCS+ key **on that new SPKM** via `WriteSphincsKey`/`LoadSphincsKey`
3. The DB key uses `spk_man.GetID()` so it's scoped to the `qr()` descriptor

## Fix

Refactor `createsphincskey` to follow the `importqprv` pattern:

### Step 1: Derive SPHINCS+ key first, before creating SPKMs

Move the key derivation (lines 137-146) to happen before the QI descriptor
creation (lines 147-202). Currently:

```
1. Find master key on tr() SPKM
2. SetupSphincsKey on tr() SPKM          ← WRONG
3. Create qr() external SPKM (no key)    ← WRONG
4. Create qr() internal SPKM (no key)    ← WRONG
```

Change to:

```
1. Find master key on tr() SPKM
2. Derive SPHINCS+ key (SphincsKey::DeriveFromMaster)
3. Create qr() external SPKM
4. Store SPHINCS+ key on external qr() SPKM
5. Create qr() internal SPKM
6. Store SPHINCS+ key on internal qr() SPKM
7. Do NOT store on old tr() SPKM
```

### Step 2: Store key on QI SPKMs using importqprv pattern

After each `AddWalletDescriptor` call, store the key like `importqprv` does:

```cpp
auto& qi_spk_man = add_result->get();
WalletBatch qi_batch(pwallet->GetDatabase());

std::array<unsigned char, 32> pk_arr;
std::copy(sphincs_key.PubkeyData(), sphincs_key.PubkeyData() + 32, pk_arr.begin());

if (pwallet->IsCrypted()) {
    // Encrypt: compute IV from pubkey hash, encrypt secret, write crypted
    auto iv = Hash(pk_arr);
    std::vector<unsigned char> plaintext(sphincs_key.SecretData(),
                                         sphincs_key.SecretData() + 64);
    std::vector<unsigned char> crypted;
    pwallet->WithEncryptionKey([&](const CKeyingMaterial& key) {
        return EncryptSecret(key, plaintext, iv, crypted);
    });
    qi_batch.WriteCryptedSphincsKey(qi_spk_man.GetID(), pk_arr, crypted);
    qi_spk_man.LoadCryptedSphincsKey(
        std::span<const unsigned char>{pk_arr.data(), 32},
        std::span<const unsigned char>{crypted.data(), crypted.size()});
} else {
    std::array<unsigned char, 64> sk_arr;
    std::copy(sphincs_key.SecretData(), sphincs_key.SecretData() + 64, sk_arr.begin());
    qi_batch.WriteSphincsKey(qi_spk_man.GetID(), pk_arr, sk_arr);
    qi_spk_man.LoadSphincsKey(
        std::span<const unsigned char>{pk_arr.data(), 32},
        std::span<const unsigned char>{sk_arr.data(), 64});
}
```

### Step 3: Remove SetupSphincsKey call on old tr() SPKM

Delete line 138-141:
```cpp
// DELETE: if (!target_spk_man->SetupSphincsKey(batch, master_ext, account_path)) {
```

The old `tr()` SPKM should NOT have the SPHINCS+ key. Only `qr()` SPKMs
should have it.

### Step 4: Remove old sphincsspend stash, apply clean version

`git stash drop` the current WIP. The sphincsspend RPC from commit
`95f7809edc` is the base. Apply the QI UTXO pre-selection and two-pass
FillPSBT on top of the refactored `createsphincskey`.

## Files to modify

| File | Changes |
|------|---------|
| `src/wallet/rpc/sphincs.cpp` | Refactor createsphincskey, update sphincsspend with QI UTXO filtering |
| `src/wallet/scriptpubkeyman.h` | Add `HasSphincsKey()` override + virtual on base (already done in stash) |
| `src/wallet/wallet.cpp` | Two-pass FillPSBT (already done in stash) |
| `src/wallet/wallet.h` | sphincs_emergency param on FillPSBT (already done in stash) |
| `src/wallet/rpc/spend.cpp` | sphincs_emergency on walletprocesspsbt (already done in stash) |
| `src/wallet/external_signer_scriptpubkeyman.h/.cpp` | FillPSBT signature update (already done in stash) |
| `test/functional/wallet_sphincs_scriptpath.py` | Full SPHINCS+ spend test |

## Verification

```bash
cmake --build build -j$(nproc)

# All existing tests must still pass (regression)
build/bin/test_bitcoin --run_test=sphincskeys_tests,qextkey_tests,qis_descriptor_tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini

# Script-path test must show 4+ witness elements with annex type 0x04
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini
```

## Key invariant after refactor

- `tr()` SPKM: NO SPHINCS+ key (default Taproot, unchanged)
- `qr()` external SPKM: HAS SPHINCS+ key (QI receiving addresses)
- `qr()` internal SPKM: HAS SPHINCS+ key (QI change addresses)
- `listsphincskeys`: finds keys on `qr()` SPKMs (2 per account)
- `exportqpub`/`exportqprv`: finds key on first `qr()` SPKM with key
- `sphincsspend`: filters UTXOs by QI SPKMs, signs via script-path
- `GetScriptPubKeyMans(qi_script)` → returns `qr()` SPKM → `HasSphincsKey()=true`
