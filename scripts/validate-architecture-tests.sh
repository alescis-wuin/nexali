#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/tests/Nexali.Architecture.Tests/Nexali.Architecture.Tests.csproj"
rules="$repo_root/eng/architecture-rules.tsv"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == WARN ]]&&c="$yellow"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][ARCHITECTURE]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(
  eng/architecture-rules.tsv
  tests/Nexali.Architecture.Tests/Nexali.Architecture.Tests.csproj
  tests/Nexali.Architecture.Tests/RepositoryPaths.cs
  tests/Nexali.Architecture.Tests/ProjectDependencyGraph.cs
  tests/Nexali.Architecture.Tests/ProjectDependencyTests.cs
  tests/Nexali.Architecture.Tests/ArchitectureAssemblyCatalog.cs
  tests/Nexali.Architecture.Tests/ArchUnitDependencyTests.cs
)
log CHECK "Checking architecture-test baseline files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing file: $path"; done
command -v dotnet >/dev/null 2>&1 || die ".NET SDK is required for architecture-test validation."
command -v python3 >/dev/null 2>&1 || die "python3 is required for architecture-test validation."

grep -Fq '<PackageVersion Include="TngTech.ArchUnitNET.xUnitV3" Version="0.13.4" />' "$repo_root/Directory.Packages.props" \
  || die "TngTech.ArchUnitNET.xUnitV3 0.13.4 is not pinned centrally."
grep -Fq $'TngTech.ArchUnitNET.xUnitV3\t0.13.4\tarchitecture-tests\tactive' "$repo_root/eng/package-baseline.tsv" \
  || die "Architecture-test package is missing from eng/package-baseline.tsv."
grep -Fq '<PackageReference Include="TngTech.ArchUnitNET.xUnitV3">' "$project" \
  || die "Architecture test project does not reference TngTech.ArchUnitNET.xUnitV3."
log OK "ArchUnitNET xUnit v3 dependency is centrally pinned and active."

python3 - "$rules" "$repo_root/eng/projects.tsv" "$project" "$repo_root" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

rules_path, projects_path, architecture_project_path, root_path = map(Path, sys.argv[1:])
rows=[]
for raw in rules_path.read_text(encoding='utf-8').splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    cols=raw.split('\t')
    if len(cols)!=4:
        raise SystemExit(f'Invalid architecture rule row: {raw!r}')
    rows.append(cols)
expected_ids={f'ARCH{i:03d}' for i in range(1,10)}
actual_ids={row[0] for row in rows}
if actual_ids != expected_ids or len(rows) != len(expected_ids):
    raise SystemExit(f'Architecture rule catalog mismatch: {sorted(actual_ids)!r}')

production=[]
for raw in projects_path.read_text(encoding='utf-8').splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    role, _, project=raw.split('\t')
    if not project.startswith('tests/'):
        production.append(project)
if len(production) != 29:
    raise SystemExit(f'Expected 29 production projects, found {len(production)}')

tree=ET.parse(architecture_project_path)
base=architecture_project_path.parent
actual=set()
for item in tree.findall('.//ProjectReference'):
    include=item.attrib.get('Include')
    if not include:
        continue
    target=(base / include).resolve()
    actual.add(target.relative_to(root_path.resolve()).as_posix())
missing=sorted(set(production)-actual)
if missing:
    raise SystemExit(f'Architecture test project does not reference every production project: {missing!r}')
PY
log OK "Architecture rule catalog contains ARCH001-ARCH009 and all 29 production assemblies are referenced."

for token in \
  'ProductionProjectGraphMustRemainAcyclic' \
  'ModuleImplementationsMustNotReferenceOtherImplementations' \
  'ContractProjectsMustRemainBoundaryOnly' \
  'ClientProjectsMustNotReferenceServerOrModules' \
  'SharedLibrariesMustRemainIndependentFromServerAndModules' \
  'OnlyServerHostMayReferenceModuleImplementations' \
  'GenericCommonUtilityProjectsMustNotBeIntroduced' \
  'ModuleNamespaceSlicesMustRemainFreeOfCycles' \
  'ArchitectureAssemblyCatalogMustCoverEveryProductionProject'; do
  grep -Rq "$token" "$repo_root/tests/Nexali.Architecture.Tests" || die "Missing architecture test: $token"
done
log OK "Executable architecture rules are present."

catalog="$repo_root/tests/Nexali.Architecture.Tests/ArchitectureAssemblyCatalog.cs"
grep -Fq 'using ArchUnitArchitecture = ArchUnitNET.Domain.Architecture;' "$catalog" \
  || die "ArchitectureAssemblyCatalog.cs must alias ArchUnitNET.Domain.Architecture to avoid the Nexali.Architecture.Tests namespace collision."
grep -Fq 'Lazy<ArchUnitArchitecture>' "$catalog" \
  || die "ArchitectureAssemblyCatalog.cs does not use the explicit ArchUnitArchitecture alias."
log OK "ArchUnitNET Architecture type is explicitly disambiguated from the Nexali.Architecture.Tests namespace."

archunit_tests="$repo_root/tests/Nexali.Architecture.Tests/ArchUnitDependencyTests.cs"
grep -Fq 'using static ArchUnitNET.Fluent.Slices.SliceRuleDefinition;' "$archunit_tests" \
  || die "ArchUnitDependencyTests.cs must import SliceRuleDefinition for the Slices() factory."
if grep -Fq 'using static ArchUnitNET.Fluent.ArchRuleDefinition;' "$archunit_tests"; then
  die "ArchUnitDependencyTests.cs must not resolve Slices() through ArchRuleDefinition."
fi
grep -Fq 'var rule = Slices()' "$archunit_tests" \
  || die "ArchUnitDependencyTests.cs must infer the concrete slice rule type to satisfy CA1859."

graph="$repo_root/tests/Nexali.Architecture.Tests/ProjectDependencyGraph.cs"
grep -Fq 'private static string[] LoadReferences(' "$graph" \
  || die "ProjectDependencyGraph.LoadReferences must return string[] to satisfy CA1859."
grep -Fq 'public ProjectDefinition[] GetReferences(' "$graph" \
  || die "ProjectDependencyGraph.GetReferences must expose the concrete array result."
grep -Fq 'public string[] FindCyclicProductionProjects()' "$graph" \
  || die "ProjectDependencyGraph.FindCyclicProductionProjects must expose the concrete array result."

project_tests="$repo_root/tests/Nexali.Architecture.Tests/ProjectDependencyTests.cs"
grep -Fq 'private static List<string> FindRoleReferenceViolations(' "$project_tests" \
  || die "ProjectDependencyTests.FindRoleReferenceViolations must return List<string> to satisfy CA1859."
grep -Fq 'cyclicProjects.Length == 0' "$project_tests" \
  || die "ProjectDependencyTests must use array Length for FindCyclicProductionProjects results."
if grep -Fq 'cyclicProjects.Count == 0' "$project_tests"; then
  die "ProjectDependencyTests must not treat the string[] cycle result as a collection Count property."
fi
log OK "ArchUnitNET slice API, concrete-type, and array-length guardrails are valid."

cd "$repo_root"
log CHECK "Restoring architecture-test dependencies."
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  TESTINGPLATFORM_TELEMETRY_OPTOUT=1 \
  dotnet restore "$repo_root/Nexali.sln" --nologo >/dev/null

log CHECK "Building architecture tests explicitly in Debug configuration."
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  dotnet build "$project" --configuration Debug --no-restore --nologo --verbosity minimal -p:RunAnalyzers=true \
  || die "Architecture test project failed to build in Debug configuration."
log OK "Architecture test project built successfully in Debug configuration."

module_rel="tests/Nexali.Architecture.Tests/bin/Debug/net10.0/Nexali.Architecture.Tests.dll"
module="$repo_root/$module_rel"
[[ -f "$module" ]] || die "Architecture test module was not produced at: $module_rel"

log CHECK "Running the compiled architecture-test module through Microsoft Testing Platform."
NEXALI_REPO_ROOT="$repo_root" \
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
TESTINGPLATFORM_TELEMETRY_OPTOUT=1 \
  dotnet test --test-modules "$module_rel" --root-directory "$repo_root" --minimum-expected-tests 9 --no-ansi --no-progress \
  || die "Architecture test suite failed."
log OK "Architecture test suite passed with all nine baseline tests present."
log OK "Nexali Phase 1.7 architecture-test baseline validation passed."
