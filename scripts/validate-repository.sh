#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; red=''
fi

log() {
  local level="$1" message="$2" color="$cyan"
  [[ "$level" == "OK" ]] && color="$green"
  [[ "$level" == "ERROR" ]] && color="$red"
  printf '%b[NEXALI][REPOSITORY]%b %b[%s]%b %s\n' "$bold" "$reset" "$color" "$level" "$reset" "$message"
}

die() {
  log ERROR "$1" >&2
  exit 1
}

required_files=(
  .editorconfig .gitattributes .gitignore README.md CONTRIBUTING.md SECURITY.md LICENSE-PENDING.md
  .github/PULL_REQUEST_TEMPLATE.md
  .github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/feature.yml .github/ISSUE_TEMPLATE/config.yml
  docs/architecture/README.md docs/architecture/principles.md docs/architecture/modules.md docs/architecture/dependency-rules.md
  docs/security/README.md docs/security/threat-model.md docs/security/e2ee.md docs/security/security-spikes.md
  docs/development/README.md docs/development/solution.md docs/deployment/README.md docs/protocols/README.md docs/testing/README.md docs/adr/README.md
  Nexali.sln eng/solution-folders.txt scripts/validate-solution.sh
)
required_dirs=(
  .github/ISSUE_TEMPLATE docs/adr docs/architecture docs/development docs/deployment docs/protocols docs/security docs/testing
  deploy/compose eng samples scripts src tests
)

log CHECK "Checking repository directories."
for path in "${required_dirs[@]}"; do
  [[ -d "$repo_root/$path" ]] || die "Missing directory: $path"
done

log CHECK "Checking repository baseline files."
for path in "${required_files[@]}"; do
  [[ -f "$repo_root/$path" ]] || die "Missing file: $path"
done

adr_count="$(find "$repo_root/docs/adr" -maxdepth 1 -type f -name 'ADR-*.md' | wc -l | tr -d ' ')"
[[ "$adr_count" -eq 12 ]] || die "Expected 12 consolidated ADR files, found $adr_count."

if find "$repo_root" -maxdepth 4 -type f \( -name '.env' -o -name '*.secrets' \) -print -quit | grep -q .; then
  die "Potential local secret file detected."
fi

log CHECK "Checking solution baseline."
"$repo_root/scripts/validate-solution.sh"

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_root" diff --check
  git -C "$repo_root" diff --cached --check
fi

log OK "Repository baseline validation passed."
