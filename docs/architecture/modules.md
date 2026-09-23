# Modules and ownership

## Identity

Owns users, authentication credentials, passkeys, TOTP configuration, sessions, devices, recovery configuration, and user/device public keys.

Does not own workspaces, file permissions, Drive resources, quotas, or collaboration data.

## Workspaces

Owns workspaces, memberships, groups/classes, group membership, and workspace/educational roles.

Does not own authentication, files, key envelopes, or synchronization state.

## Drive

Owns the logical file system: files, directories, blob references, storage usage, effective storage quotas, resource revisions, and encrypted resource metadata.

All future attachment/file use cases reference Drive rather than creating separate file stores.

## Sharing

Owns access grants, capabilities, resource references, principals, and encrypted resource-key envelopes. It never holds decrypted resource keys.

## Sync

Owns durable change journals, opaque cursors, client-operation idempotence metadata, device checkpoints, and synchronization protocol state. It is not a duplicate business database.

## Administration

Owns instance-level configuration and administrative policy. It orchestrates other modules through contracts and never gains special decryption access.

## Audit

Owns sanitized security/administrative audit records. Audit is separate from technical logs, metrics, and traces.

## Future foundations

Calendar, Tasks, Kanban, and Chat are future bounded contexts. Kanban references Tasks instead of duplicating tasks. Documents and Sheets will reuse Drive and Sharing rather than reimplementing storage or permissions.
