#!/usr/bin/env bash
set -euo pipefail

# Wait for the stack to be ready before running E2E tests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log_info "Checking stack readiness..."

# Add service readiness checks here, e.g.:
# wait_for_service "http://localhost:18443/" 30

log_info "Stack is ready."
