# Build and package baseline

Phase 1.5 establishes the repository-wide .NET SDK, MSBuild, NuGet, UI-framework, and test-framework dependency baseline. Phase 1.6 builds on that baseline with code-quality enforcement.

## SDK selection

`global.json` selects .NET SDK `10.0.112` with `rollForward: latestPatch` and disables prerelease SDK selection. This keeps Nexali on the .NET 10 `10.0.1xx` feature band while allowing servicing patches installed by a developer or CI environment.

The same file selects `Microsoft.Testing.Platform` as the .NET 10 `dotnet test` runner.

## Repository-wide build properties

`Directory.Build.props` applies:

- C# stable `latest` language version (never `preview`);
- nullable reference types;
- implicit usings;
- compiler warnings as errors;
- deterministic compilation;
- portable debug information;
- `ContinuousIntegrationBuild` when `CI=true`;
- Phase 1.6 analyzer and code-style enforcement.

`Directory.Build.targets` guards Central Package Management, rejects preview language mode, and prevents project-level weakening of the Phase 1.6 code-quality policy at build time.

## NuGet Central Package Management

`Directory.Packages.props` is the only location for package versions. `Version` and `VersionOverride` values are not permitted in project-level `PackageReference` items.

`NuGet.config` deliberately uses a single explicit source: `nuget.org`.

The human- and script-readable package registry is `eng/package-baseline.tsv`.

## Pinned package baseline

| Package | Version | Usage |
| --- | ---: | --- |
| Microsoft.AspNetCore.Components.WebAssembly | 10.0.12 | active Web foundation |
| Microsoft.AspNetCore.Components.WebAssembly.DevServer | 10.0.12 | pinned, activation deferred |
| Avalonia | 12.1.3 | active shared Avalonia foundation |
| Avalonia.Desktop | 12.1.3 | active desktop foundation |
| Avalonia.Android | 12.1.3 | pinned, platform activation deferred |
| Avalonia.iOS | 12.1.3 | pinned, platform activation deferred |
| Avalonia.Themes.Fluent | 12.1.3 | active shared Avalonia foundation |
| CommunityToolkit.Mvvm | 8.4.2 | active shared MVVM foundation |
| Microsoft.NET.Test.Sdk | 18.10.1 | active compatibility test adapter baseline |
| xunit.v3 | 4.0.1 | active test framework |
| xunit.runner.visualstudio | 4.0.0 | active VSTest/Test Explorer compatibility |

## Mobile boundary

Avalonia.Android 12.1.3 targets .NET 10 Android platform TFMs and Avalonia.iOS 12.1.3 targets Apple platform TFMs. Their packages remain centrally pinned without activation in the mobile head projects so that the canonical Linux build remains workload-independent.

## Analyzer boundary

Phase 1.6 intentionally uses the official .NET/Roslyn analyzers shipped with the pinned SDK instead of adding StyleCop, Roslynator, or another broad third-party analyzer suite. The enabled rule set is pinned through `AnalysisLevel=10.0-recommended`; security analysis uses `AnalysisLevelSecurity=10.0-all`.

This keeps the dependency surface small while making analyzer behavior explicit and build-blocking. A third-party analyzer may be added later through an ADR if a concrete gap justifies it.

## Validation

```bash
./scripts/validate-build-baseline.sh
./scripts/validate-code-quality.sh
./scripts/validate-repository.sh
```
