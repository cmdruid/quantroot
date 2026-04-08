# Audit Remediation Plan

## Context

Pre-release audit identified 4 critical, 10 high, 10 medium, and 10+ low
issues across Bitcoin Core code and BIP specifications. All issues will be
fixed in one sweep before mailing list submission.

---

## Phase 1: Critical Fixes (repos/bitcoin)

### C1. Buffer overflow in qextkey.cpp — use std::array references

**Files:** `src/qextkey.h`, `src/qextkey.cpp`

Change all Encode/Decode signatures from raw `unsigned char[]` to
`std::array<unsigned char, N>&`:

```cpp
// Before:
void Encode(unsigned char code[QI_EXTKEY_SIZE]) const;
void Decode(const unsigned char code[QI_EXTKEY_SIZE]);
// After:
void Encode(std::array<unsigned char, QI_EXTKEY_SIZE>& code) const;
void Decode(const std::array<unsigned char, QI_EXTKEY_SIZE>& code);
```

Update all callers (EncodeQExtPubKey, DecodeQExtPubKey, EncodeQExtKey,
DecodeQExtKey, child derivation, tests).

### C2. HMAC key length — add static_assert

**File:** `src/wallet/sphincskeys.cpp`

```cpp
static constexpr const char SPHINCS_HMAC_KEY[] = "Sphincs seed";
static constexpr size_t SPHINCS_HMAC_KEY_LEN = 12;
static_assert(sizeof(SPHINCS_HMAC_KEY) - 1 == SPHINCS_HMAC_KEY_LEN);

CHMAC_SHA512{reinterpret_cast<const unsigned char*>(SPHINCS_HMAC_KEY), SPHINCS_HMAC_KEY_LEN}
```

### C3. SphincsKey copy assignment — fix initialization order

**File:** `src/wallet/sphincskeys.h`

```cpp
SphincsKey& operator=(const SphincsKey& other) {
    if (this != &other) {
        m_valid = false;  // Invalidate first
        if (other.m_keydata) {
            MakeKeyData();
            *m_keydata = *other.m_keydata;
            m_pubkey = other.m_pubkey;
            m_valid = other.m_valid;  // Restore after data is copied
        } else {
            ClearKeyData();
        }
    }
    return *this;
}
```

---

## Phase 2: High Fixes (repos/bitcoin)

### H1. Clean up hybrid script fallback

**File:** `src/script/sign.cpp`

- Remove empty `else {}` block
- Add `if (!schnorr_xonly.IsFullyValid()) continue;` validation
- Verify no extra opcodes after OP_CHECKSIG (`it == cscript.end()`)
- Add comment documenting this only handles simple hybrid scripts
- Extract to `SignHybridSphincsScript()` helper function

### H2. Add sign/verify round-trip to SphincsKey::Load()

**File:** `src/wallet/sphincskeys.cpp`

After loading the key and verifying pubkey bytes, add:
```cpp
// Cryptographic verification: sign and verify a test message
uint256 test_msg = uint256S("0000...0001");  // fixed test message
std::vector<unsigned char> test_sig(SIGNATURE_SIZE);
size_t sig_len = SphincsSign(test_sig.data(), test_msg.data(), 32, m_keydata->data());
if (sig_len != SIGNATURE_SIZE ||
    !SphincsVerify(test_sig.data(), sig_len, test_msg.data(), 32, m_pubkey.data())) {
    ClearKeyData();
    return false;
}
```

### H3. Validate DB checksum on load

**File:** `src/wallet/walletdb.cpp`

In the SPHINCSKEY load handler, verify the keypair hash:
```cpp
auto [secret, stored_hash] = value;
auto computed_hash = Hash(pubkey_vec, secret_vec);
if (stored_hash != computed_hash) {
    LogError("SPHINCS+ key integrity check failed for descriptor %s", desc_id.ToString());
    return DBErrors::CORRUPT;
}
```

### H4. Integer overflow in sphincsspend coin selection

**File:** `src/wallet/rpc/sphincs.cpp`

```cpp
if (qi_total > MAX_MONEY - out.nValue) {
    throw JSONRPCError(RPC_WALLET_ERROR, "QI UTXO sum exceeds maximum money");
}
qi_total += out.nValue;
```

### H5. Encryption IV — use Hash(desc_id, pubkey)

**File:** `src/wallet/rpc/sphincs.cpp` (createsphincskey, 2 blocks)

Replace:
```cpp
uint256 iv = (HashWriter{} << MakeByteSpan(sphincs_pk)).GetHash();
```
With:
```cpp
uint256 iv = (HashWriter{} << qi_spk_man.GetID() << MakeByteSpan(sphincs_pk)).GetHash();
```

Also update `importqprv` to use same pattern. Update `GetSphincsSigningKey()`
decryption to include descriptor ID in IV computation.

**Important:** This changes the IV for existing encrypted wallets. Add
migration note or version check.

### H6. SphincsKey::Load — add cryptographic verification

Same as H2 above (merged into one task).

---

## Phase 3: Medium Fixes (repos/bitcoin)

### M1. Cache SPKM list in two-pass FillPSBT

**File:** `src/wallet/wallet.cpp`

```cpp
const auto all_spkms = GetAllScriptPubKeyMans();
if (sphincs_emergency) {
    for (ScriptPubKeyMan* spk_man : all_spkms) { ... }
    for (ScriptPubKeyMan* spk_man : all_spkms) { ... }
} else {
    for (ScriptPubKeyMan* spk_man : all_spkms) { ... }
}
```

### M2-M3. PSBT comments and validation

**File:** `src/psbt.cpp`

- Add comments explaining PSBTInputSignedAndVerified heuristic
- Add comment explaining annex validation happens at script execution time
- Add comment explaining SPHINCS+ secret validation happens during signing

### M4. getquantumaddress error handling

**File:** `src/wallet/rpc/sphincs.cpp`

Throw JSONRPCError if no SPHINCS+ key found instead of returning partial result.

### M5. Account index overflow check

**File:** `src/wallet/rpc/sphincs.cpp`

```cpp
if (account_index >= 0x80000000) {
    throw JSONRPCError(RPC_INVALID_PARAMETER, "account_index must be less than 2^31");
}
```

### M6. Extract encryption utility

**File:** `src/wallet/rpc/sphincs.cpp` (or new utility)

Extract the repeated encryption/decryption block into a helper:
```cpp
static void StoreSphincsKeyOnSPKM(CWallet& wallet, DescriptorScriptPubKeyMan& spkm,
    const SphincsKey& key, const std::array<unsigned char, 32>& pubkey);
```

---

## Phase 4: BIP Specification Fixes (repos/bips)

### C4. Fix BIP 377 PSBT field type bytes

**File:** `bip-0377.mediawiki`

Update all field type references:
- `PSBT_IN_TAP_SPHINCS_PUB`: 0x1c → 0x1d
- `PSBT_IN_TAP_SPHINCS_SIG`: 0x1d → 0x1e
- `PSBT_IN_TAP_ANNEX`: 0x1e → 0x1f
- `PSBT_OUT_TAP_SPHINCS_PUB`: 0x08 → 0x09

Update `bip-0377/test-vectors.json` to match.
Remove "provisional" language about field type assignments.

### H7. Rewrite BIP 369 SPHINCS+ sighash explanation

**File:** `bip-0369.mediawiki` (~lines 202-212)

Replace with clear domain separation explanation:
```
spend_type = 0x03: ext_flag=1 (Tapscript), annex_bit=1 (annex present)
sha_annex is NOT appended despite annex_bit=1.

Domain separation:
  - Non-annex Tapscript: spend_type=0x01, no sha_annex
  - Schnorr (with annex): spend_type=0x03, sha_annex appended
  - SPHINCS+ (with annex): spend_type=0x03, sha_annex omitted
```

### H8. Clarify BIP 395 qpub/qprv prefix disambiguation

**File:** `bip-0395.mediawiki`

Add note: "Both mainnet qpub and qprv begin with `Q1`. Deserializers
distinguish them by payload size: 110 bytes (qpub) vs 142 bytes (qprv)."

### H9. Add scope disclaimer to BIP 377

**File:** `bip-0377.mediawiki`

Add to Introduction: "This BIP specifies PSBT field types and serialization
only. It does not define RPC methods or wallet APIs."

### M8. Justify NUMS ban in BIP 368

**File:** `bip-0368.mediawiki`

Add rationale for repeating-byte NUMS: "The `0xabab...ab` pattern is a
common developer test value that may appear in production outputs due to
copy-paste from documentation or testing scripts."

### M9. Clarify unknown key type extensibility in BIP 369

**File:** `bip-0369.mediawiki`

Add: "Unknown key types are silently skipped (cursor advanced, no
verification). This is safe because script authors control which key
types are pushed — attackers cannot inject unknown key types."

### M10. Finalize validation weight budget in BIP 369

**File:** `bip-0369.mediawiki`

Run `build/bin/bench_bitcoin -filter="Sphincs"` to get verification time.
Compute: `VALIDATION_WEIGHT_PER_SPHINCS_SIGOP = ceil(sphincs_verify_us / schnorr_verify_us) * 50`
Document methodology and final value. Fix the example calculation.

---

## Verification

```bash
cd repos/bitcoin
cmake --build build -j$(nproc)

# Unit tests
build/bin/test_bitcoin --run_test=sphincskeys_tests,qextkey_tests,qis_descriptor_tests,sphincskeys_db_tests,script_tests

# All functional tests
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini

# Benchmarks (for M10)
build/bin/bench_bitcoin -filter="Sphincs"

# Website
cd services/website && npx astro build

# Final grep for stale references
grep -rn "0x1c.*SPHINCS\|0x08.*SPHINCS" repos/bips/ --include='*.mediawiki'
```
