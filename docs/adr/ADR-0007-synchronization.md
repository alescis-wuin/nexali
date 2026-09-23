# ADR-0007: Durable synchronization architecture

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Multi-device synchronization must survive disconnects, crashes, duplicate delivery, missed notifications, and concurrent edits without silent data loss.

## Decision

Use durable per-scope change feeds with opaque cursors, a separate entitlement feed, bootstrap via snapshot + watermark + delta, at-least-once delivery, ClientOperationId idempotence, ExpectedRevision concurrency, client-side conflict handling, and advisory-only SignalR.

## Consequences

Desktop sync maintains a durable SQLite tracking database and pending-operation queue, combines filesystem watching with reconciliation, resumes uploads, performs atomic downloads, and preserves tombstones.

## Alternatives considered

Silent last-write-wins, timestamps as conflict authority, filesystem watcher as the only truth source, and following symlinks in the MVP were rejected.

## Security impact

Encrypted names remain server-private; cryptographic NameTags may reveal only same-parent equality needed for portable collision detection.

## Migration / reversibility

Cursor expiry triggers rebootstrap. Future offline mode builds on the same durable pending-operation model.
