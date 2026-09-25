# Testing strategy

Nexali uses Test First/TDD by default and combines:

- Unit tests.
- Integration tests against real PostgreSQL/MinIO/Redis via Testcontainers.
- Architecture tests.
- API and contract tests.
- Cryptography and security tests.
- Synchronization property/fault-injection tests.
- Accessibility tests.
- Focused E2E tests.
- Automated backup/restore and migration/upgrade validation.

The target is at least 90% line coverage globally and for Domain, Cryptography, Security, and Sync, without treating coverage as a substitute for negative tests, fuzzing, mutation testing, or review.

WCAG 2.2 AA and backup/restore validation are release gates.

## Architecture tests

`Nexali.Architecture.Tests` is the release-blocking architecture test project. It combines direct project-reference graph checks with ArchUnitNET bytecode analysis and is executed in Debug configuration through `./scripts/validate-architecture-tests.sh`.
