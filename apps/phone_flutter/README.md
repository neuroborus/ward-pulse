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

## Reproducible Debug Mock Data

For repeatable capture data, build from `apps/phone_flutter/` with an optional starting seed:

```sh
flutter build apk --debug --dart-define=WARD_PULSE_MOCK_SEED=51
```

The define does not enable Mock data; turn it on explicitly in Settings. Release builds
do not select the mock repository; only the debug startup branch consumes the define.
The seed accepts ASCII decimal digits from **0** through **9223372036854775807**;
leading zeroes are valid. Signs, whitespace, decimals, exponents, hexadecimal values
and out-of-range values are invalid. An absent or invalid value retains the existing
time-based seed selection.

A loaded scenario stays cached across automatic sync. Invalidating a loaded scenario
advances the sequence once; repeated invalidation before another load does not advance
it again. Recreating the repository, including an app-process restart, starts from the
configured seed again. The maximum seed wraps to zero. A reproducible seed is not a
healthy-data preset: inspect the actual rendered statuses before choosing public captures.

## Persistent Connection Recovery

`PhoneLiveBindings` wires all six live connections to `ConnectionSnapshotCache` and the
headless-safe native `ConnectionCacheEngine` channel. Only canonical normalized snapshots
are cached; provider credentials stay in platform-secure storage. Fresh repositories after
restart can merge current data with stale failed connections without changing their original
success times. Mock data never enters this store.

Credential generation, OAuth revision and cache epoch are separate. Reconnect/disconnect
barriers and conditional writes prevent old requests from restoring removed accounts. The
native service coordinates concurrent Flutter engines in the application's single Android
process, including WorkManager; separate OS processes are unsupported. Foreground and
headless callers validate ownership before publication.

`just check-phone` includes `just test-phone-cache`, which runs the production Java transaction
engine's adversarial tests with the existing Android JDK (`javac` and `java`). Flutter tests also
exercise the real engine through a test-only JVM bridge with fake encrypted storage and HTTP
responses. No live credentials, emulator state or provider network are used by these tests.

Final-APK emulator acceptance on 2026-10-13 covered three real plan connections (Codex,
Claude and Cursor), a production periodic WorkManager task in a fresh background process,
offline cold-start recovery with unchanged cached data/success times, and restored live
phone-to-watch delivery. Hardware and whole-phase release acceptance remain separate gates.

## Cursor Sign-in Request Guard

`WebViewCursorSignInBrowser` wires `CursorSignInPlugin` to the existing plugin's WebView
and client before loading the sign-in page. `CursorSignInWebViewClient` blocks Google
authorization in both navigation and resource interception, including subframes. Native
interception also enforces the approved main-frame HTTPS/host policy for POST requests,
which skip Android's navigation callback. Explicit retirement admits only the internal blank
document. The client forwards other callbacks to the existing client and classifies HTTP failures with the native
`isForMainFrame` flag. Only view/client IDs and fixed failure categories cross the guard channel.
Retirement errors remain retryable while the shared cookie jar stays fenced.

Focused HOST coverage adds `cursor_sign_in_adapter_test.dart` to the affected Flutter
regressions and a dependency-free native callback harness:

```sh
python3 tools/test-cursor-sign-in/run.py
```

The harness compiles the production Java client against small Android API doubles. It checks
subframe authorization interception, harmless-resource delegation, fixed diagnostics and
main-document HTTP classification, and main-frame POST admission/rejection. It does not
prove native rendering or live login. Run it as an additional focused HOST regression
alongside the unchanged complete `just check-phone`.

Local verification on 2026-10-27–28 passed the complete phone check, affected Flutter
regressions and this JVM harness. Normal and seeded debug APKs were built and installed
with data preserved on the API36 phone emulator. Offline page recovery and Cancel were
rechecked in the normal build; earlier native verification of the unchanged sign-in code
also covers Retry, Cancel/back/reopen, Help and the empty Advanced paste editor. The saved connection
remained available without reading its value. These checks do not establish a new live
Google/email login, session capture, account entitlement or billing repair.
