#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages="$repo_root/Directory.Packages.props"
baseline="$repo_root/eng/package-baseline.tsv"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == WARN ]]&&c="$yellow"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][BUILD]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(global.json Directory.Build.props Directory.Build.targets Directory.Packages.props NuGet.config eng/package-baseline.tsv)
log CHECK "Checking build/package baseline files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing file: $path"; done
command -v python3 >/dev/null 2>&1 || die "python3 is required for build baseline validation."
command -v dotnet >/dev/null 2>&1 || die ".NET SDK is required for build baseline validation."

python3 - "$repo_root/global.json" <<'PY'
import json, sys
p=sys.argv[1]
with open(p, encoding='utf-8') as f: data=json.load(f)
sdk=data.get('sdk', {})
assert sdk.get('version') == '10.0.112', 'global.json must pin SDK baseline 10.0.112'
assert sdk.get('rollForward') == 'latestPatch', 'global.json must use latestPatch'
assert sdk.get('allowPrerelease') is False, 'global.json must disable prerelease SDKs'
assert data.get('test', {}).get('runner') == 'Microsoft.Testing.Platform', 'global.json must select Microsoft.Testing.Platform'
PY
selected_sdk="$(cd "$repo_root" && dotnet --version 2>/dev/null || true)"
python3 - "$selected_sdk" <<'PY'
import re, sys
v=sys.argv[1]
if not re.fullmatch(r'10\.0\.1\d\d', v):
    raise SystemExit(f"Selected SDK must be from the 10.0.1xx feature band, found {v!r}")
if tuple(map(int,v.split('.'))) < (10,0,112):
    raise SystemExit(f"Selected SDK must be >= 10.0.112, found {v}")
PY
log OK "global.json selects supported SDK $selected_sdk and Microsoft Testing Platform."

grep -Fq '<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>' "$packages" || die "Central Package Management is not enabled."
grep -Fq '<CentralPackageVersionOverrideEnabled>false</CentralPackageVersionOverrideEnabled>' "$packages" || die "Package version overrides must be disabled."

python3 - "$packages" "$baseline" <<'PY'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
packages_path, baseline_path = map(Path, sys.argv[1:])
root=ET.parse(packages_path).getroot()
actual={x.attrib['Include']:x.attrib['Version'] for x in root.findall('.//PackageVersion')}
expected={}
for line in baseline_path.read_text(encoding='utf-8').splitlines():
    if not line.strip() or line.lstrip().startswith('#'): continue
    pkg, ver, scope, status=line.split('\t')
    expected[pkg]=ver
if actual != expected:
    missing=sorted(set(expected)-set(actual)); extra=sorted(set(actual)-set(expected))
    mismatched=sorted(k for k in expected.keys() & actual.keys() if expected[k]!=actual[k])
    raise SystemExit(f'Package baseline mismatch. missing={missing} extra={extra} mismatched={mismatched}')
PY
log OK "Central package registry matches eng/package-baseline.tsv."

if grep -R --include='*.csproj' -En '<PackageReference[^>]+(Version|VersionOverride)=' "$repo_root/src" "$repo_root/tests" >/dev/null 2>&1; then
  grep -R --include='*.csproj' -En '<PackageReference[^>]+(Version|VersionOverride)=' "$repo_root/src" "$repo_root/tests" >&2 || true
  die "Project-level PackageReference versions are forbidden; use Directory.Packages.props."
fi
log OK "No project-level package version overrides were found."

web="$repo_root/src/Clients/Web/Nexali.Web/Nexali.Web.csproj"
app="$repo_root/src/Clients/Avalonia/Nexali.App/Nexali.App.csproj"
desktop="$repo_root/src/Clients/Avalonia/Nexali.Desktop/Nexali.Desktop.csproj"
android="$repo_root/src/Clients/Avalonia/Nexali.Mobile.Android/Nexali.Mobile.Android.csproj"
ios="$repo_root/src/Clients/Avalonia/Nexali.Mobile.iOS/Nexali.Mobile.iOS.csproj"
for spec in \
  "$web|Microsoft.AspNetCore.Components.WebAssembly" \
  "$app|Avalonia" \
  "$app|Avalonia.Themes.Fluent" \
  "$app|CommunityToolkit.Mvvm" \
  "$desktop|Avalonia.Desktop"; do
  file="${spec%%|*}"; pkg="${spec#*|}"
  grep -Fq "<PackageReference Include=\"$pkg\"" "$file" || die "Missing active package '$pkg' in ${file#$repo_root/}."
done
if grep -Fq '<PackageReference' "$android" || grep -Fq '<PackageReference' "$ios"; then
  die "Android/iOS package activation is deferred; mobile shells must remain package-free in Phase 1.5."
fi
log OK "Web/Avalonia active and mobile deferred package boundaries are valid."

mapfile -t test_projects < <(find "$repo_root/tests" -mindepth 2 -maxdepth 2 -name '*.csproj' -type f | sort)
[[ "${#test_projects[@]}" -eq 11 ]] || die "Expected 11 test projects, found ${#test_projects[@]}."
for project in "${test_projects[@]}"; do
  grep -Fq '<OutputType>Exe</OutputType>' "$project" || die "xUnit v3 test project must be executable: ${project#$repo_root/}"
  grep -Fq '<IsTestProject>true</IsTestProject>' "$project" || die "Missing IsTestProject=true: ${project#$repo_root/}"
  grep -Fq '<IsPackable>false</IsPackable>' "$project" || die "Tests must be non-packable: ${project#$repo_root/}"
  for pkg in Microsoft.NET.Test.Sdk xunit.v3 xunit.runner.visualstudio; do
    grep -Fq "<PackageReference Include=\"$pkg\"" "$project" || die "Missing $pkg: ${project#$repo_root/}"
  done
done
log OK "All 11 test projects use the executable xUnit v3 baseline."

grep -Fq '<LangVersion>latest</LangVersion>' "$repo_root/Directory.Build.props" || die "LangVersion baseline missing."
grep -Fq '<TreatWarningsAsErrors>true</TreatWarningsAsErrors>' "$repo_root/Directory.Build.props" || die "Warnings-as-errors baseline missing."
grep -Fq '<Deterministic>true</Deterministic>' "$repo_root/Directory.Build.props" || die "Deterministic build baseline missing."
grep -Fq '<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>' "$repo_root/Directory.Build.props" || die "Code-style enforcement baseline missing."
grep -Fq '<AnalysisLevel>10.0-recommended</AnalysisLevel>' "$repo_root/Directory.Build.props" || die "Pinned analyzer rule set missing."
grep -Fq '<AnalysisLevelSecurity>10.0-all</AnalysisLevelSecurity>' "$repo_root/Directory.Build.props" || die "Security analyzer rule set missing."
log OK "Repository-wide build properties and Phase 1.6 analyzer policy are valid."

source_count="$(grep -Ec '<add key="nuget.org" value="https://api.nuget.org/v3/index.json"' "$repo_root/NuGet.config" || true)"
[[ "$source_count" -eq 1 ]] || die "NuGet.config must define the canonical nuget.org source exactly once."
log OK "NuGet source policy is valid."
log OK "Nexali Phase 1.5 build/package baseline validation passed."
