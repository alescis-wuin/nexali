# Initial continuous integration baseline

Phase 1.8 turns the local repository gates from Phases 1.4–1.7 into GitHub Actions checks.

## Required checks

The workflow exposes exactly two stable check names:

- `PR source chain`
- `Repository gate`

These names are intentionally stable because GitHub branch protection uses them as required status-check contexts.

## Events

The CI workflow runs for pull requests targeting `develop`, `testing`, or `main`, for pushes to those protected branches, and through manual `workflow_dispatch` runs.

The pull-request promotion chain is:

```text
<type>/<name> -> develop -> testing -> main
```

`PR source chain` enforces this relationship by calling `scripts/validate-pr-source.sh`.

`Repository gate` executes `scripts/validate-repository.sh`, which already composes the solution, Git governance, project structure, build/package, formatting/analyzer, and architecture-test gates.

## Security model

Phase 1.8 deliberately uses `pull_request`, not `pull_request_target`, for code validation.

- workflow permissions are `contents: read`;
- no repository or organization secret is required;
- checkout credentials are not persisted;
- official GitHub actions are pinned by full commit SHA;
- the runner is pinned to `ubuntu-24.04`;
- third-party dependency caching is not enabled yet;
- CI executes the pull-request merge/head content only in the read-only pull-request security model.

Approved action pins are registered in `eng/ci-baseline.tsv`.

## .NET toolchain

`actions/setup-dotnet` reads the repository `global.json`. The workflow therefore uses the same .NET 10 SDK policy as local development instead of duplicating an SDK version in YAML.

NuGet caching is intentionally deferred until Nexali adopts `packages.lock.json`/locked restore. `setup-dotnet` caching requires NuGet lock files, and introducing a cache before the lock-file policy would weaken reproducibility rather than improve it.

## Running the gates locally

Validate only the CI baseline:

```bash
./scripts/validate-ci-baseline.sh
```

Validate the source-chain policy:

```bash
./scripts/validate-pr-source.sh --self-test
```

Run the complete gate used by GitHub Actions:

```bash
./scripts/validate-repository.sh
```

## Activating required checks

The Phase 1.8 topic package does **not** mutate GitHub branch protection before the workflow is merged. This prevents the introducing pull request from becoming impossible to merge.

After Phase 1.8 is merged and the two checks have executed successfully at least once, run:

```bash
./scripts/configure-github-governance.sh
```

The governance script configures strict required status checks for `main`, `testing`, and `develop` while retaining signed commits, PR-only updates, linear history, conversation resolution, and force-push/deletion protection.

## Phase boundary

Phase 1.8 does not add PostgreSQL, MinIO, Redis, Testcontainers services, deployment images, or Docker Compose execution. Those belong to Phase 1.9 and later test/infrastructure phases.
