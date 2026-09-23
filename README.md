# Nexali

> **Status:** pre-alpha / under active development. The architecture is defined, but the product is not yet ready for production use.

Nexali is a free/open-source, self-hostable, privacy-first collaborative workspace. Its long-term goal is to provide an integrated alternative for secure file storage, workspaces, calendar, tasks, communication, and document tooling while remaining accessible, interoperable, and deployable without a mandatory Nexali-hosted service.

## Principles

Nexali's architectural priorities are, in order:

1. Accessibility.
2. Reliability.
3. Security and end-to-end encryption.
4. Aesthetics.
5. Feature richness.
6. Multiplatform reach.

Strong baseline rules include client-side E2EE, no administrator decryption backdoor, WCAG 2.2 AA as a release gate, no silent data loss, no silent last-write-wins for user data, tested backup/restore, no central product telemetry, and no custom cryptography.

## Current MVP direction

The first MVP is intentionally narrow and centers on:

- Identity and authentication.
- Personal and shared workspaces.
- An encrypted Drive.
- Capability-based sharing.
- Durable multi-device synchronization.
- Blazor WebAssembly/PWA.
- Avalonia desktop plus minimal Android/iOS clients.
- Docker Compose self-hosting.

Calendar, Tasks, Kanban, Chat, Documents, and Sheets are future modules and are not presented as implemented features.

## Architecture

The backend is a .NET 10 ASP.NET Core modular monolith. Main bounded contexts are Identity, Workspaces, Drive, Sharing, Sync, Administration, and Audit. PostgreSQL is the durable structured-data store, MinIO stores encrypted blobs, and Redis is ephemeral only.

See [`docs/architecture/`](docs/architecture/) and [`docs/adr/`](docs/adr/).

## Repository structure

- `src/` — product source code.
- `tests/` — automated tests.
- `docs/` — architecture, ADRs, security, testing, deployment, and protocol documentation.
- `deploy/` — deployment assets.
- `eng/` — build and repository engineering tooling.
- `scripts/` — short deterministic helper scripts.
- `samples/` — future SDK/protocol examples only.

## Development

The repository is being bootstrapped incrementally. The .NET solution, project graph, centralized package management, analyzers, Docker stack, and CI are introduced in later Phase 1 steps.

Technical code and documentation are written in English. Contributions must follow [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security

Security issues must not be disclosed through a public issue. See [`SECURITY.md`](SECURITY.md).

The E2EE design is still pre-implementation and has not yet been independently audited. Do not make production-security claims based solely on this repository state.

## License

AGPL-3.0-or-later is the current license candidate, but final legal confirmation is still pending. See [`LICENSE-PENDING.md`](LICENSE-PENDING.md). No official public release should be made until the final license file is present.
