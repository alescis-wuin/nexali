# Git workflow

Nexali uses a protected three-stage integration flow:

```text
<type>/<name> -> develop -> testing -> main
```

## Protected branches

`main`, `testing`, and `develop` are protected integration branches.

- Direct commits are forbidden.
- Direct pushes are forbidden.
- Force pushes and branch deletion must be blocked by the remote host.
- Changes enter through pull requests only.
- Commits must be signed.
- Linear history is required on protected branches.

`main` represents the most stable integration state, `testing` is the validation/staging branch, and `develop` is the integration target for normal development.

## Topic branches

All work is performed on a dedicated branch created from `develop`:

```text
<type>/<name>
```

Allowed types:

```text
feature fix refactor test docs security perf build ci chore release
```

`<name>` uses lowercase kebab-case and contains no additional slash.

Examples:

```text
feature/drive-upload
fix/sync-conflict
refactor/api-routing
build/git-governance
```

Create a topic branch with:

```bash
./scripts/git-start.sh feature drive-upload
```

The previous `agent/<type>/<name>` convention is superseded by the strict `<type>/<name>` convention.

## Commit format

Every commit uses:

```text
<branch_type>(<branch_name>): <title>

Description:
<description of the purpose and implementation>

Changes:
- <completed change>
- <completed change>

Footer:
Phase: <phase identifier>
Ticket: <optional ticket>
```

`Footer:` is optional. If present, each entry uses `Key: value`.

Example:

```text
feature(feature/drive-upload): add upload session foundation

Description:
Introduce the first application-level model for resumable uploads.

Changes:
- Add the upload session state model.
- Add validation for expected resource revisions.
- Add unit tests for invalid session transitions.

Footer:
Phase: 2.4
Ticket: NEX-123
```

## Promotion rules

Normal flow:

1. `<type>/<name>` -> pull request to `develop`.
2. `develop` -> pull request to `testing`.
3. `testing` -> pull request to `main`.

The source/base relationship becomes a required remote CI check in Phase 1.8. Until that gate exists, it is a mandatory project rule documented here and reinforced by local tooling.

## Local enforcement

Versioned hooks are stored in `.githooks/` and enabled with:

```text
core.hooksPath=.githooks
```

They prevent commits on protected branches, validate branch names and commit messages, and reject direct pushes to protected branches.

Local hooks are intentionally not considered a security boundary because `--no-verify` can bypass them.

## Remote enforcement

When the GitHub repository exists and `origin` is configured, run once:

```bash
./scripts/configure-github-governance.sh --bootstrap
```

This creates any missing remote protected branches once, then enables server-side protection. Subsequent direct pushes and force pushes to `main`, `testing`, and `develop` are rejected by GitHub.
