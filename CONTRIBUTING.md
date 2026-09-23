# Contributing to Nexali

## Language

Code, identifiers, namespaces, branches, commits, tests, ADRs, and technical documentation are written in English. User-facing strings must be localizable.

## Branches

Use:

```text
<type>/<name>
```

For automated agents:

```text
agent/<type>/<name>
```

Allowed types include `feature`, `fix`, `refactor`, `test`, `docs`, `security`, `perf`, `build`, `ci`, `chore`, and `release`.

Examples:

```text
feature/drive-upload
security/device-key-validation
agent/build/repository-bootstrap
```

## Commits

Commit header format:

```text
<type>(<branch_name>): <title>
```

Example:

```text
build(build/repository-bootstrap): initialize repository structure
```

Use the body for meaningful implementation details and the footer for issue references, breaking changes, migrations, or security notes.

Commits and release tags must be signed using the contributor's configured Git signing mechanism. Private signing keys must never be committed.

## Pull requests

Pull requests should be focused and include purpose, key changes, tests, security impact, accessibility impact, architecture impact, and migration impact when applicable.

`main` must remain buildable, tested, and deployable. Normal feature work does not happen directly on `main`.

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
