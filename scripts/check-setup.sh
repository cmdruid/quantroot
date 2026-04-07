#!/usr/bin/env bash
set -euo pipefail

# Verify prerequisites for running the Quantroot stack.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/util.sh"

ERRORS=0

# Check Docker
if ! command -v docker &> /dev/null; then
  log_error "Docker is not installed"
  ERRORS=$((ERRORS + 1))
else
  log_info "Docker: $(docker --version)"
fi

# Check Docker Compose v2
if ! docker compose version &> /dev/null; then
  log_error "Docker Compose v2 is not available"
  ERRORS=$((ERRORS + 1))
else
  log_info "Compose: $(docker compose version)"
fi

# Check .env
if [ ! -f "$ROOT_DIR/.env" ]; then
  log_error "Missing .env file — copy from .env.example"
  ERRORS=$((ERRORS + 1))
else
  log_info ".env file present"
fi

# Check git
if ! command -v git &> /dev/null; then
  log_error "Git is not installed"
  ERRORS=$((ERRORS + 1))
else
  log_info "Git: $(git --version)"
fi

if [ "$ERRORS" -gt 0 ]; then
  log_error "$ERRORS prerequisite issue(s) found."
  exit 1
fi

log_info "All prerequisites OK."
