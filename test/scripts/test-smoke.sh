#!/usr/bin/env bash
set -euo pipefail

# Run smoke tests — fast, stateful service health checks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log_info "Running smoke tests..."

# Add smoke test checks here, e.g.:
# wait_for_service "http://localhost:18443/" 10

log_info "Smoke tests passed."
