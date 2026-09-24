#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve from this versioned file so policy helpers also work when invoked by
# repository validators from an arbitrary current working directory.
NEXALI_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$NEXALI_REPO_ROOT/eng/git-policy.conf"

nexali_current_branch() {
  git -C "$NEXALI_REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

nexali_is_protected_branch() {
  local candidate="$1" branch
  for branch in "${NEXALI_PROTECTED_BRANCHES[@]}"; do
    [[ "$candidate" == "$branch" ]] && return 0
  done
  return 1
}

nexali_is_valid_topic_branch() {
  local candidate="$1"
  [[ "$candidate" =~ $NEXALI_BRANCH_NAME_REGEX ]]
}

nexali_branch_type() {
  printf '%s\n' "${1%%/*}"
}

nexali_hook_error() {
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    printf '\033[1;31m[NEXALI][GIT-POLICY][ERROR]\033[0m %s\n' "$1" >&2
  else
    printf '[NEXALI][GIT-POLICY][ERROR] %s\n' "$1" >&2
  fi
}

nexali_hook_info() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    printf '\033[1;36m[NEXALI][GIT-POLICY][INFO]\033[0m %s\n' "$1"
  else
    printf '[NEXALI][GIT-POLICY][INFO] %s\n' "$1"
  fi
}
