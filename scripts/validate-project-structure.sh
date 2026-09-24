#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/eng/projects.tsv"
refs_manifest="$repo_root/eng/project-references.tsv"
solution="$repo_root/Nexali.sln"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == WARN ]]&&c="$yellow"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][PROJECTS]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

[[ -f "$manifest" ]] || die "Missing eng/projects.tsv."
[[ -f "$refs_manifest" ]] || die "Missing eng/project-references.tsv."
[[ -f "$solution" ]] || die "Missing Nexali.sln."
command -v dotnet >/dev/null 2>&1 || die ".NET SDK is required for Phase 1.4 validation."
sdk="$(dotnet --version 2>/dev/null || true)"
[[ "$sdk" == 10.* ]] || die "Phase 1.4 requires a .NET 10 SDK (found: ${sdk:-unknown})."

mapfile -t rows < <(grep -Ev '^[[:space:]]*(#|$)' "$manifest")
[[ "${#rows[@]}" -eq 40 ]] || die "Expected 40 projects in eng/projects.tsv, found ${#rows[@]}."
log OK "Canonical project catalog contains 40 projects."

# Expected role counts protect against accidental catalog drift.
declare -A expected=(
  [server-host]=1 [module]=7 [contracts]=7 [future-module]=4 [library]=4
  [web-client-shell]=1 [avalonia-shared-shell]=1 [platform-head-shell]=3
  [tool]=1 [test-shell]=11
)
for role in "${!expected[@]}"; do
  count="$(awk -F '\t' -v r="$role" '$1==r{c++} END{print c+0}' "$manifest")"
  [[ "$count" -eq "${expected[$role]}" ]] || die "Role '$role' expected ${expected[$role]} project(s), found $count."
done
log OK "Project role counts are valid."

while IFS=$'\t' read -r role folder project; do
  [[ -z "$role" || "$role" == \#* ]] && continue
  [[ -f "$repo_root/$project" ]] || die "Missing project: $project"
  grep -Fq '<TargetFramework>net10.0</TargetFramework>' "$repo_root/$project" || die "Project does not target net10.0: $project"
done < "$manifest"

if grep -R --include='*.csproj' -n '<PackageReference' "$repo_root/src" "$repo_root/tests" >/dev/null 2>&1; then
  die "External PackageReference found during Phase 1.4; package selection belongs to Phase 1.5."
fi
log OK "All project shells target net10.0 and contain no external PackageReference."

# Validate canonical ProjectReference edges.
while IFS=$'\t' read -r source target; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ -f "$repo_root/$source" ]] || die "Reference source missing: $source"
  [[ -f "$repo_root/$target" ]] || die "Reference target missing: $target"
  rel="$(realpath --relative-to="$(dirname "$repo_root/$source")" "$repo_root/$target")"
  grep -Fq "ProjectReference Include=\"$rel\"" "$repo_root/$source" || die "Missing ProjectReference: $source -> $target"
done < "$refs_manifest"
log OK "Canonical project-reference graph is present."

log CHECK "Validating solution membership with .NET SDK $sdk."
solution_list="$(DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 dotnet sln "$solution" list | tr '\\\\' '/')"
while IFS=$'\t' read -r role folder project; do
  [[ -z "$role" || "$role" == \#* ]] && continue
  grep -Fqx "$project" <<<"$solution_list" || die "Project is missing from Nexali.sln: $project"
done < "$manifest"
listed_count="$(grep -Ec '\.csproj$' <<<"$solution_list" || true)"
[[ "$listed_count" -eq 40 ]] || die "Expected 40 .csproj entries in Nexali.sln, found $listed_count."
log OK "Nexali.sln contains exactly the 40 canonical projects."

for top in src/Server src/Modules src/Libraries src/Clients/Web src/Clients/Avalonia src/Tools tests; do
  name="${top##*/}"
  grep -Fq "= \"$name\", \"$name\"" "$solution" || die "Solution folder '$top' was not materialized as expected."
done
log OK "Canonical top-level solution folders are materialized."

log CHECK "Restoring project shells."
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 dotnet restore "$solution" --nologo >/dev/null
log CHECK "Building project shells."
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 dotnet build "$solution" --no-restore --nologo >/dev/null
log OK "Restore and build succeeded."
log OK "Nexali Phase 1.4 project structure validation passed."
