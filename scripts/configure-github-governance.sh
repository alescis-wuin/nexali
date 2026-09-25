#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap=0
if [[ "${1:-}" == "--bootstrap" ]]; then bootstrap=1; shift; fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--bootstrap]" >&2; exit 2; }

log(){ printf '[NEXALI][GITHUB-GOVERNANCE][%s] %s\n' "$1" "$2"; }
command -v gh >/dev/null 2>&1 || { log ERROR "GitHub CLI (gh) is required." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { log ERROR "gh is not authenticated. Run: gh auth login" >&2; exit 1; }
origin="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"
[[ -n "$origin" ]] || { log ERROR "No origin remote is configured." >&2; exit 1; }
case "$origin" in
  git@github.com:*|ssh://git@github.com/*|https://github.com/*) ;;
  *) log ERROR "origin is not a github.com repository: $origin" >&2; exit 1 ;;
esac

repo="$(cd "$repo_root" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
[[ -n "$repo" ]] || { log ERROR "Unable to resolve GitHub repository." >&2; exit 1; }
log INFO "Repository: $repo"

if [[ "$bootstrap" -eq 1 ]]; then
  baseline_sha="$(git -C "$repo_root" rev-parse main)"
  for branch in testing develop; do
    git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" || { log ERROR "Missing local branch: $branch" >&2; exit 1; }
    branch_sha="$(git -C "$repo_root" rev-parse "$branch")"
    [[ "$branch_sha" == "$baseline_sha" ]] || {
      log ERROR "Local protected branches are not aligned. Integrate Phase 1.3 into main before remote bootstrap." >&2
      exit 1
    }
  done
  log OK "main, testing and develop are aligned on the Phase 1.3 bootstrap baseline."
fi

for branch in main testing develop; do
  git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" || { log ERROR "Missing local branch: $branch" >&2; exit 1; }
  local_sha="$(git -C "$repo_root" rev-parse "$branch")"
  remote_sha="$(git -C "$repo_root" ls-remote --heads origin "$branch" | awk '{print $1}')"
  if [[ -z "$remote_sha" ]]; then
    if [[ "$bootstrap" -ne 1 ]]; then
      log ERROR "Remote branch '$branch' does not exist. Re-run with --bootstrap for the one-time initial push before protections are installed." >&2
      exit 1
    fi
    log INFO "Bootstrapping remote branch '$branch' once before enabling protection."
    git -C "$repo_root" push --no-verify -u origin "$branch"
  elif [[ "$remote_sha" != "$local_sha" ]]; then
    log ERROR "Remote '$branch' differs from local '$branch'. Refusing to rewrite it during governance setup." >&2
    exit 1
  fi
done

for branch in main testing develop; do
  log INFO "Applying branch protection to '$branch'."
  gh api --method PUT "repos/$repo/branches/$branch/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "PR source chain",
      "Repository gate"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
  gh api --method POST "repos/$repo/branches/$branch/protection/required_signatures" >/dev/null
  protection="$(gh api "repos/$repo/branches/$branch/protection" --jq '[.enforce_admins.enabled,.allow_force_pushes.enabled,.allow_deletions.enabled,.required_linear_history.enabled,.required_signatures.enabled,.required_status_checks.strict, (.required_status_checks.contexts | sort | join(","))] | @tsv')"
  IFS=$'\t' read -r admins force deletes linear signatures strict_checks check_contexts <<<"$protection"
  [[ "$admins" == true && "$force" == false && "$deletes" == false && "$linear" == true && "$signatures" == true && "$strict_checks" == true && "$check_contexts" == "PR source chain,Repository gate" ]] || {
    log ERROR "Protection verification failed for '$branch'." >&2; exit 1;
  }
  log OK "'$branch' requires PR-based updates, signed commits, strict CI checks, linear history and blocks force pushes/deletion."
done

log OK "The PR source chain is enforced by the required 'PR source chain' CI check."
log OK "GitHub server-side governance configured successfully."
