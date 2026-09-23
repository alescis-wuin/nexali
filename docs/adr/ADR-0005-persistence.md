# ADR-0005: Persistence architecture

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Nexali needs reliable structured persistence, encrypted blob storage, and ephemeral coordination state.

## Decision

Use PostgreSQL with EF Core/Npgsql, one schema and DbContext per bounded context, opaque UUID v4 identifiers, explicit Revision values, transactional Outbox, MinIO for ciphertext blobs, and Redis only for ephemeral state.

## Consequences

Persistence reflects module ownership and supports optimistic concurrency and durable synchronization.

## Alternatives considered

Cross-module foreign-key coupling, EF Core InMemory as PostgreSQL validation, and Redis as a durable source of truth were rejected.

## Security impact

Private metadata is stored encrypted; MinIO object names remain opaque; runtime DB privileges follow least privilege.

## Migration / reversibility

Migrations run as an explicit deployment step. Backups must coordinate PostgreSQL, MinIO, configuration, and required server material.
