# Security Policy

## Project status

Nexali is currently pre-alpha. The cryptographic architecture is designed but the production implementation and external security review are not complete.

Do not assume the current repository is suitable for protecting production-sensitive data.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Until a dedicated private reporting channel is configured, contact the repository owner through a private channel available on the hosting platform. A private vulnerability-reporting feature should be enabled before the first public release.

Include, when possible:

- A concise description of the issue.
- Affected component/version/commit.
- Reproduction steps.
- Security impact.
- Any suggested mitigation.

Do not include real credentials, private keys, recovery keys, tokens, or user data.

## Security principles

Nexali's security baseline includes:

- Client-side end-to-end encryption for protected user content and metadata.
- No administrator decryption backdoor.
- Least privilege.
- Explicit capability authorization.
- No custom cryptographic primitives.
- No secrets in logs, traces, metrics, diagnostics, Git, or container images.
- Tested backup/restore and synchronization failure handling.
- Security-sensitive architectural changes require explicit review and normally an ADR.

## Supported versions

No stable version is currently supported. This section will be replaced by a release support matrix before the first public release.
