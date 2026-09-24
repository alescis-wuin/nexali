#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$repo_root/.githooks/lib/policy.sh"

usage() {
  cat <<USAGE
Usage: ./scripts/git-start.sh <type> <name> [--no-sync]
Example: ./scripts/git-start.sh feature drive-upload
USAGE
}
[[ $# -ge 2 ]] || { usage; exit 2; }
type="$1"; name="$2"; shift 2
sync=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sync) sync=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
branch="$type/$name"
if ! nexali_is_valid_topic_branch "$branch"; then
  nexali_hook_error "Invalid branch '$branch'. Expected <type>/<name>, lowercase kebab-case."
  nexali_hook_info "Allowed types: ${NEXALI_BRANCH_TYPES[*]}"
  exit 1
fi
if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --cached --quiet; then
  nexali_hook_error "Tracked worktree changes exist. Commit or stash them before creating a branch."
  exit 1
fi
if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
  nexali_hook_error "Local branch already exists: $branch"
  exit 1
fi
if [[ "$sync" -eq 1 ]] && git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
  git -C "$repo_root" fetch --prune origin
  if git -C "$repo_root" show-ref --verify --quiet refs/remotes/origin/develop; then
    git -C "$repo_root" switch develop
    git -C "$repo_root" merge --ff-only origin/develop
  else
    git -C "$repo_root" switch develop
  fi
else
  git -C "$repo_root" switch develop
fi
git -C "$repo_root" switch -c "$branch"
printf '[NEXALI][GIT] Created branch %s from develop.\n' "$branch"
