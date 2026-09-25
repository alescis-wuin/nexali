#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'; yellow='\033[33m'; else reset=''; bold=''; cyan=''; green=''; red=''; yellow=''; fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == ERROR ]]&&c="$red"; [[ "$l" == WARN ]]&&c="$yellow"; printf '%b[NEXALI][GIT-GOVERNANCE]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(
  eng/git-policy.conf .githooks/lib/policy.sh .githooks/pre-commit .githooks/commit-msg .githooks/pre-push
  scripts/git-start.sh scripts/configure-github-governance.sh docs/development/git-workflow.md
)
log CHECK "Checking Git governance files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing file: $path"; done
for path in .githooks/pre-commit .githooks/commit-msg .githooks/pre-push scripts/git-start.sh scripts/configure-github-governance.sh; do [[ -x "$repo_root/$path" ]] || die "File is not executable: $path"; done

if [[ "${NEXALI_CI:-0}" == "1" || "${CI:-}" == "true" ]]; then
  log OK "CI mode detected; developer-local Git config and local protected-branch presence checks are skipped."
else
  hooks_path="$(git -C "$repo_root" config --local --get core.hooksPath || true)"
  [[ "$hooks_path" == ".githooks" ]] || die "core.hooksPath must be .githooks (current: ${hooks_path:-unset})."
  [[ "$(git -C "$repo_root" config --local --get commit.gpgsign || true)" == "true" ]] || die "commit.gpgsign must be true locally."
  [[ "$(git -C "$repo_root" config --local --get tag.gpgSign || true)" == "true" ]] || die "tag.gpgSign must be true locally."
  [[ "$(git -C "$repo_root" config --local --get pull.ff || true)" == "only" ]] || die "pull.ff must be only locally."

  for branch in main testing develop; do
    git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" || die "Missing protected local branch: $branch"
  done
fi

# shellcheck source=/dev/null
source "$repo_root/.githooks/lib/policy.sh"
for good in feature/drive-upload fix/sync-conflict refactor/api-routing build/git-governance; do
  nexali_is_valid_topic_branch "$good" || die "Branch regex unexpectedly rejects valid sample: $good"
done
for bad in feature/foo/bar Feature/test main agent/feature/test feature/Foo; do
  if nexali_is_valid_topic_branch "$bad"; then die "Branch regex unexpectedly accepts invalid sample: $bad"; fi
done
log OK "Local Gitflow governance is configured and valid."

if [[ "${NEXALI_CI:-0}" == "1" || "${CI:-}" == "true" ]]; then
  log OK "Versioned Git governance policy is valid for CI execution."
elif git -C "$repo_root" remote get-url origin >/dev/null 2>&1; then
  log WARN "An origin remote exists. Run ./scripts/configure-github-governance.sh to validate/apply server-side protections if it is hosted on GitHub."
else
  log WARN "No origin remote is configured yet. Server-side protection remains pending until a GitHub remote exists."
fi
