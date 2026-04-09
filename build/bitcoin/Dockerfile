# Quantroot Bitcoin Core builder
# Builds all binaries including bitcoin-qt from the quantroot fork.
#
# Usage:
#   docker build --output=type=local,dest=. -f build/bitcoin/Dockerfile .
#   # Outputs binaries to ./bin/

# ---------------------------------------------------------------------------
# Builder stage: Ubuntu 24.04 (has Qt6 packages for bitcoin-qt)
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make pkg-config \
    libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
    qt6-base-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools \
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
      -DENABLE_IPC=OFF \
      -DWITH_ZMQ=ON \
      -DWITH_QRENCODE=ON \
      -DCMAKE_BUILD_TYPE=Release \
  && cmake --build /build -j"$(nproc)"

# ---------------------------------------------------------------------------
# Export stage: extract all binaries to host
# ---------------------------------------------------------------------------
FROM scratch AS export

COPY --from=builder /build/bin/bitcoind      /bin/
COPY --from=builder /build/bin/bitcoin-cli   /bin/
COPY --from=builder /build/bin/bitcoin-tx    /bin/
COPY --from=builder /build/bin/bitcoin-util  /bin/
COPY --from=builder /build/bin/bitcoin-qt    /bin/
