#!/usr/bin/env bash
# Launch bitcoin-qt from the local build directory.
# Usage: ./scripts/launch-qt.sh [--regtest|--testnet|--signet|--mainnet]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
QT_BIN="$ROOT_DIR/build/bitcoin/bin/bitcoin-qt"

if [[ ! -x "$QT_BIN" ]]; then
  echo "bitcoin-qt not found at $QT_BIN"
  echo "Run 'make build-bitcoin' first."
  exit 1
fi

NETWORK="${1:---mainnet}"

case "$NETWORK" in
  --regtest)
    mkdir -p "$ROOT_DIR/data/demo-qt"
    exec "$QT_BIN" -regtest -datadir="$ROOT_DIR/data/demo-qt" -addnode=127.0.0.1:19444 -fallbackfee=0.0001
    ;;
  --testnet)
    exec "$QT_BIN" -testnet
    ;;
  --signet)
    exec "$QT_BIN" -signet
    ;;
  --mainnet|*)
    exec "$QT_BIN"
    ;;
esac
