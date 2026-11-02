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

## Android notification integration case (HOST only)

`integration_test/notification_delivery_test.dart` mounts `WardPulseApp` with inline normalized
inputs, real Rust alert/recovery FFI and the real Android notification adapters. The first-party
SDK `integration_test` dependency supplies the binding and stock driver; no custom runner is
needed. Choices, rules, consumed markers and the recovery watchlist live only in case-owned
memory. Watch/widget/navigation/wake effects and both foreground/headless scheduling are inert.
The target never calls production `main`, initializes WorkManager or polls providers. Existing
OS-scheduled production work is separate and is neither canceled nor proved by this case.

Acceptance is **Pending** until HOST runs this route and records actual Android observations.
Begin only after the whole owning execution is DONE, its CLI has exited, all owned processes
have retired and a fresh separate idle check passes. The sole admitted native operator owns
all ADB, permission, channel and restoration actions; keep Square protected. First run unchanged
full `just check-phone` and the extra nonmutating format check from `apps/phone_flutter`:

```sh
dart format --output=none --set-exit-if-changed integration_test test_driver
```

From the repository root, run `just build-android-rust` for both Android ABIs. Then, from
`apps/phone_flutter`, retain an ordinary APK at a unique task-owned path outside `build/`:

```sh
: "${WARDPULSE_NORMAL_APK:?Set a unique retained normal APK path outside build/}"
flutter build apk --debug --target=lib/main.dart || exit 1
cp build/app/outputs/flutter-apk/app-debug.apk "$WARDPULSE_NORMAL_APK" || exit 1
sha256sum "$WARDPULSE_NORMAL_APK" || exit 1
flutter build apk --debug --target=integration_test/notification_delivery_test.dart --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false || exit 1
```

Before either installation, bind the source HEAD, APK SHA-256, application ID `app.wardpulse`,
version name/code and signer certificate to that artifact. Use SDK `apkanalyzer`/`apksigner`
and compare both packaged `lib/<abi>/libward_pulse_ffi.so` hashes against the corresponding
`android/app/src/main/jniLibs/<abi>/libward_pulse_ffi.so` inputs (`arm64-v8a`, `x86_64`). Compare
the installed package's signer/version and base-APK hash with the verified APK after install;
an SDK build message alone establishes no installed identity. Record original permissions,
channel settings and normal-live profiles/rules/bookkeeping without exporting credentials.

Install the verified target without removing the app or clearing its data:

```sh
adb -s "$PHONE_SERIAL" install -t -r build/app/outputs/flutter-apk/app-debug.apk || exit 1
```

**Stop on installation failure.** Do not uninstall, clear data or substitute a convenience
`flutter drive` route that installs the target. After verified successful installation, launch:

```sh
adb -s "$PHONE_SERIAL" shell am start -W -n app.wardpulse/.MainActivity || exit 1
WARDPULSE_NOTIFICATION_PID=$(adb -s "$PHONE_SERIAL" shell pidof app.wardpulse) || exit 1
adb -s "$PHONE_SERIAL" logcat --pid="$WARDPULSE_NOTIFICATION_PID" -d -s flutter:I
```

Require one current PID belonging to the verified target. Read its fresh Dart VM-service URL
from this scoped output; do not attach to an old log entry or another process. Set
`WARDPULSE_NOTIFICATION_DEVICE_PORT` to that URL's actual device port, then forward only it:

```sh
WARDPULSE_NOTIFICATION_HOST_PORT=$(adb -s "$PHONE_SERIAL" forward tcp:0 tcp:"$WARDPULSE_NOTIFICATION_DEVICE_PORT") || exit 1
```

Set `WARDPULSE_NOTIFICATION_VM_URI` to the exact logged HTTP URL, replacing only its port with
`WARDPULSE_NOTIFICATION_HOST_PORT` and preserving its authentication path. Attach the stock
driver to this already running app, with no automatic install/uninstall cleanup:

```sh
flutter drive -d "$PHONE_SERIAL" --target=integration_test/notification_delivery_test.dart --driver=test_driver/notification_delivery.dart --use-existing-app="$WARDPULSE_NOTIFICATION_VM_URI" --keep-app-running
```

The case has an 18-minute limit inside the stock driver's 20-minute timeout. Use each visible
**Continue** barrier after inspecting the requested OS state. It drives clear→crossed→unchanged
→clear→crossed, independent mute/no-backlog cases, actual Android denial/restoration, and a
genuinely exhausted→usable recovery. Intended identities must be unused at entry; an occupied
identity stops the case without canceling it. Preserve original shade frames and privacy-safe
UID/channel/tag/ID/post-update facts at CROSSED, UNCHANGED, CLEAR, REARMED, EXHAUSTED and RECOVERED,
and inspect absence at mute/denial barriers. Do not dismiss the case posts during comparisons.
If changing Android permission kills the process, record the case incomplete and restore;
do not claim a resumed test or replace actual denial with a fake permission result.

The adapters distinguish attempts from successful plugin completion, and the case queries its
own active Android identities. Neither a completed Future nor unchanged tags/counts proves
delivery, no repost or exactly-once behavior. OS observations remain necessary. This proves only
the injected pipeline with real adapters; separately verify production `main` Off/restart, the real foreground timer
and actual headless dispatch. Leave unexercised real-edge/background/physical scope Pending.

On success or failure, await teardown and cancel only posts created by this case; never reset
notifications globally. If interrupted before teardown, reconcile only its recorded identities.
Remove only the case's ADB forward, then restore the retained ordinary APK with data preserved:

```sh
adb -s "$PHONE_SERIAL" forward --remove tcp:"$WARDPULSE_NOTIFICATION_HOST_PORT"
adb -s "$PHONE_SERIAL" install -t -r "$WARDPULSE_NORMAL_APK" || exit 1
adb -s "$PHONE_SERIAL" shell am start -W -n app.wardpulse/.MainActivity || exit 1
```

Stop on restoration installation failure without uninstalling or clearing data. Reverify the
normal installed artifact/native libraries and restore normal-live state plus all touched
permissions, channels, profiles, rules and bookkeeping. The injected stores require no copying
into production. Root completes HOST acceptance and an independent zero-findings pass after
the last correction; builds or test completion alone do not establish delivery acceptance.
