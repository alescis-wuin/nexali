# Solution baseline

`Nexali.sln` is the canonical .NET solution file for Nexali.

## Why `.sln`

The architecture baseline explicitly selected `Nexali.sln`. .NET 10 defaults `dotnet new sln` to the newer `.slnx` format, so Nexali intentionally uses the classic `.sln` format for this baseline. When regenerating an empty solution with the .NET 10 CLI, use `dotnet new sln --name Nexali --format sln`.

## Phase 1.2

Phase 1.2 created the empty solution and pinned the planned top-level solution folders in `eng/solution-folders.txt`.

## Phase 1.4

Phase 1.4 creates the canonical project shells from `eng/projects.tsv` and materializes solution folders with:

```bash
dotnet sln Nexali.sln add <project> --solution-folder <folder>
```

Nested bounded-context folders below `src/Modules` are created by the .NET CLI from each manifest entry rather than by hand-editing the `.sln` format.

The current `dotnet sln add` implementation may rewrite classic `.sln` files with a UTF-8 BOM and CRLF line endings. The Phase 1.4 automation normalizes `Nexali.sln` back to the repository convention (UTF-8 without BOM, LF) before validation and commit.

Canonical top-level folders:

- `src/Server`
- `src/Modules`
- `src/Libraries`
- `src/Clients/Web`
- `src/Clients/Avalonia`
- `src/Tools`
- `tests`

## Validation

Run:

```bash
./scripts/validate-solution.sh
./scripts/validate-project-structure.sh
```

## Deterministic classic `.sln` encoding

The .NET CLI may rewrite classic `.sln` files using a UTF-8 BOM and/or CRLF line endings when projects are added. Nexali keeps repository text deterministic: `Nexali.sln` must be UTF-8 without BOM and LF-only.

`./scripts/validate-solution.sh --normalize` performs byte-level normalization and rejects unexpected solution headers before writing the normalized file. The validator uses Python 3 for deterministic encoding checks and diagnostics.
