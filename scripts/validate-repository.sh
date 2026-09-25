#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'; else reset=''; bold=''; cyan=''; green=''; red=''; fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][REPOSITORY]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }
required_dirs=(.github docs/adr docs/architecture docs/development docs/deployment docs/protocols docs/security docs/testing deploy/compose eng samples scripts src tests)
required_files=(.editorconfig .gitattributes .gitignore CONTRIBUTING.md LICENSE-PENDING.md README.md SECURITY.md global.json Directory.Build.props Directory.Build.targets Directory.Packages.props NuGet.config)
log CHECK "Checking repository directories."
for p in "${required_dirs[@]}"; do [[ -d "$repo_root/$p" ]] || die "Missing directory: $p"; done
log CHECK "Checking repository baseline files."
for p in "${required_files[@]}"; do [[ -f "$repo_root/$p" ]] || die "Missing file: $p"; done
if [[ -x "$repo_root/scripts/validate-solution.sh" ]]; then log CHECK "Checking solution baseline."; "$repo_root/scripts/validate-solution.sh"; fi
if [[ -x "$repo_root/scripts/validate-git-governance.sh" ]]; then log CHECK "Checking Git governance baseline."; "$repo_root/scripts/validate-git-governance.sh"; fi
if [[ -f "$repo_root/eng/projects.tsv" ]]; then
  [[ -x "$repo_root/scripts/validate-project-structure.sh" ]] || die "Project catalog exists but project validator is missing/not executable."
  log CHECK "Checking project structure baseline."
  "$repo_root/scripts/validate-project-structure.sh"
fi
[[ -x "$repo_root/scripts/validate-build-baseline.sh" ]] || die "Build/package baseline validator is missing/not executable."
log CHECK "Checking build/package baseline."
"$repo_root/scripts/validate-build-baseline.sh"
[[ -x "$repo_root/scripts/validate-code-quality.sh" ]] || die "Formatting/analyzer baseline validator is missing/not executable."
log CHECK "Checking formatting/analyzer baseline."
"$repo_root/scripts/validate-code-quality.sh"
[[ -x "$repo_root/scripts/validate-architecture-tests.sh" ]] || die "Architecture-test baseline validator is missing/not executable."
log CHECK "Checking architecture-test baseline."
"$repo_root/scripts/validate-architecture-tests.sh"
log OK "Repository baseline validation passed."
