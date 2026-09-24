# Project structure baseline

Phase 1.4 materializes the .NET project identities and reference graph selected by the architecture baseline.

## Scope

The phase established names, paths, target framework (`net10.0`), solution folders, executable composition shells, and project-to-project references before package selection.

Phase 1.5 adds the repository-wide SDK and package baseline while preserving the same 40 project identities and reference graph.

## Projects

The canonical catalog is `eng/projects.tsv`. The canonical project-reference graph is `eng/project-references.tsv`.

The baseline contains:

- 1 ASP.NET Core server host (`Nexali.Api`);
- 7 primary bounded-context implementation projects and 7 `.Contracts` projects;
- 4 future bounded-context implementation-only foundations (Calendar, Tasks, Kanban, Chat);
- 4 shared libraries (`Nexali.Cryptography`, `Nexali.Sync.Protocol`, `Nexali.Client`, `Nexali.Client.Sync`);
- 1 Web client foundation;
- 4 Avalonia/client-platform foundations;
- 1 CLI tool;
- 11 test projects.

Total: **40 projects**.

## Phase 1.5 transition

External package references are permitted only through NuGet Central Package Management. Project files must not carry package versions directly.

The Web project receives the Blazor WebAssembly package baseline while remaining a non-runnable project foundation until the Web application bootstrap is implemented. The shared Avalonia and desktop projects receive their framework packages. Android and iOS remain workload-independent `net10.0` shells; their platform TFMs and package references are intentionally deferred until platform bootstrap work.

The eleven test projects are converted to executable xUnit.net v3 projects and use Microsoft Testing Platform through `global.json`.

## Validation

Run:

```bash
./scripts/validate-project-structure.sh
./scripts/validate-build-baseline.sh
```

The validators check the canonical catalog, project count, solution membership, target frameworks, project references, solution-folder materialization, centralized package policy, restore, and build.
