# Multi-stage build for Quantroot Bitcoin Core fork
# Produces: bitcoind, bitcoin-cli, bitcoin-tx, bitcoin-util, bitcoin-qt

# ---------------------------------------------------------------------------
# Builder stage: compile from source
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make pkg-config \
    libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
    qtbase5-dev qttools5-dev qttools5-dev-tools \
    libqrencode-dev libdbus-1-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY repos/bitcoin /src

RUN cmake -S /src -B /build \
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
      -DCMAKE_BUILD_TYPE=Release \
  && cmake --build /build -j"$(nproc)"

# ---------------------------------------------------------------------------
# Runtime stage: minimal image for running bitcoind in a container
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libevent-2.1-7 libsqlite3-0 libzmq5 libqrencode4 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash bitcoin

COPY --from=builder /build/bin/bitcoind    /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-cli /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-tx  /usr/local/bin/
COPY --from=builder /build/bin/bitcoin-util /usr/local/bin/

USER bitcoin

EXPOSE 8332 8333 18332 18333 18443 18444 38332 38333

ENTRYPOINT ["bitcoind"]

# ---------------------------------------------------------------------------
# Export stage: extract all binaries (including bitcoin-qt) to host
# Used by: make build-bitcoin
# ---------------------------------------------------------------------------
FROM scratch AS export

COPY --from=builder /build/bin/bitcoind      /bin/
COPY --from=builder /build/bin/bitcoin-cli   /bin/
COPY --from=builder /build/bin/bitcoin-tx    /bin/
COPY --from=builder /build/bin/bitcoin-util  /bin/
COPY --from=builder /build/bin/bitcoin-qt    /bin/
