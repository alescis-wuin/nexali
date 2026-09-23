# Deployment

The accepted deployment baseline is Docker Compose v2 / the current Compose Specification, using Linux containers for `linux/amd64` and `linux/arm64`.

The future baseline stack contains:

- `nexali-web`.
- `nexali-api`.
- One-shot database migration and MinIO initialization jobs.
- PostgreSQL.
- MinIO.
- Ephemeral Redis.

PostgreSQL, MinIO, and Redis remain on a private backend network. Production upgrades are explicit, migrations are separated from normal API startup, and backup/restore is coordinated across PostgreSQL, MinIO, configuration, and required server cryptographic material.

The actual Compose files are introduced later in Phase 1.
