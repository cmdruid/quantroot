#!/usr/bin/env bash
# Docker helper functions for runtime scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

compose_exec() {
  docker compose exec "$@"
}

compose_run() {
  docker compose run --rm "$@"
}

container_healthy() {
  local container="$1"
  local status
  status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
  [ "$status" = "healthy" ]
}
