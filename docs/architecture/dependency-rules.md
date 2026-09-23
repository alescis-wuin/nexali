# Dependency rules

## Inter-module boundaries

- A module never references another module's implementation assembly.
- Synchronous collaboration uses the other module's explicit `.Contracts` surface.
- Secondary reactions prefer integration events.
- The dependency graph must remain acyclic.
- No module reads another module's `DbContext`, tables, or internal entities.
- No business SQL joins across module-owned schemas.
- `internal` is the default visibility for implementation types.
- `InternalsVisibleTo` is restricted to targeted test assemblies.

## Layer direction inside a module

Conceptually:

```text
Presentation -> Application/Features -> Domain
Infrastructure -> Application -> Domain
```

The Domain must not depend on EF Core, ASP.NET Core, Redis, MinIO, Avalonia, Blazor, or other infrastructure frameworks.

## Client boundaries

Web, Desktop, Android, and iOS clients use `Nexali.Client`, `Nexali.Client.Sync`, `Nexali.Cryptography`, and protocol libraries. They never reference server module implementations or EF Core.

## Cross-cutting rule

A new shared abstraction is introduced only after more than one real consumer demonstrates the need. Do not solve coupling by creating a generic `Common`, `Utils`, or `Helpers` project.
