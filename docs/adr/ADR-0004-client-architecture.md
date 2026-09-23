# ADR-0004: Web and Avalonia client architecture

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Nexali requires Web, desktop, Android, and iOS clients while preserving a client-side cryptographic trust boundary.

## Decision

Use a standalone Blazor WebAssembly PWA with no private SSR, plus Avalonia 12 with MVVM and CommunityToolkit.Mvvm. Share client SDK, sync protocol, cryptographic protocol/facade, design tokens, and localization concepts, not server implementations.

## Consequences

Sensitive plaintext stays on clients. Native platform heads stay thin and provide secure-storage/platform adapters.

## Alternatives considered

Blazor Server for private application state and a forced single UI technology across Web/native were rejected.

## Security impact

Native clients use OS secure key stores. The browser must not persist plaintext master secrets in ordinary storage.

## Migration / reversibility

Platform-specific implementations remain replaceable behind explicit interfaces.
