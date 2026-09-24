# Contributing to Nexali

## Language

Code, identifiers, namespaces, branches, commits, tests, ADRs, and technical documentation are written in English. User-facing strings must be localizable.

## Gitflow

Nexali uses the following integration order:

```text
<type>/<name> -> develop -> testing -> main
```

`main`, `testing`, and `develop` are protected branches. Do not commit or push directly to them. Changes are promoted only through pull requests.

Create normal work from `develop` with:

```bash
./scripts/git-start.sh <type> <name>
```

## Branches

The only topic-branch format is:

```text
<type>/<name>
```

Allowed types are `feature`, `fix`, `refactor`, `test`, `docs`, `security`, `perf`, `build`, `ci`, `chore`, and `release`.

`<name>` must be lowercase kebab-case without additional slashes.

Examples:

```text
feature/drive-upload
security/device-key-validation
build/git-governance
```

The former `agent/<type>/<name>` convention is superseded.

## Commits

Commit messages use a mandatory header and body, with an optional footer:

```text
<branch_type>(<branch_name>): <title>

Description:
<description>

Changes:
- <completed point>
- <completed point>

Footer:
Phase: <phase>
Ticket: <ticket>
```

The header type must match the current branch type and `<branch_name>` must be the exact current branch name. `Description:` must contain text and `Changes:` must contain at least one bullet. Footer entries, when present, use `Key: value`.

Commits and release tags must be signed. Private signing keys must never be committed.

## Pull requests

Normal promotion order:

```text
topic -> develop -> testing -> main
```

Pull requests should be focused and include purpose, key changes, tests, security impact, accessibility impact, architecture impact, and migration impact when applicable.

The exact source/base branch relation will become a required CI rule in Phase 1.8. Until then it remains mandatory project policy.

## Architecture rules

Core rules include:

- Modules do not reference another module's implementation assembly.
- Inter-module synchronous communication uses explicit contracts.
- Reactions use integration events when immediate consistency is unnecessary.
- No cross-module `DbContext` access or business joins across module schemas.
- Dependencies remain acyclic.
- Types are `internal` by default.
- Client applications never reference server module implementations.
- E2EE plaintext must not cross the server trust boundary.
- No custom cryptographic primitives.

See `docs/architecture/`.

## Quality

The project follows Test First/TDD by default. Bugs should receive a regression test before the fix whenever reasonably possible.

Do not commit generated build output, local databases, coverage artifacts, secrets, real user data, or developer credentials.

## Security and accessibility

Security and accessibility are part of the Definition of Done, not post-processing steps. WCAG 2.2 AA is a release requirement for applicable UI surfaces.
