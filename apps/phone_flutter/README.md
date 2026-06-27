# WardPulse Phone App

Flutter phone app shell for the primary WardPulse dashboard.

This directory is intentionally light until the Rust dashboard model and mock fixtures settle. Generate or expand the Flutter project here when Phase 2 starts.

## Ownership

- Phone dashboard UI.
- Provider setup screens.
- Platform transport for provider APIs.
- Secure credential storage integration.
- Local persistence and sync scheduling.
- Wear Data Layer sender.

The phone app consumes Rust-produced dashboard state; the Rust core must not depend on Flutter.
