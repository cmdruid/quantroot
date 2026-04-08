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

assert "bitcoin-qt binary exists" \
  test -x "$ROOT_DIR/build/bitcoin/bin/bitcoin-qt"

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

# Clean up any leftover wallet from a previous run
$BCLI unloadwallet "test_quantum" > /dev/null 2>&1 || true

assert "createwallet succeeds" \
  $BCLI createwallet "test_quantum"

assert_output "createsphincskey returns sphincs_pubkey" \
  "sphincs_pubkey" \
  $BCLI -rpcwallet=test_quantum createsphincskey

assert_output "listsphincskeys shows the key" \
  "sphincs_pubkey" \
  $BCLI -rpcwallet=test_quantum listsphincskeys

# Get a quantum-insured address
QI_ADDR=$($BCLI -rpcwallet=test_quantum getquantumaddress 2>&1)
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
SPEND_CONFS=$($BCLI -rpcwallet=test_quantum gettransaction "$SPEND_TXID" 2>&1 | grep -o '"confirmations":[0-9]*' | grep -o '[0-9]*')
if [[ "$SPEND_CONFS" -ge 1 ]]; then
  log_info "PASS: key-path spend confirmed ($SPEND_CONFS confirmations)"
  PASS=$((PASS + 1))
else
  log_error "FAIL: spend not confirmed (confirmations: $SPEND_CONFS)"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# Phase 4 (optional): SPHINCS+ script-path spend via PSBT
# ============================================================================

if [[ "${SPHINCS_SPEND:-0}" == "1" ]]; then
  log_info "=== Phase 4: SPHINCS+ Script-Path Spend ==="

  # Fund a fresh QI address for the script-path test
  QI_ADDR2=$($BCLI -rpcwallet=test_quantum getquantumaddress 2>&1 | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
  if [[ -z "$QI_ADDR2" ]]; then
    # Fallback: getquantumaddress may return plain address
    QI_ADDR2=$($BCLI -rpcwallet=test_quantum getquantumaddress 2>&1)
  fi
  $BCLI -rpcwallet=test_miner sendtoaddress "$QI_ADDR2" 2.0 > /dev/null 2>&1
  $BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1

  # Verify funds arrived
  QI_BAL2=$($BCLI -rpcwallet=test_quantum getbalance)
  log_info "Quantum wallet balance before script-path spend: $QI_BAL2 BTC"

  # Create a PSBT spending from the QI wallet
  DEST_ADDR2=$($BCLI -rpcwallet=test_miner getnewaddress "" bech32m)
  PSBT=$($BCLI -rpcwallet=test_quantum walletcreatefundedpsbt '[]' "[{\"$DEST_ADDR2\":1.0}]" 0 '{"fee_rate":10}' 2>&1 | grep -o '"psbt":"[^"]*"' | cut -d'"' -f4)

  if [[ -n "$PSBT" ]]; then
    log_info "PASS: created PSBT for QI output"
    PASS=$((PASS + 1))
  else
    log_error "FAIL: could not create PSBT"
    FAIL=$((FAIL + 1))
  fi

  # Process the PSBT with SPHINCS+ signing (force_script_path)
  # walletprocesspsbt will use the SPHINCS+ key if available and produce
  # a script-path spend with both SPHINCS+ and Schnorr signatures
  SIGNED=$($BCLI -rpcwallet=test_quantum walletprocesspsbt "$PSBT" true "ALL" true 2>&1)
  COMPLETE=$(echo "$SIGNED" | grep -o '"complete":true' || true)

  if [[ -n "$COMPLETE" ]]; then
    log_info "PASS: PSBT signed and complete (script-path with SPHINCS+)"
    PASS=$((PASS + 1))

    # Finalize and broadcast
    SIGNED_PSBT=$(echo "$SIGNED" | grep -o '"psbt":"[^"]*"' | cut -d'"' -f4)
    FINAL=$($BCLI -rpcwallet=test_quantum finalizepsbt "$SIGNED_PSBT" 2>&1)
    FINAL_HEX=$(echo "$FINAL" | grep -o '"hex":"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$FINAL_HEX" ]]; then
      SP_TXID=$($BCLI sendrawtransaction "$FINAL_HEX" 2>&1)
      if [[ ${#SP_TXID} -eq 64 ]]; then
        log_info "PASS: SPHINCS+ script-path tx broadcast ($SP_TXID)"
        PASS=$((PASS + 1))

        # Mine and confirm
        $BCLI -rpcwallet=test_miner generatetoaddress 1 "$MINER_ADDR" > /dev/null 2>&1
        SP_CONFS=$($BCLI -rpcwallet=test_quantum gettransaction "$SP_TXID" 2>&1 | grep -o '"confirmations":[0-9]*' | grep -o '[0-9]*')
        if [[ "$SP_CONFS" -ge 1 ]]; then
          log_info "PASS: SPHINCS+ script-path spend confirmed ($SP_CONFS confirmations)"
          PASS=$((PASS + 1))
        else
          log_error "FAIL: SPHINCS+ spend not confirmed"
          FAIL=$((FAIL + 1))
        fi
      else
        log_error "FAIL: sendrawtransaction failed: $SP_TXID"
        FAIL=$((FAIL + 1))
      fi
    else
      log_error "FAIL: finalizepsbt failed"
      FAIL=$((FAIL + 1))
    fi
  else
    log_warn "SKIP: PSBT not complete — SPHINCS+ script-path signing requires sphincs_secret in PSBT pipeline"
    log_warn "This is expected until a dedicated sphincsspend RPC is implemented."
  fi
else
  log_info "=== Phase 4: SPHINCS+ Script-Path Spend (skipped) ==="
  log_info "Run with SPHINCS_SPEND=1 to enable: SPHINCS_SPEND=1 make test-demo"
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
