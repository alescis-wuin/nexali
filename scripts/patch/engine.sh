#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf '[NEXALI][PATCH][ERROR] Current directory is not inside a Git repository.\n' >&2
  exit 1
}
exec python3 "$repo_root/scripts/patch/engine.py" "$@"
