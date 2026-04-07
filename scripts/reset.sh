#!/usr/bin/env bash
set -euo pipefail

# Reset runtime state — removes data/, logs/, and .tmp/ contents.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

log_info "Resetting runtime state..."

# Clean runtime directories (preserve .gitkeep)
for dir in data logs .tmp; do
  target="$ROOT_DIR/$dir"
  if [ -d "$target" ]; then
    find "$target" -mindepth 1 -not -name '.gitkeep' -delete 2>/dev/null || true
    log_info "Cleaned $dir/"
  fi
done

log_info "Runtime state reset."
