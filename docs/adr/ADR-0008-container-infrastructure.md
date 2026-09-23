# ADR-0008: Container infrastructure

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Self-hosting must be reproducible and simple without introducing orchestration complexity too early.

## Decision

Use Docker Compose v2/current Compose Specification, Linux containers for amd64/arm64, nexali-web, nexali-api, one-shot migration/storage-init jobs, PostgreSQL, MinIO, and ephemeral Redis on a private backend network.

## Consequences

Application containers are stateless, non-root, versioned explicitly, and do not receive the Docker socket. Secrets remain outside images and versioned .env files.

## Alternatives considered

Kubernetes, privileged containers, public database/object-store ports, silent auto-updates, and :latest production deployments were rejected.

## Security impact

Backups and upgrades are explicit and coordinated; runtime DB accounts do not need schema-migration privileges.

## Migration / reversibility

Kubernetes or service extraction may be reconsidered only after measured need.
