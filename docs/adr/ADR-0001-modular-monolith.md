# ADR-0001: Modular monolith architecture

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Nexali needs strong domain boundaries without the operational cost of distributed services during the MVP.

## Decision

Use a .NET 10 ASP.NET Core modular monolith with pragmatic Clean Architecture, vertical slices, pragmatic DDD, lightweight CQRS, domain/integration events, and a transactional Outbox.

## Consequences

Modules remain deployable together while keeping explicit ownership and contracts. Service extraction stays possible later.

## Alternatives considered

Generalized microservices, global Event Sourcing, distributed CQRS, and a mandatory broker were rejected for the MVP.

## Security impact

A smaller distributed attack surface and fewer moving parts improve reliability; module isolation must be enforced in CI.

## Migration / reversibility

Future services may be extracted only after measured operational or scaling needs justify the cost.
