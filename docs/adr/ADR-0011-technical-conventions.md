# ADR-0011: Technical conventions

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

A multi-platform open-source project needs consistent conventions from its first implementation commit.

## Decision

Use English for technical code/docs, UTF-8/LF, .NET nullable analysis, warnings as errors, strongly typed IDs, async I/O with cancellation, explicit dependency injection, semantic versioning, signed Git history, and branch/commit conventions documented in CONTRIBUTING.md.

## Consequences

Public surfaces stay minimal and stable; accessible UI and secure logging are part of the Definition of Done.

## Alternatives considered

Service locator, global generic repository, custom crypto, large in-memory file handling, untracked TODOs, and ad-hoc secret storage were rejected.

## Security impact

Security-sensitive exceptions require explicit documentation and normally an ADR.

## Migration / reversibility

Conventions can evolve through a superseding ADR, but must not drift silently.
