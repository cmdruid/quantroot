#!/usr/bin/env bash
set -euo pipefail

# Refresh service dependencies across the monorepo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Updating submodules..."
cd "$ROOT_DIR"
git submodule sync --recursive
git submodule update --init --recursive

echo "Rebuilding containers..."
docker compose build

echo "Update complete."
