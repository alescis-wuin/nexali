# ADR-0003: Backend and HTTP API

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Web, desktop, and mobile clients need one stable API-first backend.

## Decision

Use ASP.NET Core 10 Minimal APIs under /api/v1, OpenAPI, ProblemDetails, capability-based authorization, idempotent client operations, streaming/resumable uploads, explicit revisions, and SignalR only as a change notification mechanism.

## Consequences

The API remains stateless where practical and clients can evolve independently against explicit contracts.

## Alternatives considered

Private UI logic on the server and SignalR as the durable synchronization source were rejected.

## Security impact

Authorization is deny-by-default. Password authentication targets OPAQUE; passkeys/WebAuthn and TOTP are in scope.

## Migration / reversibility

API versions, DTOs, and compatibility policy can evolve independently from internal modules.
