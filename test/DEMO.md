# Quantroot Interactive Demo

A step-by-step guide to demoing the post-quantum soft fork on regtest.
Both BIP 368 and BIP 369 are active from block 1 on regtest.

---

## Prerequisites

Build the Quantroot Bitcoin Core binaries:

```bash
make build-bitcoin
```

This produces all binaries in `build/bitcoin/bin/` including `bitcoin-qt`.

---

## Option A: Docker + CLI Demo

### 1. Start the Regtest Node

```bash
make start BG=1
make health
# Should show: quantroot-bitcoin   Up ... (healthy)
```

### 2. Open a Shell in the Container

```bash
make shell-bitcoin
```

From inside the container, all commands use:
```bash
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot <command>
```

### 3. Create a Quantum-Insured Wallet

```bash
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  createwallet "quantum"

bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum createsphincskey
```

Output shows the SPHINCS+ public key and the `qr()` descriptor.

### 4. Generate Addresses and Fund

```bash
# Mine 101 blocks for coinbase maturity
ADDR=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum getnewaddress "" bech32m)
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  generatetoaddress 101 "$ADDR"

# Get a quantum-insured address
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum getquantumaddress

# Fund it
QI=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum getquantumaddress | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum sendtoaddress "$QI" 10

bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  generatetoaddress 1 "$ADDR"
```

### 5. Key-Path Spend (Normal Operation)

```bash
DEST=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum getnewaddress "" bech32m)
TXID=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum sendtoaddress "$DEST" 5)

bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  generatetoaddress 1 "$ADDR"

# Inspect the witness — should show BIP 368 annex (type 0x02)
HEX=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum gettransaction "$TXID" | grep -o '"hex":"[^"]*"' | cut -d'"' -f4)
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  decoderawtransaction "$HEX"
```

The witness has 2 elements: a 64-byte Schnorr signature and a 66-byte
BIP 368 annex (`0x50 0x02` + internal key + merkle root).

### 6. SPHINCS+ Emergency Spend

```bash
DEST2=$(bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum getnewaddress "" bech32m)
bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  -rpcwallet=quantum sphincsspend "$DEST2" 2

bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot \
  generatetoaddress 1 "$ADDR"
```

The witness has 4 elements: Schnorr signature, hybrid script, control
block, and a 4,083-byte BIP 369 annex (`0x50 0x04` + SPHINCS+ signature).

### 7. Clean Up

```bash
exit  # Leave the container shell
make stop
```

---

## Option B: bitcoin-qt GUI Demo

### 1. Start the Container Node

```bash
make start BG=1
```

### 2. Launch bitcoin-qt (Regtest)

```bash
make qt-regtest
```

This launches `bitcoin-qt` as its own regtest node, peering with the
Docker container via P2P (port 19444).

### 3. Use the GUI

- Create a wallet via File → Create Wallet
- Open the console (Window → Console)
- Run the same commands as the CLI demo above
- Watch transactions propagate between the two peers

### 4. Test on Public Networks

For forward-compatibility testing on real networks:

```bash
# Mainnet — creates valid quantum-insured outputs today
make qt-mainnet

# Testnet
make qt-testnet

# Signet
make qt-signet
```

On public networks:
- `createsphincskey` works (creates the key)
- `getquantumaddress` works (generates valid bech32m addresses)
- `sendtoaddress` to QI addresses works (key-path spend, standard Taproot)
- `sphincsspend` will NOT work (BIP 369 is not activated on public networks)
- The hybrid tapleaf is embedded but dormant — `OP_CHECKSPHINCSVERIFY`
  is `OP_NOP4` until the soft fork activates

---

## What to Look For

### Key-Path Witness (Normal Spend)

```
Witness: [schnorr_sig (64 bytes), annex (66 bytes)]
Annex:   0x50 || 0x02 || internal_key (32 bytes) || merkle_root (32 bytes)
```

- BIP 368 requires internal key disclosure post-activation
- The hybrid tapleaf hash is committed via the merkle root
- Normal Taproot efficiency (~130 bytes total)

### Script-Path Witness (Emergency Spend)

```
Witness: [schnorr_sig (64 bytes), script (69 bytes), control_block (33 bytes), annex (4083 bytes)]
Annex:   0x50 || 0x04 || compact_size(1) || sphincs_sig (4080 bytes)
Script:  <sphincs_pk> OP_CHECKSPHINCSVERIFY OP_DROP <schnorr_pk> OP_CHECKSIG
```

- Both SPHINCS+ and Schnorr signatures verified
- An attacker must break both to spend
- Only used when quantum threat materializes
