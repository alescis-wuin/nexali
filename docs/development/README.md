# Development

Nexali is developed incrementally with Test First/TDD as the default engineering method.

Repository-wide conventions are documented in `CONTRIBUTING.md` and `docs/adr/ADR-0011-technical-conventions.md`.

## Git workflow

Nexali uses protected `develop -> testing -> main` promotion with all normal work on `<type>/<name>` branches created from `develop`.

See [`git-workflow.md`](git-workflow.md).

Validate Git governance with:

```bash
./scripts/validate-git-governance.sh
```

## .NET solution

`Nexali.sln` is the canonical solution file. Its Phase 1.2 baseline and the planned solution-folder hierarchy are documented in [`solution.md`](solution.md).

Validate it with:

```bash
./scripts/validate-solution.sh
```

The .NET SDK pinning, central package management, analyzers, formatting commands, local Docker workflow, and CI commands are introduced in later Phase 1 steps.
