# WardPulse Phone App

Flutter phone app shell for the primary WardPulse dashboard.

This directory remains intentionally light while Phase 2 approaches acceptance. The current app shell loads a sanitized mock dashboard asset and renders the phone dashboard, usage history, provider list, provider detail, and settings surfaces. The reviewed Android runner and emulator build/run gate are still pending.

The verified Flutter and Android SDK baseline is documented in [`../../docs/ANDROID_TOOLCHAIN.md`](../../docs/ANDROID_TOOLCHAIN.md).

## Ownership

- Phone dashboard UI.
- Provider setup screens.
- Platform transport for provider APIs.
- Secure credential storage integration.
- Local persistence and sync scheduling.
- Wear Data Layer sender.

The phone app consumes Rust-produced dashboard state; the Rust core must not depend on Flutter.
