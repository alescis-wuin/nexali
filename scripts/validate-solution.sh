#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
solution="$repo_root/Nexali.sln"
layout="$repo_root/eng/solution-folders.txt"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi

log() {
  local level="$1" message="$2" color="$cyan"
  [[ "$level" == "OK" ]] && color="$green"
  [[ "$level" == "WARN" ]] && color="$yellow"
  [[ "$level" == "ERROR" ]] && color="$red"
  printf '%b[NEXALI][SOLUTION]%b %b[%s]%b %s\n' "$bold" "$reset" "$color" "$level" "$reset" "$message"
}

die() {
  log ERROR "$1" >&2
  exit 1
}

log CHECK "Checking canonical solution files."
[[ -f "$solution" ]] || die "Missing solution: Nexali.sln"
[[ -f "$layout" ]] || die "Missing solution-folder manifest: eng/solution-folders.txt"

if find "$repo_root" -maxdepth 1 -type f -name '*.slnx' -print -quit | grep -q .; then
  die "Unexpected .slnx file found at repository root; Nexali.sln is the canonical solution."
fi

first_line="$(head -n 1 "$solution")"
[[ "$first_line" == 'Microsoft Visual Studio Solution File, Format Version 12.00' ]] || die "Nexali.sln has an unexpected format header."

grep -Fqx '# Visual Studio Version 17' "$solution" || die "Nexali.sln is missing the Visual Studio 17 marker."
grep -Fq 'GlobalSection(SolutionConfigurationPlatforms) = preSolution' "$solution" || die "Nexali.sln is missing solution configurations."
grep -Fq 'Debug|Any CPU = Debug|Any CPU' "$solution" || die "Nexali.sln is missing Debug|Any CPU."
grep -Fq 'Release|Any CPU = Release|Any CPU' "$solution" || die "Nexali.sln is missing Release|Any CPU."
grep -Fq 'GlobalSection(SolutionProperties) = preSolution' "$solution" || die "Nexali.sln is missing SolutionProperties."
grep -Fq 'HideSolutionNode = FALSE' "$solution" || die "Nexali.sln must keep the solution node visible."
log OK "SLN structure and configurations are valid."

expected=(
  'src/Server'
  'src/Modules'
  'src/Libraries'
  'src/Clients/Web'
  'src/Clients/Avalonia'
  'src/Tools'
  'tests'
)
mapfile -t actual < <(grep -Ev '^[[:space:]]*(#|$)' "$layout")
[[ "${#actual[@]}" -eq "${#expected[@]}" ]] || die "Unexpected number of solution-folder entries in eng/solution-folders.txt."
for i in "${!expected[@]}"; do
  [[ "${actual[$i]}" == "${expected[$i]}" ]] || die "Solution-folder manifest mismatch at entry $((i + 1)): expected '${expected[$i]}', found '${actual[$i]}'."
done
log OK "Solution-folder plan is pinned and valid."

if command -v dotnet >/dev/null 2>&1; then
  sdk_version="$(dotnet --version 2>/dev/null || true)"
  log CHECK "Validating Nexali.sln with .NET SDK ${sdk_version:-unknown}."
  if ! dotnet sln "$solution" list >/dev/null; then
    die "The installed .NET SDK could not parse Nexali.sln."
  fi
  log OK ".NET CLI accepts Nexali.sln."
else
  log WARN ".NET SDK not found; CLI parsing check skipped. SDK pinning is introduced in Phase 1.4."
fi

log OK "Nexali solution baseline validation passed."
