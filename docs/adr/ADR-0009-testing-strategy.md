# ADR-0009: Testing strategy

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Reliability, E2EE, synchronization, accessibility, and restoration cannot be validated by unit tests alone.

## Decision

Use Test First/TDD by default; unit, integration, architecture, API, contract, crypto, sync, security, accessibility, E2E, migration, upgrade, and backup/restore tests. Integration tests use real PostgreSQL/MinIO/Redis through Testcontainers.

## Consequences

Critical paths receive negative tests, property-based testing, fault injection, fuzzing, and targeted mutation testing. Coverage target is at least 90% globally and in critical areas.

## Alternatives considered

EF Core InMemory as a proof of PostgreSQL behavior, flaky-test acceptance, and coverage-only quality measurement were rejected.

## Security impact

WCAG 2.2 AA and backup/restore are release-blocking. Secret leakage is tested with sentinel values.

## Migration / reversibility

Test scope may be selected for fast PR feedback, but full release validation remains mandatory.
