#!/usr/bin/env bash
# Demo environment E2E test.
# Exercises: build verification, wallet operations, full spend cycle.
#
# Prerequisites: make build-bitcoin && make start (BG=1)
# Usage: ./test/scripts/test-demo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CONTAINER="quantroot-bitcoin"
BCLI="docker exec $CONTAINER bitcoin-cli -regtest -rpcuser=quantroot -rpcpassword=quantroot"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    log_info "PASS: $desc"
    PASS=$((PASS + 1))
  else
    log_error "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_output() {
  local desc="$1"
  local expected="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -q "$expected"; then
    log_info "PASS: $desc"
    PASS=$((PASS + 1))
  else
    log_error "FAIL: $desc (expected '$expected', got '$output')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Phase 1: Infrastructure
# ============================================================================

log_info "=== Phase 1: Infrastructure ==="

assert "bitcoind binary exists" \
  test -x "$ROOT_DIR/build/bitcoin/bin/bitcoind"

assert "bitcoin-cli binary exists" \
  test -x "$ROOT_DIR/build/bitcoin/bin/bitcoin-cli"

# bitcoin-qt is built natively, not in Docker
if [ -x "$ROOT_DIR/build/bitcoin/bin/bitcoin-qt" ]; then
  log_info "PASS: bitcoin-qt binary exists"
  PASS=$((PASS + 1))
else
  log_info "SKIP: bitcoin-qt not in Docker build (built natively)"
fi

assert "container is running" \
  docker inspect -f '{{.State.Running}}' "$CONTAINER"

assert "bitcoin-cli works in container" \
  $BCLI getblockchaininfo

assert_output "node is on regtest" \
  "regtest" \
  $BCLI getblockchaininfo

# ============================================================================
# Phase 2: Wallet operations
# ============================================================================

log_info "=== Phase 2: Wallet Operations ==="

# Clean up any leftover wallets from a previous run
$BCLI unloadwallet "test_quantum" > /dev/null 2>&1 || true
$BCLI unloadwallet "test_miner" > /dev/null 2>&1 || true
docker exec "$CONTAINER" rm -rf /data/regtest/wallets/test_quantum /data/regtest/wallets/test_miner > /dev/null 2>&1 || true

assert "createwallet succeeds" \
  $BCLI createwallet "test_quantum"

assert_output "createsphincskey returns sphincs_pubkey" \
  "sphincs_pubkey" \
  $BCLI -rpcwallet=test_quantum createsphincskey

assert_output "listsphincskeys shows the key" \
  "sphincs_pubkey" \
  $BCLI -rpcwallet=test_quantum listsphincskeys

# Get a quantum-insured address (returns JSON, extract address field)
QI_ADDR_JSON=$($BCLI -rpcwallet=test_quantum getquantumaddress 2>&1)
QI_ADDR=$(echo "$QI_ADDR_JSON" | tr -d ' \n' | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
if [[ "$QI_ADDR" == bcrt1p* ]]; then
  log_info "PASS: getquantumaddress returns bech32m address ($QI_ADDR)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: getquantumaddress unexpected output: $QI_ADDR"
  FAIL=$((FAIL + 1))
fi

assert_output "exportqpub returns Q1-prefixed key" \
  "Q1" \
  $BCLI -rpcwallet=test_quantum exportqpub

# ============================================================================
# Phase 3: Full spend cycle
# ============================================================================

log_info "=== Phase 3: Full Spend Cycle ==="

# Create a funding wallet for mining
$BCLI unloadwallet "test_miner" > /dev/null 2>&1 || true
$BCLI createwallet "test_miner" > /dev/null 2>&1

MINER_ADDR=$($BCLI -rpcwallet=test_miner getnewaddress "" bech32m)

# Mine blocks to get spendable coins (101 for coinbase maturity)
log_info "Mining 101 blocks..."
$BCLI -rpcwallet=test_miner generatetoaddress 101 "$MINER_ADDR" > /dev/null 2>&1

MINER_BALANCE=$($BCLI -rpcwallet=test_miner getbalance)
log_info "Miner balance: $MINER_BALANCE BTC"

# Send to quantum-insured address
log_info "Sending 1 BTC to quantum-insured address..."
SEND_TXID=$($BCLI -rpcwallet=test_miner sendtoaddress "$QI_ADDR" 1.0 2>&1)
if [[ ${#SEND_TXID} -eq 64 ]]; then
  log_info "PASS: sendtoaddress returned txid ($SEND_TXID)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: sendtoaddress unexpected output: $SEND_TXID"
  FAIL=$((FAIL + 1))
fi

# Mine to confirm
$BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1

# Verify the quantum wallet received the funds
QI_BALANCE=$($BCLI -rpcwallet=test_quantum getbalance)
if (( $(echo "$QI_BALANCE > 0" | bc -l) )); then
  log_info "PASS: quantum wallet received funds ($QI_BALANCE BTC)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: quantum wallet balance is $QI_BALANCE"
  FAIL=$((FAIL + 1))
fi

# Spend from quantum-insured address (key-path)
log_info "Spending from quantum-insured address via key-path..."
SPEND_ADDR=$($BCLI -rpcwallet=test_miner getnewaddress "" bech32m)
SPEND_TXID=$($BCLI -rpcwallet=test_quantum sendtoaddress "$SPEND_ADDR" 0.5 2>&1)
if [[ ${#SPEND_TXID} -eq 64 ]]; then
  log_info "PASS: key-path spend returned txid ($SPEND_TXID)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: key-path spend unexpected output: $SPEND_TXID"
  FAIL=$((FAIL + 1))
fi

# Mine to confirm the spend
$BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1

# Verify the spend confirmed
SPEND_CONFS=$($BCLI -rpcwallet=test_quantum gettransaction "$SPEND_TXID" 2>&1 | tr -d " " | grep -o '"confirmations":[0-9]*' | grep -o '[0-9]*')
if [[ "$SPEND_CONFS" -ge 1 ]]; then
  log_info "PASS: key-path spend confirmed ($SPEND_CONFS confirmations)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: spend not confirmed (confirmations: $SPEND_CONFS)"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# Phase 4: SPHINCS+ emergency script-path spend
# ============================================================================

log_info "=== Phase 4: SPHINCS+ Emergency Spend ==="

# Fund a QI address for the emergency spend test
QI_ADDR2=$($BCLI -rpcwallet=test_quantum getquantumaddress 2>&1 | tr -d ' \n' | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
$BCLI -rpcwallet=test_miner sendtoaddress "$QI_ADDR2" 2.0 > /dev/null 2>&1
$BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1

# Emergency spend via sphincsspend
DEST_ADDR2=$($BCLI -rpcwallet=test_miner getnewaddress "" bech32m)
SP_RESULT=$($BCLI -rpcwallet=test_quantum sphincsspend "$DEST_ADDR2" 1.0 2>&1)
SP_TXID=$(echo "$SP_RESULT" | tr -d ' \n' | grep -o '"txid":"[^"]*"' | cut -d'"' -f4)

if [[ ${#SP_TXID} -eq 64 ]]; then
  log_info "PASS: sphincsspend returned txid ($SP_TXID)"
  PASS=$((PASS + 1))

  # Mine and confirm
  $BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1
  SP_CONFS=$($BCLI -rpcwallet=test_quantum gettransaction "$SP_TXID" 2>&1 | tr -d ' \n' | grep -o '"confirmations":[0-9]*' | grep -o '[0-9]*')
  if [[ "$SP_CONFS" -ge 1 ]]; then
    log_info "PASS: SPHINCS+ emergency spend confirmed ($SP_CONFS confirmations)"
    PASS=$((PASS + 1))
  else
    log_error "FAIL: SPHINCS+ spend not confirmed"
    FAIL=$((FAIL + 1))
  fi
else
  log_error "FAIL: sphincsspend failed: $SP_RESULT"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# Cleanup
# ============================================================================

log_info "Cleaning up test wallets..."
$BCLI unloadwallet "test_quantum" > /dev/null 2>&1 || true
$BCLI unloadwallet "test_miner" > /dev/null 2>&1 || true

# ============================================================================
# Summary
# ============================================================================

echo ""
log_info "=== Results ==="
log_info "Passed: $PASS"
if [[ $FAIL -gt 0 ]]; then
  log_error "Failed: $FAIL"
  exit 1
else
  log_info "Failed: 0"
  log_info "All demo tests passed!"
fi
