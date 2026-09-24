# Formatting and analyzer baseline

Phase 1.6 makes source formatting and static-analysis policy deterministic and locally enforceable before CI is introduced in Phase 1.8.

## Principles

- Formatting is repository policy, not an editor preference.
- The same `.editorconfig` drives IDEs, `dotnet format`, and build-visible IDE diagnostics.
- Official .NET analyzers are the initial analyzer baseline; no broad third-party analyzer suite is required.
- Analyzer and code-style warnings are build failures.
- Project files may not weaken analyzer, warning, or formatting policy locally.
- Security analyzer coverage is intentionally stricter than the general recommended set.

## MSBuild policy

`Directory.Build.props` pins:

```xml
<AnalysisLevel>10.0-recommended</AnalysisLevel>
<AnalysisLevelSecurity>10.0-all</AnalysisLevelSecurity>
<TreatWarningsAsErrors>true</TreatWarningsAsErrors>
<CodeAnalysisTreatWarningsAsErrors>true</CodeAnalysisTreatWarningsAsErrors>
<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
```

`Directory.Build.targets` rejects attempts to override these values during compilation.

Using a versioned `AnalysisLevel` keeps the enabled rule set on the .NET 10 baseline even if a newer SDK is installed, while still allowing analyzer bug fixes delivered with servicing SDKs.

## EditorConfig policy

`.editorconfig` defines UTF-8/LF source hygiene, four-space C# indentation, two-space XML/JSON/YAML indentation, using ordering, brace placement, namespace preferences, naming rules, and selected build-visible IDE diagnostics.

Three style diagnostics are explicitly build-visible from the start:

- `IDE0005`: unnecessary using directives;
- `IDE0055`: formatting violations;
- `IDE0060`: unused parameters on non-public methods.

Other preferences remain editor/formatter preferences unless they are intentionally promoted to warnings.

## Formatting workflow

Apply safe automatic formatting and code-style fixes:

```bash
./scripts/format.sh
```

Verify without changing files:

```bash
./scripts/format.sh --check
```

The formatting check intentionally verifies only deterministic whitespace/formatting changes:

```bash
dotnet format whitespace Nexali.sln --verify-no-changes
```

Build-visible style diagnostics are checked by the analyzer-enforced build instead of by `dotnet format --verify-no-changes`. This distinction matters because some valid Roslyn diagnostics, including `IDE0060`, do not always expose an automatic code fix to `dotnet format`.

## Permanent gate

Run:

```bash
./scripts/validate-code-quality.sh
```

It verifies:

1. the central MSBuild analyzer policy;
2. compile-time policy guards;
3. required `.editorconfig` rules;
4. absence of project-level analyzer/warning escape hatches;
5. the machine-readable policy registry in `eng/code-quality-baseline.tsv`;
6. `dotnet format whitespace --verify-no-changes`;
7. a full analyzer-enabled solution build, including warning-level IDE diagnostics.

`./scripts/validate-repository.sh` invokes the same gate after the existing solution, Git governance, project-structure, and build/package validations.

## CI boundary

Phase 1.6 does not add GitHub Actions. Phase 1.8 will execute the existing local gates remotely, including the formatting/analyzer validator and the Gitflow PR-source checks.
