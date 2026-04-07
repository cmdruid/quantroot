#!/usr/bin/env bash
set -euo pipefail

# Main E2E test runner.
# Usage: ./test/scripts/test-e2e.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SESSION_LOG="$LOG_DIR/e2e-$(date +%Y%m%d-%H%M%S).log"

log_info "Running E2E test suite..."
log_info "Session log: $SESSION_LOG"

# Wait for stack readiness
"$SCRIPT_DIR/wait-e2e-ready.sh"

# Run pytest
cd "$TEST_DIR/e2e"
python -m pytest "${@:---v}" 2>&1 | tee "$SESSION_LOG"

log_info "E2E tests complete. Log: $SESSION_LOG"
