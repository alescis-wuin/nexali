#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
editorconfig="$repo_root/.editorconfig"
props="$repo_root/Directory.Build.props"
targets="$repo_root/Directory.Build.targets"
baseline="$repo_root/eng/code-quality-baseline.tsv"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == WARN ]]&&c="$yellow"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][QUALITY]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(.editorconfig Directory.Build.props Directory.Build.targets eng/code-quality-baseline.tsv scripts/format.sh)
log CHECK "Checking formatting/analyzer baseline files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing file: $path"; done
[[ -x "$repo_root/scripts/format.sh" ]] || die "scripts/format.sh is not executable."
command -v dotnet >/dev/null 2>&1 || die ".NET SDK is required for code-quality validation."
command -v python3 >/dev/null 2>&1 || die "python3 is required for code-quality validation."

for expected in \
  '<TreatWarningsAsErrors>true</TreatWarningsAsErrors>' \
  '<CodeAnalysisTreatWarningsAsErrors>true</CodeAnalysisTreatWarningsAsErrors>' \
  '<AnalysisLevel>10.0-recommended</AnalysisLevel>' \
  '<AnalysisLevelSecurity>10.0-all</AnalysisLevelSecurity>' \
  '<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>'; do
  grep -Fq "$expected" "$props" || die "Missing code-quality property in Directory.Build.props: $expected"
done
log OK "MSBuild analyzer and code-style policy is enabled."

for expected in \
  "'\$(TreatWarningsAsErrors)' != 'true'" \
  "'\$(CodeAnalysisTreatWarningsAsErrors)' != 'true'" \
  "'\$(AnalysisLevel)' != '10.0-recommended'" \
  "'\$(AnalysisLevelSecurity)' != '10.0-all'" \
  "'\$(EnforceCodeStyleInBuild)' != 'true'"; do
  grep -Fq "$expected" "$targets" || die "Directory.Build.targets does not guard policy: $expected"
done
log OK "MSBuild policy overrides are guarded at compile time."

for expected in \
  'charset = utf-8' \
  'end_of_line = lf' \
  'indent_size = 4' \
  'dotnet_style_require_accessibility_modifiers = for_non_interface_members:warning' \
  'csharp_style_prefer_braces = true:warning' \
  'dotnet_diagnostic.IDE0005.severity = warning' \
  'dotnet_diagnostic.IDE0055.severity = warning' \
  'dotnet_diagnostic.IDE0060.severity = warning' \
  'dotnet_code_quality_unused_parameters = non_public'; do
  grep -Fq "$expected" "$editorconfig" || die "Missing EditorConfig rule: $expected"
done
log OK "EditorConfig formatting, naming, and build-visible style rules are present."

# Prevent project-level escape hatches from weakening the repository baseline.
if grep -R --include='*.csproj' -En '<(AnalysisLevel|AnalysisLevelSecurity|EnforceCodeStyleInBuild|TreatWarningsAsErrors|CodeAnalysisTreatWarningsAsErrors|NoWarn|WarningsNotAsErrors)>' "$repo_root/src" "$repo_root/tests" >/dev/null 2>&1; then
  grep -R --include='*.csproj' -En '<(AnalysisLevel|AnalysisLevelSecurity|EnforceCodeStyleInBuild|TreatWarningsAsErrors|CodeAnalysisTreatWarningsAsErrors|NoWarn|WarningsNotAsErrors)>' "$repo_root/src" "$repo_root/tests" >&2 || true
  die "Project-level analyzer/warning overrides are forbidden. Configure repository policy centrally."
fi
log OK "No project-level analyzer or warning escape hatches were found."

python3 - "$baseline" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
rows=[]
for raw in p.read_text(encoding='utf-8').splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    cols=raw.split('\t')
    if len(cols)!=3:
        raise SystemExit(f'Invalid code-quality baseline row: {raw!r}')
    rows.append(tuple(cols))
required={
 ('msbuild','AnalysisLevel','10.0-recommended'),
 ('msbuild','AnalysisLevelSecurity','10.0-all'),
 ('msbuild','TreatWarningsAsErrors','true'),
 ('msbuild','CodeAnalysisTreatWarningsAsErrors','true'),
 ('msbuild','EnforceCodeStyleInBuild','true'),
 ('format','check','whitespace'),
 ('format','style-fix-severity','warn'),
 ('format','verify-no-changes','true'),
 ('editorconfig','IDE0060','warning'),
}
missing=required-set(rows)
if missing:
    raise SystemExit(f'Missing code-quality baseline entries: {sorted(missing)!r}')
PY
log OK "Machine-readable code-quality baseline is valid."

log CHECK "Verifying deterministic repository formatting."
cd "$repo_root"
./scripts/format.sh --check >/dev/null \
  || die "Whitespace formatting drift detected. Run ./scripts/format.sh and review the diff."
log OK "dotnet format whitespace --verify-no-changes passed."

log CHECK "Building with analyzers and code-style enforcement enabled."
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  dotnet build Nexali.sln --no-restore --nologo -p:RunAnalyzers=true >/dev/null \
  || die "Analyzer-enforced build failed."
log OK "Analyzer-enforced build passed."
log OK "Nexali Phase 1.6 formatting/analyzer baseline validation passed."
