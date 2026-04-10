# Demo Environment

- Status: proposed
- Date: 2026-04-08
- Owner: cmdruid

## Goal

Set up a complete demo environment where developers can:

1. Build the Quantroot Bitcoin Core fork from source inside Docker
2. Run a `bitcoind` regtest node in a container (BIP 368/369 pre-activated)
3. Launch `bitcoin-qt` natively, connecting to the regtest node or public networks
4. Test forward compatibility by creating quantum-insured outputs on mainnet/testnets

---

## Architecture

```
┌─────────────────────────────────────┐
│  Docker: build stage                │
│  (multi-arch, debian bookworm)      │
│  cmake → binaries in build/bitcoin/bin/ │
└──────────────┬──────────────────────┘
               │ volume mount
┌──────────────▼──────────────────────┐
│  Docker: bitcoind (regtest)         │
│  compose service, port 18443/18444  │
│  BIP 368/369 active from block 1   │
└──────────────┬──────────────────────┘
               │ RPC (localhost:18443)
┌──────────────▼──────────────────────┐
│  Native: bitcoin-qt                 │
│  regtest → connects to container    │
│  mainnet/testnet/signet → public    │
└─────────────────────────────────────┘
```

---

## Components

### 1. Build Dockerfile

**File:** `services/bitcoin/Dockerfile`

Multi-stage build:

- **Builder stage** (`debian:bookworm-slim`):
  - Install build deps: `cmake`, `g++`, `make`, `pkg-config`, `libevent-dev`,
    `libboost-dev`, `libsqlite3-dev`, `libzmq3-dev`, `qtbase5-dev`,
    `qttools5-dev`, `qttools5-dev-tools`, `libqrencode-dev`, `libdbus-1-dev`
  - Copy `repos/bitcoin` source
  - Build with cmake:
    ```
    cmake -B /build \
      -DBUILD_DAEMON=ON \
      -DBUILD_CLI=ON \
      -DBUILD_GUI=ON \
      -DBUILD_TX=ON \
      -DBUILD_UTIL=ON \
      -DBUILD_TESTS=OFF \
      -DBUILD_BENCH=OFF \
      -DENABLE_WALLET=ON \
      -DWITH_ZMQ=ON \
      -DWITH_QRENCODE=ON \
      -DCMAKE_BUILD_TYPE=Release
    cmake --build /build -j$(nproc)
    ```

- **Runtime stage** (`debian:bookworm-slim`):
  - Install runtime deps only: `libevent-2.1-7`, `libsqlite3-0`, `libzmq5`,
    `libqrencode4`
  - Copy binaries from builder: `bitcoind`, `bitcoin-cli`, `bitcoin-tx`,
    `bitcoin-util`
  - `bitcoin-cli` must be in the runtime image so that developers can
    `docker exec` into the container and command the node directly:
    `make shell-bitcoin` → `bitcoin-cli -regtest getblockchaininfo`
  - Do NOT include `bitcoin-qt` in the runtime image (runs natively)
  - Create non-root user `bitcoin`
  - Expose ports: 8332, 8333, 18332, 18333, 18443, 18444, 38332, 38333
  - Default entrypoint: `bitcoind`

- **Export stage** (build target `export`):
  - Copy ALL binaries (including `bitcoin-qt`) into `bin/` within the output dir
  - `--output=type=local,dest=build/bitcoin` produces `build/bitcoin/bin/bitcoind`, etc.
  - Used by `make build-bitcoin` to extract binaries to `build/bitcoin/bin/`

**Cross-arch support:** The Dockerfile uses standard Debian packages — works
on `linux/amd64` and `linux/arm64` via `docker buildx`. No `depends/` or Guix
needed for the demo. Configurable via `TARGETARCH` build arg if needed.

### 2. Bitcoin config files

**File:** `config/bitcoin/regtest.conf`

```ini
regtest=1
server=1
txindex=1
rpcuser=quantroot
rpcpassword=quantroot
rpcallowip=0.0.0.0/0
rpcbind=0.0.0.0
zmqpubrawblock=tcp://0.0.0.0:28332
zmqpubrawtx=tcp://0.0.0.0:28333
[regtest]
rpcport=18443
```

### 3. Docker Compose service

**File:** `compose.yml` — add `bitcoin` service

```yaml
services:
  bitcoin:
    build:
      context: .
      dockerfile: services/bitcoin/Dockerfile
      target: runtime
    container_name: quantroot-bitcoin
    restart: unless-stopped
    volumes:
      - ./data/bitcoin:/data
      - ./config/bitcoin:/config:ro
    command: >
      bitcoind
        -conf=/config/regtest.conf
        -datadir=/data
        -printtoconsole
    ports:
      - "18443:18443"   # RPC
      - "18444:18444"   # P2P
      - "28332:28332"   # ZMQ block
      - "28333:28333"   # ZMQ tx
    logging: *default-logging
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "bitcoin-cli", "-regtest", "-rpcuser=quantroot",
             "-rpcpassword=quantroot", "getblockchaininfo"]
```

Update `CORE_SERVICES` in Makefile: `CORE_SERVICES := bitcoin`

### 4. Build extraction target

**File:** `Makefile` — add targets

```makefile
# Build Bitcoin Core binaries and extract to build/bitcoin/bin/
build-bitcoin:
	@mkdir -p build/bitcoin
	docker build \
		--target=export \
		--output=type=local,dest=build/bitcoin \
		-f services/bitcoin/Dockerfile .

# Launch bitcoin-qt natively (regtest, own node, peers with container)
qt-regtest:
	./build/bitcoin/bin/bitcoin-qt \
		-regtest \
		-addnode=127.0.0.1:18444 \
		-fallbackfee=0.0001

# Launch bitcoin-qt natively (mainnet)
qt-mainnet:
	./build/bitcoin/bin/bitcoin-qt

# Launch bitcoin-qt natively (testnet)
qt-testnet:
	./build/bitcoin/bin/bitcoin-qt -testnet

# Launch bitcoin-qt natively (signet)
qt-signet:
	./build/bitcoin/bin/bitcoin-qt -signet

# Open a shell in the running bitcoind container (bitcoin-cli available)
shell-bitcoin:
	docker exec -it quantroot-bitcoin /bin/bash
```

### 5. Qt launcher script

**File:** `scripts/launch-qt.sh`

Wrapper script that:
- Checks `build/bitcoin/bin/bitcoin-qt` exists, prompts to `make build-bitcoin` if not
- Accepts `--regtest`, `--testnet`, `--signet`, `--mainnet` (default)
- For regtest: passes `-addnode=127.0.0.1:18444` to peer with the container node.
  bitcoin-qt runs its own full node with its own datadir — separate wallet, separate
  chain state. This enables testing peer interactions between the two nodes.
- For public networks: launches with no special flags (connects to public peers)

### 6. Environment variables

**File:** `.env.example` — update with bitcoin RPC config

```
BITCOIN_RPC_USER=quantroot
BITCOIN_RPC_PASS=quantroot
BITCOIN_RPC_PORT=18443
```

---

## Makefile targets (summary)

| Target | Description |
|--------|-------------|
| `make build-bitcoin` | Build fork binaries, extract to `build/bitcoin/bin/` |
| `make start` | Start bitcoind regtest container |
| `make shell-bitcoin` | Open a shell in the container (`bitcoin-cli` available) |
| `make qt-regtest` | Launch bitcoin-qt as own regtest node, peers with container |
| `make qt-mainnet` | Launch bitcoin-qt on mainnet (public peers) |
| `make qt-testnet` | Launch bitcoin-qt on testnet (public peers) |
| `make qt-signet` | Launch bitcoin-qt on signet (public peers) |

---

## File list

| File | Action | Description |
|------|--------|-------------|
| `services/bitcoin/Dockerfile` | Create | Multi-stage build + runtime + export |
| `config/bitcoin/regtest.conf` | Create | Regtest node configuration |
| `compose.yml` | Modify | Add bitcoin service |
| `Makefile` | Modify | Add build-bitcoin, qt-* targets |
| `scripts/launch-qt.sh` | Create | Qt launcher wrapper |
| `.env.example` | Modify | Add RPC credentials |

---

## Developer workflow

```bash
# First time: build the binaries (~10 min)
make build-bitcoin

# Start the regtest node (container)
make start

# Open bitcoin-qt as its own regtest node, peers with the container
make qt-regtest
# → Two independent nodes on the same regtest network
# → Each has its own wallet and chain state
# → Test mining on one, spending on the other

# Or test forward compatibility on mainnet
make qt-mainnet
```

---

## Forward compatibility demo

On mainnet/testnet/signet, developers can:

1. Create a wallet in bitcoin-qt
2. Run `createsphincskey` via the console
3. Generate quantum-insured addresses (`getnewaddress`)
4. Receive real funds to those addresses
5. Spend via key-path (works today — standard Taproot spend)
6. Verify the hybrid tapleaf exists in the descriptor (`listdescriptors`)

The SPHINCS+ tapleaf is valid but dormant — `OP_NOP4` is a no-op on the
current network. When/if the soft fork activates, those outputs become
fully quantum-insured without any migration.

---

## Verification

```bash
# Build succeeds
make build-bitcoin
ls build/bitcoin/bin/bitcoind build/bitcoin/bin/bitcoin-qt build/bitcoin/bin/bitcoin-cli

# Container starts and is healthy
make start
make health

# Qt connects to regtest
make qt-regtest
# → bitcoin-qt opens, shows regtest, can run createsphincskey in console

# Qt connects to mainnet
make qt-mainnet
# → bitcoin-qt opens, syncs headers from public peers
```
