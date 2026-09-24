# Project structure baseline

Phase 1.4 materializes the .NET project identities and reference graph selected by the architecture baseline.

## Scope

This phase intentionally creates package-free **project shells**. It establishes names, paths, target framework (`net10.0`), solution folders, executable composition shells, and project-to-project references without selecting external NuGet package versions.

Phase 1.5 owns SDK pinning, Central Package Management, package versions, and the conversion of UI/test shells to their concrete Blazor WebAssembly, Avalonia, and test SDK/package setup.

This split keeps dependency selection centralized instead of allowing templates to introduce package versions before `Directory.Packages.props` exists.

## Projects

The canonical catalog is `eng/projects.tsv`. The canonical project-reference graph is `eng/project-references.tsv`.

The baseline contains:

- 1 ASP.NET Core server host (`Nexali.Api`);
- 7 primary bounded-context implementation projects and 7 `.Contracts` projects;
- 4 future bounded-context implementation-only foundations (Calendar, Tasks, Kanban, Chat);
- 4 shared libraries (`Nexali.Cryptography`, `Nexali.Sync.Protocol`, `Nexali.Client`, `Nexali.Client.Sync`);
- 1 Web client shell;
- 4 Avalonia/client-platform shells;
- 1 CLI tool;
- 11 test project shells.

Total: **40 projects**.

## Important boundary

No external `PackageReference` is permitted in Phase 1.4. This is deliberate. The Web/Avalonia/test projects are not yet feature-complete templates; they are project identities prepared for the centralized dependency work in Phase 1.5.

## Validation

Run:

```bash
./scripts/validate-project-structure.sh
```

The validator checks the canonical catalog, project count, solution membership, target frameworks, external package absence, project references, solution-folder materialization, restore, and build.
