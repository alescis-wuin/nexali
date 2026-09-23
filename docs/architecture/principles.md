# Architecture principles

## Priority order

1. Accessibility.
2. Reliability.
3. Security and end-to-end encryption.
4. Aesthetics.
5. Feature richness.
6. Multiplatform reach.

## Non-negotiable baseline

- Client-side E2EE for protected user content and private metadata.
- No administrator decryption backdoor.
- WCAG 2.2 AA minimum as a release gate.
- No silent data loss.
- No silent last-write-wins for user data.
- Explicit bounded-context ownership.
- No cross-module database access.
- Test First/TDD by default.
- Backup/restore must be tested, not merely documented.
- No central product telemetry or behavioral analytics.
- No custom cryptographic primitives.
- Self-hosting must not require a Nexali SaaS dependency.

## Architectural posture

Nexali starts as a pragmatic modular monolith. Complexity such as microservices, brokers, distributed CQRS, event sourcing, Kubernetes, or dedicated search infrastructure is introduced only after a measured need appears.
