#!/usr/bin/env bash
set -euo pipefail

# Run a single E2E scenario for reproduction/debugging.
# Usage: ./test/scripts/e2e.sh <test-path>
# Example: ./test/scripts/e2e.sh cases/test_health.py::test_service_responds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if [ $# -eq 0 ]; then
  log_error "Usage: $0 <test-path>"
  log_error "Example: $0 cases/test_health.py::test_service_responds"
  exit 1
fi

cd "$TEST_DIR/e2e"
python -m pytest "$@" -v --tb=long
