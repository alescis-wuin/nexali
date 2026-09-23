# ADR-0006: End-to-end encryption baseline

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Nexali's privacy goal requires the server to store and route protected data without being able to decrypt it.

## Decision

Use client-side E2EE with an Account Root Key, Personal Space Key, workspace key epochs, per-resource keys, per-device keys, encrypted key envelopes, a Recovery Key without administrator backdoor, versioned cryptographic formats, and chunked authenticated encryption for large files.

## Consequences

Server-side search/content processing is constrained; recovery and sharing require explicit key-management flows.

## Alternatives considered

Server-side master decryption, custom cryptographic primitives, and using the user's password directly as a file-encryption key were rejected.

## Security impact

OPAQUE, HPKE, browser crypto, chunk format, secure storage, and the Web trust model require dedicated technical/security spikes before production implementation.

## Migration / reversibility

Cryptographic formats are versioned so suites can migrate without silently reinterpreting existing ciphertext.
