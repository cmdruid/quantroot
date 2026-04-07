# Quantroot Manual Testing Guide

This guide walks through manually testing the quantum-insured wallet on regtest.
Both BIP 368 and BIP 369 are always active on regtest (buried at height 1).

## Prerequisites

```bash
cd repos/bitcoin
cmake -B build -DENABLE_IPC=OFF
cmake --build build -j$(nproc)
```

## 1. Start a Regtest Node

```bash
# Start in background
build/bin/bitcoind -regtest -daemon -txindex -fallbackfee=0.0001

# Verify it's running
build/bin/bitcoin-cli -regtest getblockchaininfo | head -5
```

## 2. Create a Quantum-Insured Wallet

```bash
# Create a descriptor wallet
build/bin/bitcoin-cli -regtest createwallet "quantum"

# Create the SPHINCS+ key and register QI descriptors
build/bin/bitcoin-cli -regtest -rpcwallet=quantum createsphincskey
```

You should see output like:
```json
{
  "sphincs_pubkey": "abcd...1234",
  "qi_descriptor": "tr(tpub.../0/*,qis(abcd...1234,tpub.../0/*))"
}
```

The wallet now has:
- A SPHINCS+ keypair derived from the master key at `m/395'/1'/0'`
- A QI descriptor registered as active for bech32m addresses
- Both external (`/0/*`) and internal (`/1/*`) QI descriptors for change

## 3. Generate Addresses and Fund the Wallet

```bash
# Mine coins to a standard address (for funding)
FUND=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum getnewaddress "" bech32)
build/bin/bitcoin-cli -regtest generatetoaddress 101 $FUND

# Check balance
build/bin/bitcoin-cli -regtest -rpcwallet=quantum getbalance
# Should show 50.00000000

# Generate a quantum-insured address
build/bin/bitcoin-cli -regtest -rpcwallet=quantum getquantumaddress
```

The QI address is a standard bech32m Taproot address (`bcrt1p...`). It's
indistinguishable from any other Taproot address on-chain.

## 4. Fund a QI Address

```bash
# Get a QI address
QI_ADDR=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum getquantumaddress | jq -r .address)
echo "QI address: $QI_ADDR"

# Send 10 BTC to it
build/bin/bitcoin-cli -regtest -rpcwallet=quantum sendtoaddress $QI_ADDR 10

# Mine a block to confirm
build/bin/bitcoin-cli -regtest generatetoaddress 1 $FUND

# Verify the UTXO is tracked
build/bin/bitcoin-cli -regtest -rpcwallet=quantum listunspent 1 9999 "[\"$QI_ADDR\"]"
```

You should see the 10 BTC UTXO at the QI address.

## 5. Spend from a QI Address

```bash
# Spend 5 BTC from the QI address to a standard address
DEST=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum getnewaddress "" bech32)
TXID=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum sendtoaddress $DEST 5)
echo "Spend txid: $TXID"

# Mine to confirm
build/bin/bitcoin-cli -regtest generatetoaddress 1 $FUND

# Verify confirmed
build/bin/bitcoin-cli -regtest -rpcwallet=quantum gettransaction $TXID | jq .confirmations
```

## 6. Inspect the Witness (BIP 368 Annex)

```bash
# Get the raw transaction
TX_HEX=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum gettransaction $TXID | jq -r .hex)
build/bin/bitcoin-cli -regtest decoderawtransaction $TX_HEX | jq '.vin[0].txinwitness'
```

You should see a witness with 2 elements:
```json
[
  "3045...ac",     // 64-byte Schnorr signature
  "5002...abcd"    // 66-byte BIP 368 annex (0x50 = annex tag, 0x02 = key-path type)
]
```

The annex contains:
- `0x50` — annex tag (BIP 341)
- `0x02` — key-path type (BIP 368)
- 32 bytes — internal key P
- 32 bytes — merkle root (of the hybrid tapleaf)

## 7. Export and Import qpub (Watch-Only)

```bash
# Export the quantum-insured extended public key
QPUB=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum exportqpub | jq -r .qpub)
echo "qpub: ${QPUB:0:20}..."
# Should start with Q1...

# Create a watch-only wallet
build/bin/bitcoin-cli -regtest createwallet "watchonly" true true

# Import the qpub
build/bin/bitcoin-cli -regtest -rpcwallet=watchonly importqpub "$QPUB"

# Generate addresses from the watch-only wallet
build/bin/bitcoin-cli -regtest -rpcwallet=watchonly getnewaddress "" bech32m
# Should produce a valid bcrt1p... address
```

## 8. Export and Import qprv (Full Backup)

```bash
# Export the private key (wallet must be unlocked)
QPRV=$(build/bin/bitcoin-cli -regtest -rpcwallet=quantum exportqprv)
echo "qprv: ${QPRV:0:20}..."
# Should start with Q1...

# Create a new wallet and import
build/bin/bitcoin-cli -regtest createwallet "restored"
build/bin/bitcoin-cli -regtest -rpcwallet=restored importqprv "$QPRV"

# Verify the SPHINCS+ key matches
build/bin/bitcoin-cli -regtest -rpcwallet=restored listsphincskeys
# Should show the same sphincs_pubkey as the original wallet
```

## 9. Encrypted Wallet

```bash
# Create an encrypted wallet
build/bin/bitcoin-cli -regtest createwallet "encrypted" false false "mypassword"

# Unlock and create SPHINCS+ key
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted walletpassphrase "mypassword" 300
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted createsphincskey

# Lock the wallet
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted walletlock

# These work while locked (public key operations only):
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted listsphincskeys
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted getquantumaddress

# This fails while locked (needs private key):
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted exportqprv
# Error: Please enter the wallet passphrase with walletpassphrase first.

# Unlock to spend or export private key
build/bin/bitcoin-cli -regtest -rpcwallet=encrypted walletpassphrase "mypassword" 60
```

## 10. Test Activation Boundary (Optional)

To test pre/post activation behavior, start the node with delayed activation:

```bash
# Stop the running node first
build/bin/bitcoin-cli -regtest stop

# Start with activation at height 200
build/bin/bitcoind -regtest -daemon -txindex -fallbackfee=0.0001 \
  -testactivationheight=sphincs@200 \
  -testactivationheight=keypath_hardening@200

# Create wallet and fund it (height < 200 = pre-activation)
# Key-path spends work WITHOUT annex
# OP_CHECKSPHINCSVERIFY is treated as OP_NOP4

# Mine past height 200
# Now key-path spends REQUIRE the BIP 368 annex
# OP_CHECKSPHINCSVERIFY enforces SPHINCS+ verification
```

## 11. Clean Up

```bash
build/bin/bitcoin-cli -regtest stop
rm -rf ~/.bitcoin/regtest
```

## Automated Test Suites

For comprehensive automated testing:

```bash
# Unit tests (75 tests, ~30 seconds)
build/bin/test_bitcoin --run_test=sphincskeys_tests,sphincskeys_db_tests,qextkey_tests,qis_descriptor_tests

# Wallet functional tests (37 tests, ~2 minutes)
python3 test/functional/wallet_sphincs.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_psbt.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_activation.py --configfile=build/test/config.ini
python3 test/functional/wallet_sphincs_scriptpath.py --configfile=build/test/config.ini

# Consensus functional tests (56 tests, ~1 minute)
python3 test/functional/feature_sphincs.py --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --configfile=build/test/config.ini

# Activation boundary tests
python3 test/functional/feature_sphincs.py --activation --configfile=build/test/config.ini
python3 test/functional/feature_keypath_hardening.py --activation --configfile=build/test/config.ini

# Core regression
build/bin/test_bitcoin --run_test=script_tests,transaction_tests

# Benchmarks (requires -DBUILD_BENCH=ON)
build/bin/bench_bitcoin -filter="Sphincs"
```

## What to Verify

| Step | Expected Result |
|------|----------------|
| `createsphincskey` | Returns 64-char hex `sphincs_pubkey` + `qi_descriptor` |
| `getquantumaddress` | Returns `bcrt1p...` bech32m address |
| `listsphincskeys` | Shows the key with `has_private_key: true` |
| Fund QI address | `listunspent` shows the UTXO at the QI address |
| Spend from QI | Transaction confirms, witness has 2 elements (sig + annex) |
| Annex format | Starts with `5002` (0x50 tag + 0x02 key-path type), 66 bytes total |
| `exportqpub` | Returns `Q1...` base58 string |
| `importqpub` | Watch-only wallet can derive same-format addresses |
| `exportqprv` | Returns `Q1...` base58 string (longer than qpub) |
| `importqprv` | Restored wallet has same `sphincs_pubkey` |
| Encrypted wallet | `listsphincskeys` works locked; `exportqprv` requires unlock |

## Troubleshooting

**"Method not found"** — The wallet RPCs are only available when a descriptor
wallet is loaded. Make sure you used `createwallet` with `descriptors=true`
(the default).

**"No master key found"** — The wallet doesn't have private keys. Make sure
the wallet is not watch-only and is unlocked if encrypted.

**"Key-path spend requires annex"** — This is expected on regtest where BIP 368
is always active. The wallet includes the annex automatically.

**Annex rejected as non-standard** — This should not happen with the current
code. BIP 368/369 annexes (type 0x02 and 0x04) are standard in relay policy.
If you see this error, check that you're running the quantroot build.
