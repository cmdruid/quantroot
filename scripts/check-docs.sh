#!/usr/bin/env bash
set -euo pipefail

# Documentation consistency gate.
# Checks that required docs exist and key links are not broken.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

ERRORS=0

# Required root files
for file in README.md CONTRIBUTING.md CHANGELOG.md CLAUDE.md Makefile compose.yml .env.example; do
  if [ ! -f "$ROOT_DIR/$file" ]; then
    log_error "Missing root file: $file"
    ERRORS=$((ERRORS + 1))
  fi
done

# Required knowledge base entrypoints
for file in docs/INDEX.md dev/README.md test/README.md services/README.md; do
  if [ ! -f "$ROOT_DIR/$file" ]; then
    log_error "Missing KB entrypoint: $file"
    ERRORS=$((ERRORS + 1))
  fi
done

# Required dev templates
for dir in adr audit reports plans; do
  for file in README.md TEMPLATE.md; do
    if [ ! -f "$ROOT_DIR/dev/$dir/$file" ]; then
      log_error "Missing dev/$dir/$file"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

if [ "$ERRORS" -gt 0 ]; then
  log_error "$ERRORS doc consistency issue(s) found."
  exit 1
fi

log_info "Documentation consistency OK."
