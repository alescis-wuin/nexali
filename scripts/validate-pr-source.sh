#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$repo_root/eng/git-policy.conf"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][PR-POLICY]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; return 1; }

usage(){ printf 'Usage: %s <source-branch> <target-branch> | --self-test\n' "$0"; }

validate_pair(){
  local source="$1" target="$2"
  case "$target" in
    develop)
      [[ "$source" =~ $NEXALI_BRANCH_NAME_REGEX ]] \
        || die "Pull requests to develop must come from a valid <type>/<kebab-name> topic branch (found: $source)."
      ;;
    testing)
      [[ "$source" == "develop" ]] \
        || die "Pull requests to testing must come from develop (found: $source)."
      ;;
    main)
      [[ "$source" == "testing" ]] \
        || die "Pull requests to main must come from testing (found: $source)."
      ;;
    *)
      die "Unsupported protected target branch: $target"
      ;;
  esac
}

if [[ "${1:-}" == "--self-test" ]]; then
  pass(){ validate_pair "$1" "$2" >/dev/null || { log ERROR "Expected valid pair rejected: $1 -> $2"; exit 1; }; }
  fail(){ if validate_pair "$1" "$2" >/dev/null 2>&1; then log ERROR "Expected invalid pair accepted: $1 -> $2"; exit 1; fi; }

  pass feature/drive-upload develop
  pass fix/sync-conflict develop
  pass ci/initial-ci develop
  pass develop testing
  pass testing main

  fail develop develop
  fail testing develop
  fail main develop
  fail feature/drive-upload testing
  fail develop main
  fail testing testing
  fail Feature/invalid develop
  fail feature/foo/bar develop
  fail feature/Invalid develop
  fail feature/foo unknown

  log OK "PR source-chain self-tests passed."
  exit 0
fi

[[ $# -eq 2 ]] || { usage >&2; exit 2; }
validate_pair "$1" "$2"
log OK "Allowed promotion: $1 -> $2"
