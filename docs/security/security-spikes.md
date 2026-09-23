# Security and cryptography spikes

These investigations are required before the corresponding production implementation is finalized.

| ID | Topic | Initial status | Required outcome |
|---|---|---|---|
| S01 | OPAQUE | Not started | Select a mature, maintained, interoperable implementation for browser and native .NET clients, or formally evaluate a safe alternative. |
| S02 | HPKE | Not started | Select and validate an interoperable implementation for recipient key envelopes. |
| S03 | Browser crypto provider | Not started | Define the Web/WASM AEAD/KDF/randomness provider compatible with native protocol test vectors. |
| S04 | Chunk encryption format | Not started | Freeze chunk size strategy, nonce handling, AAD, manifest, streaming behavior, and format version. |
| S05 | Secure-storage matrix | Not started | Validate Windows, Linux, macOS, Android, and iOS secure key storage and failure behavior. |
| S06 | Web trust model | Not started | Document CSP, asset integrity, reproducible/signed releases, and limitations of a Web client served by the instance. |

No spike authorizes writing a home-grown cryptographic primitive.
