# ADR-0002: Solution and module boundaries

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The solution must remain understandable while enforcing real module boundaries.

## Decision

Use one Nexali solution. Each main bounded context gets one implementation assembly and, where needed, one lightweight Contracts assembly. Implementation types are internal by default. Cross-module implementation references, cross-DbContext access, and business joins across module schemas are forbidden.

## Consequences

The project count stays lower than a four-assembly-per-layer design while architecture tests preserve boundaries.

## Alternatives considered

A project per Clean Architecture layer and a generic Common/SharedKernel project were rejected initially.

## Security impact

Restricting public surfaces and database shortcuts reduces accidental privilege/data-boundary violations.

## Migration / reversibility

A new shared abstraction or assembly can be introduced later only when multiple real consumers justify it.
