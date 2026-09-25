#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf '[NEXALI][PATCHCTL][ERROR] Run from inside the Nexali repository.\n' >&2
  exit 1
}
case "${1:-status}" in
  status) exec "$repo_root/scripts/patch/engine.sh" status ;;
  cleanup)
    shift || true
    exec "$repo_root/scripts/patch/engine.sh" cleanup "$@"
    ;;
  *)
    printf 'Usage: %s [status|cleanup [--apply]]\n' "$0" >&2
    exit 2
    ;;
esac
