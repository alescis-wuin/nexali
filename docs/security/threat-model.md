# Initial threat model

## Protected against

The E2EE design aims to protect user content and private metadata against compromise or direct inspection of:

- PostgreSQL data.
- MinIO object storage.
- Server backups.
- A server administrator reading databases/blobs directly.
- Storage infrastructure without the authorized client keys.

## Not protected against

E2EE cannot protect plaintext already exposed on an authorized endpoint against:

- Malware or keyloggers on the endpoint.
- A compromised Nexali client binary/runtime.
- An authorized recipient copying data after decryption.
- Local plaintext files intentionally synchronized to the desktop filesystem.

## Web trust limitation

A malicious server that controls the Web client assets can attempt to serve altered JavaScript/WASM. The Web client therefore has a different trust boundary from a separately installed, verified native client. This limitation must be documented and mitigated, not hidden.
