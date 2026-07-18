# WardPulse Phone App

Flutter phone app shell for the primary WardPulse dashboard.

Phase 2 is complete. The app loads a sanitized mock dashboard asset and renders the phone dashboard, usage history, provider list, provider detail, and settings surfaces. Its Android application ID is `app.wardpulse`; the runner builds and runs on the canonical phone emulator.

The verified Flutter and Android SDK baseline is documented in [`../../docs/ANDROID_TOOLCHAIN.md`](../../docs/ANDROID_TOOLCHAIN.md).

## Ownership

- Phone dashboard UI.
- Provider setup screens.
- Platform transport for provider APIs.
- Secure credential storage integration.
- Local persistence and sync scheduling.
- Wear Data Layer sender.

The phone app consumes Rust-produced dashboard state; the Rust core must not depend on Flutter.
