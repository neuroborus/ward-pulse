# WardPulse Phone App

Flutter phone app shell for the primary WardPulse dashboard.

This directory is intentionally light while Phase 2 starts. The current app shell loads a sanitized mock dashboard asset and renders the first phone dashboard, provider list, provider detail, and settings surfaces.

## Ownership

- Phone dashboard UI.
- Provider setup screens.
- Platform transport for provider APIs.
- Secure credential storage integration.
- Local persistence and sync scheduling.
- Wear Data Layer sender.

The phone app consumes Rust-produced dashboard state; the Rust core must not depend on Flutter.
