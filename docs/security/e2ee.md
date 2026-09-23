# E2EE architecture baseline

Protected content is encrypted on trusted clients and remains ciphertext across the server boundary.

Accepted key hierarchy concepts include:

- Account Root Key (ARK).
- Personal Space Key.
- Workspace keys with epochs/rotation.
- Per-resource keys.
- Per-device keys.
- Recovery Key without an administrator backdoor.
- Encrypted key envelopes for sharing.

The password does not directly encrypt user files. OPAQUE is the target password-authentication architecture. Argon2id is the reference memory-hard KDF when local derivation from a human secret is required outside the OPAQUE flow.

Large files use versioned chunked authenticated encryption. Cryptographic formats are explicitly versioned and tested across platforms.

Nexali does not implement custom cryptographic primitives.
