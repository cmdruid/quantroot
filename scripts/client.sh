#!/usr/bin/env bash
set -euo pipefail

# Open an interactive client shell.
# Customize this to connect to your primary client service.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

log_info "Opening interactive client shell..."

# Example: docker compose exec <client-service> /bin/bash
log_warn "No client service configured yet. Edit scripts/client.sh to set one up."
