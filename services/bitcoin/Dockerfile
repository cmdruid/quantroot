# Multi-stage build for Quantroot Bitcoin Core fork
# Produces: bitcoind, bitcoin-cli, bitcoin-tx, bitcoin-util, bitcoin-qt

# ---------------------------------------------------------------------------
# Builder stage: compile from source
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make pkg-config \
    libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
    libqrencode-dev libdbus-1-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY repos/bitcoin /src

RUN cmake -S /src -B /build \
      -DBUILD_DAEMON=ON \
      -DBUILD_CLI=ON \
      -DBUILD_GUI=OFF \
      -DBUILD_TX=ON \
      -DBUILD_UTIL=ON \
      -DBUILD_TESTS=OFF \
      -DBUILD_BENCH=OFF \
      -DENABLE_WALLET=ON \
      -DENABLE_IPC=OFF \
      -DWITH_ZMQ=ON \
      -DWITH_QRENCODE=ON \
      -DCMAKE_BUILD_TYPE=Release \
  && cmake --build /build -j"$(nproc)"

# ---------------------------------------------------------------------------
# Runtime stage: minimal image for running bitcoind in a container
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libevent-dev libsqlite3-0 libzmq5 libqrencode4 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/bin/bitcoind    /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-cli /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-tx  /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-util /usr/local/bin/

EXPOSE 8332 8333 18332 18333 18443 18444 38332 38333

ENTRYPOINT ["bitcoind"]

# ---------------------------------------------------------------------------
# Export stage: extract server binaries to host
# bitcoin-qt is built natively (requires Qt6 which is not in bookworm)
# Used by: make build-bitcoin
# ---------------------------------------------------------------------------
FROM scratch AS export

COPY --from=builder /build/bin/bitcoind      /bin/
COPY --from=builder /build/bin/bitcoin-cli   /bin/
COPY --from=builder /build/bin/bitcoin-tx    /bin/
COPY --from=builder /build/bin/bitcoin-util  /bin/
