#!/usr/bin/env bash
# Shared bash library for test scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$ROOT_DIR/test"
LOG_DIR="$ROOT_DIR/logs/sessions"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Helpers
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

wait_for_service() {
  local url="$1"
  local max_attempts="${2:-30}"
  local attempt=0

  log_info "Waiting for $url ..."
  while ! curl -sf "$url" > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      log_error "Service at $url did not become ready after $max_attempts attempts"
      return 1
    fi
    sleep 2
  done
  log_info "Service at $url is ready."
}
