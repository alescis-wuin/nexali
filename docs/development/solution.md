# Solution baseline

`Nexali.sln` is the canonical .NET solution file for Nexali.

## Why `.sln`

The architecture baseline explicitly selected `Nexali.sln`. .NET 10 defaults `dotnet new sln` to the newer `.slnx` format, so Nexali intentionally uses the classic `.sln` format for this baseline. When regenerating an empty solution with the .NET 10 CLI, use `dotnet new sln --name Nexali --format sln`.

## Phase 1.2 scope

Phase 1.2 creates an empty solution only. It does not create projects and does not manually inject empty Visual Studio solution folders into the `.sln` file.

The canonical future solution-folder paths are stored in `eng/solution-folders.txt`. Phase 1.3 creates projects and adds them with `dotnet sln Nexali.sln add ... --solution-folder <path>`, which lets the .NET tooling materialize the virtual solution-folder hierarchy.

Planned solution folders:

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
```

The validator checks the solution format, required configurations, the planned folder manifest, accidental `.slnx` creation, and uses `dotnet sln Nexali.sln list` when a .NET SDK is available.
