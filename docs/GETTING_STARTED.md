# Getting Started

Get Quantroot running in under 10 minutes.

## Prerequisites

- Docker Engine 24+ with Docker Compose v2
- Git 2.30+
- 8 GB RAM, 20 GB disk

## 1. Clone

```bash
git clone --recurse-submodules https://github.com/cmdruid/quantroot.git
cd quantroot
cp .env.example .env
```

## 2. Build

Build the Quantroot Bitcoin Core fork (includes bitcoin-qt):

```bash
make build-bitcoin
```

This uses Docker to compile from source. Takes ~10 minutes the first time,
seconds on subsequent runs (cached layers).

Output: `build/bitcoin/bin/bitcoind`, `bitcoin-cli`, `bitcoin-qt`, `bitcoin-tx`, `bitcoin-util`

## 3. Start the Regtest Node

```bash
make start BG=1
make health
```

You should see `quantroot-bitcoin   Up ... (healthy)`.

The container runs a regtest node with BIP 368 and BIP 369 active from
block 1. Data is stored in `data/demo-node/`.

## 4. Run the Demo Test

```bash
make test-demo
```

This runs 22 automated checks across 6 phases:

1. **Infrastructure** — binaries exist, container healthy
2. **Wallet Operations** — create SPHINCS+ key, generate QI address, export qpub
3. **Key-Path Spend** — fund, spend, confirm (normal Taproot with BIP 368 annex)
4. **SPHINCS+ Emergency** — sphincsspend via hybrid tapleaf, confirm on-chain
5. **PSBT Key-Path** — create PSBT, sign, finalize, broadcast
6. **PSBT SPHINCS+ Emergency** — PSBT with sphincs_emergency=true, confirm

All 22 checks should pass.

## 5. Open bitcoin-qt (Optional)

Launch the GUI as a separate regtest node that peers with the container:

```bash
make qt-regtest
```

Open the console (Window → Console) and try:

```
createwallet "quantum"
createsphincskey
getquantumaddress
```

Data is stored in `data/demo-qt/`, separate from the container node.

## 6. Test on Signet (Optional)

Launch bitcoin-qt on signet to test forward compatibility with real peers:

```bash
make qt-signet
```

On signet, you can create quantum-insured wallets and addresses that are
valid under current consensus. The hybrid tapleaf is dormant (`OP_NOP4`)
until the soft fork activates.

## What Just Happened?

You built a modified Bitcoin Core that implements four companion BIPs:

- **BIP 368**: Hardens key-path spending (internal key disclosure via annex)
- **BIP 369**: Adds `OP_CHECKSPHINCSVERIFY` for SPHINCS+ post-quantum signatures
- **BIP 395**: Defines quantum-insured extended keys (qpub/qprv) and `qr()` descriptor
- **BIP 377**: Extends PSBT with fields for SPHINCS+ key material and signatures

The quantum-insured outputs you created look like ordinary Taproot on-chain.
The hidden hybrid tapleaf becomes enforceable when the soft fork activates,
providing post-quantum protection without any migration.

## Clean Up

```bash
make stop          # Stop the container
make reset-demo    # Delete all demo data
```

## Next Steps

- [test/DEMO.md](../test/DEMO.md) — interactive step-by-step demo
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit together
- [docs/OVERVIEW.md](OVERVIEW.md) — domain knowledge and threat model
- [CONTRIBUTING.md](../CONTRIBUTING.md) — how to contribute
- [www.quantroot.org](https://www.quantroot.org) — project website
