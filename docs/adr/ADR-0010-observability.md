# ADR-0010: Observability and privacy

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Operators need diagnosis and health information without creating a new privacy channel.

## Decision

Use OpenTelemetry, structured sanitized logs, low-cardinality metrics, traces, health checks, TraceId/correlation, and optional operator-controlled OTLP export. Audit remains a separate bounded context.

## Consequences

Clients use local-first diagnostics and explicit inspectable diagnostic bundles. Healthy/Degraded/Unhealthy states distinguish partial dependency failures.

## Alternatives considered

Central Nexali telemetry, behavioral product analytics, automatic client diagnostic uploads, request-body logging, and secret-bearing dumps were rejected.

## Security impact

E2EE plaintext, passwords, tokens, keys, private names/content, and unbounded identifiers must not enter logs/metrics/traces.

## Migration / reversibility

Operators may plug in their own observability backend without changing Nexali's privacy filtering rules.
