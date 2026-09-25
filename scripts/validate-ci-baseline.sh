#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ci.yml"
baseline="$repo_root/eng/ci-baseline.tsv"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][CI]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(.github/workflows/ci.yml eng/ci-baseline.tsv scripts/validate-pr-source.sh scripts/configure-github-governance.sh)
log CHECK "Checking Phase 1.8 CI baseline files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing CI baseline file: $path"; done
[[ -x "$repo_root/scripts/validate-pr-source.sh" ]] || die "scripts/validate-pr-source.sh is not executable."
command -v python3 >/dev/null 2>&1 || die "python3 is required for CI baseline validation."

for script in \
  scripts/validate-pr-source.sh \
  scripts/validate-ci-baseline.sh \
  scripts/validate-git-governance.sh \
  scripts/configure-github-governance.sh \
  scripts/validate-repository.sh; do
  bash -n "$repo_root/$script" || die "Bash syntax validation failed: $script"
done
log OK "CI/governance Bash syntax is valid."

checkout_sha='3d3c42e5aac5ba805825da76410c181273ba90b1'
setup_dotnet_sha='a98b56852c35b8e3190ac28c8c2271da59106c68'

for token in \
  'name: CI' \
  'pull_request:' \
  'push:' \
  'workflow_dispatch:' \
  'contents: read' \
  'name: PR source chain' \
  'name: Repository gate' \
  'runs-on: ubuntu-24.04' \
  'timeout-minutes: 20' \
  'NEXALI_CI: "1"' \
  'global-json-file: global.json' \
  './scripts/validate-pr-source.sh "$NEXALI_PR_SOURCE" "$NEXALI_PR_TARGET"' \
  'run: ./scripts/validate-repository.sh'; do
  grep -Fq "$token" "$workflow" || die "Missing workflow requirement: $token"
done

for branch in develop testing main; do
  grep -Eq "^[[:space:]]+- ${branch}$" "$workflow" || die "CI workflow does not target protected branch: $branch"
done

grep -Fq "actions/checkout@$checkout_sha # v7.0.1" "$workflow" \
  || die "actions/checkout is not pinned to the approved v7.0.1 SHA."
grep -Fq "actions/setup-dotnet@$setup_dotnet_sha # v6.0.0" "$workflow" \
  || die "actions/setup-dotnet is not pinned to the approved v6.0.0 SHA."

if grep -Eq 'uses:[[:space:]]+[^[:space:]]+@(main|master|v[0-9]+([.][0-9]+){0,2})([[:space:]#]|$)' "$workflow"; then
  die "Mutable GitHub Action tags/branches are forbidden; pin actions by full commit SHA."
fi
if grep -Fq 'pull_request_target:' "$workflow"; then
  die "Phase 1.8 CI must not use pull_request_target."
fi
if grep -Eq 'permissions:[[:space:]]+(write-all|read-all)' "$workflow" || grep -Eq '^[[:space:]]+[a-z-]+:[[:space:]]+write([[:space:]#]|$)' "$workflow"; then
  die "CI workflow requests write permissions. Phase 1.8 must remain read-only."
fi
if grep -Fq 'persist-credentials: true' "$workflow"; then
  die "Checkout credentials must not persist in Phase 1.8 CI."
fi

python3 - "$baseline" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
for raw in p.read_text(encoding='utf-8').splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    cols=raw.split('\t')
    if len(cols)!=5:
        raise SystemExit(f'Invalid CI baseline row: {raw!r}')
    rows.append(tuple(cols))
required={
    ('action','actions/checkout','v7.0.1','3d3c42e5aac5ba805825da76410c181273ba90b1','active'),
    ('action','actions/setup-dotnet','v6.0.0','a98b56852c35b8e3190ac28c8c2271da59106c68','active'),
    ('runner','github-hosted','ubuntu-24.04','ubuntu-24.04','active'),
    ('check','pr-source-chain','PR source chain','pull_request','required'),
    ('check','repository-gate','Repository gate','pull_request+push','required'),
}
missing=required-set(rows)
if missing:
    raise SystemExit(f'Missing CI baseline entries: {sorted(missing)!r}')
PY
log OK "Machine-readable CI baseline is valid."

"$repo_root/scripts/validate-pr-source.sh" --self-test >/dev/null
log OK "PR source-chain policy self-tests passed."

for token in \
  '"strict": true' \
  '"PR source chain"' \
  '"Repository gate"'; do
  grep -Fq "$token" "$repo_root/scripts/configure-github-governance.sh" \
    || die "GitHub governance script is not prepared to require CI check: $token"
done
log OK "GitHub governance is prepared for strict required CI checks."
log OK "Nexali Phase 1.8 CI baseline validation passed."
