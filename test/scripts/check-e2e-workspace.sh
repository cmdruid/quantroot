#!/usr/bin/env bash
set -euo pipefail

# Verify E2E workspace integrity (static and runtime checks).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ERRORS=0

# Static checks
log_info "Checking E2E workspace..."

if [ ! -f "$TEST_DIR/e2e/pytest.ini" ]; then
  log_error "Missing pytest.ini"
  ERRORS=$((ERRORS + 1))
fi

if [ ! -f "$TEST_DIR/e2e/conftest.py" ]; then
  log_error "Missing conftest.py"
  ERRORS=$((ERRORS + 1))
fi

if [ ! -f "$TEST_DIR/e2e/requirements.txt" ]; then
  log_error "Missing requirements.txt"
  ERRORS=$((ERRORS + 1))
fi

if [ ! -d "$TEST_DIR/e2e/cases" ]; then
  log_error "Missing cases/ directory"
  ERRORS=$((ERRORS + 1))
fi

# Runtime checks
if command -v python &> /dev/null; then
  if ! python -c "import pytest" 2>/dev/null; then
    log_warn "pytest not installed — run: pip install -r test/e2e/requirements.txt"
  fi
else
  log_warn "python not found in PATH"
fi

if [ "$ERRORS" -gt 0 ]; then
  log_error "$ERRORS workspace issue(s) found."
  exit 1
fi

log_info "E2E workspace OK."
