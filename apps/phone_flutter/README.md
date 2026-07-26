# WardPulse Phone App

Flutter phone app shell for the primary WardPulse dashboard.

Phase 3 is complete. The app loads a Rust-generated dashboard snapshot at runtime through
the narrow JSON FFI bridge and renders the phone dashboard, usage history, provider list,
provider detail, and settings surfaces. Its Android application ID is `app.wardpulse`; the
runner builds and runs on the canonical phone emulator.

The verified Flutter and Android SDK baseline is documented in
[`docs/ANDROID_TOOLCHAIN.md`](https://github.com/neuroborus/ward-pulse/blob/main/docs/ANDROID_TOOLCHAIN.md).

## Ownership

- Phone dashboard UI.
- Provider setup screens.
- Platform transport for provider APIs.
- On-device Codex account sign-in and read-only usage transport.
- Secure credential storage integration.
- Local persistence and sync scheduling.
- Wear Data Layer sender.

Mock dashboards are available only in debug builds and remain disabled until explicitly enabled
in Settings. Release builds never select the mock repository.

The phone app consumes Rust-produced dashboard state; the Rust core must not depend on Flutter.

Build the native libraries and run the app:

```sh
just run-phone
```
