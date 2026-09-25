# Architecture test baseline

Phase 1.7 turns the frozen Nexali dependency rules into executable tests before CI automation is introduced.

## Tooling

The architecture test project uses `TngTech.ArchUnitNET.xUnitV3` `0.13.4` together with the repository xUnit v3 / Microsoft Testing Platform baseline.

ArchUnitNET analyzes compiled assemblies. Architecture tests therefore run in **Debug** configuration, where dependency information is preserved most reliably.

## Two enforcement layers

Nexali deliberately uses two complementary mechanisms:

1. **Project graph tests** parse `eng/projects.tsv` and every project `ProjectReference`. These rules are effective immediately, even while some projects are still empty shells.
2. **ArchUnitNET bytecode tests** analyze compiled production assemblies and become increasingly valuable as types and namespace-level dependencies appear.

This avoids false confidence from bytecode-only tests while the repository is still in its bootstrap phase.

## Initial rules

The machine-readable registry is `eng/architecture-rules.tsv`.

- `ARCH001`: the production project graph is acyclic;
- `ARCH002`: module implementations never reference other module implementations;
- `ARCH003`: `.Contracts` projects remain boundary-only and do not depend on implementations, hosts, clients, or tools;
- `ARCH004`: clients never reference server or module projects;
- `ARCH005`: shared libraries remain independent from server, module, client, and tool projects;
- `ARCH006`: only the server composition root may reference module implementation projects;
- `ARCH007`: generic `Common`, `Utils`, `Utilities`, and `Helpers` project buckets are forbidden;
- `ARCH008`: `Nexali.Modules.(*)` namespace slices remain free of bytecode dependency cycles;
- `ARCH009`: the ArchUnitNET assembly catalog covers every production project.

The rules intentionally encode the current frozen architecture. A legitimate architecture change must update the relevant ADR/documentation and the executable rule in the same pull request.

## Running locally

Run the dedicated gate:

```bash
./scripts/validate-architecture-tests.sh
```

Or reproduce the gate manually:

```bash
dotnet restore Nexali.sln
dotnet build tests/Nexali.Architecture.Tests/Nexali.Architecture.Tests.csproj \
  --configuration Debug --no-restore -p:RunAnalyzers=true

NEXALI_REPO_ROOT="$PWD" dotnet test \
  --test-modules "tests/Nexali.Architecture.Tests/bin/Debug/net10.0/Nexali.Architecture.Tests.dll" \
  --root-directory "$PWD" \
  --minimum-expected-tests 9
```

The explicit build followed by `--test-modules` is intentional. It keeps ArchUnitNET in Debug configuration while avoiding an unnecessary second MSBuild project-property evaluation by the .NET 10 MTP driver.

The full repository gate also executes these tests through:

```bash
./scripts/validate-repository.sh
```

## Phase boundary

Phase 1.7 only establishes the architecture tests and their local validation command. GitHub Actions integration, required checks, PR source-chain enforcement, and remote CI execution remain Phase 1.8 responsibilities.
