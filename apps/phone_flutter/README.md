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

For explicitly dated debug data, add `--dart-define=WARD_PULSE_MOCK_ANCHOR=2026-11-02T12:00:00Z`.
The anchor accepts exactly `YYYY-MM-DDTHH:MM:SSZ` (Gregorian UTC, whole seconds).
An explicitly empty, malformed or out-of-range value fails the Mock load; it never
falls back to historical or current time. Anchors whose rebased history or next billing
boundary cannot be represented within years 0001–9999 also fail. Omit the define to
retain the exact seed-only scenario. Both defines are consumed only by debug startup.

Anchored composition has five accounts: OpenAI reporting, Codex plan, Claude plan,
Anthropic reporting and Cursor plan. It uses the existing synthetic Max Fable fixture
and both Cursor pools, omitting the optional Cursor Team reporting connection.
The unanchored seed-only composition retains all six accounts, including Cursor Team
with its unknown day/week budgets.
Rust rebases calendar/reporting/history/billing dates before normalization and preserves
rolling reset offsets, missing resets and unknown consumption. It reads no clock.
The actually generated seed **280**, anchor **2026-11-02T12:00:00Z**, provides:

| Widget metric | Used % |
| --- | ---: |
| Codex Weekly | 9.6 |
| Claude 5-hour | 48.4 |
| Claude Weekly | 30.6 |
| Claude Fable weekly | 36.9 |
| Cursor Models | 45.95531337916742 |
| Cursor Other Models | 2.3 |

These six plan metrics are healthy; Codex has **1200** finite purchased credits.
For a healthy capture, the overall snapshot, every included account and every rendered
allowance must be OK. Verify the complete native screen has zero app-bar/family problem
counters, including grey Unknown badges; healthy selected metrics alone are insufficient.
Other seeds can still produce unhealthy states, and missing optional values remain missing.
For the watch, select Codex plan, Claude plan + Fable, and both Cursor pools: three bands
with two completed pairs.
Use one cached accepted snapshot and normal guarded sync for related views; refresh or
Mock-toggle invalidation advances the seed, while process restart restores the configured seed.
This dated example is Mock data, not evidence of current device or public readiness.

Before enabling Mock for capture, qualify custody/restoration of live credentials,
preferences, notification bookkeeping and wake, or HOLD. Mock clears the recovery watchlist
and cancels its wake; toggling back cannot restore that history. Native/public capture,
real default weather availability and Pending headless-publication proof remain separate gates.

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

Production `main` retains one notification coordinator across DashboardHost recreation. It
registers both existing system channels without a post, including when delivery is Off, and
requests the shared Android permission once after successful effective-choice reads and a
completed resumed frame when either choice is On. Failed/held reads and stale ownership cannot
authorize asking. A secure attempt marker prevents repeated automatic requests after denial or
restart; explicit Off→On retries remain available with blocking feedback. Missing marker state
allows one OS-bounded pre-release bootstrap, not an inference about earlier permission history.
The durable claim can consume that opportunity if the process crashes before dispatch. Existing
OS/channel policy, saved delivery choices and delivery bookkeeping are preserved.

The default integration invocation runs only the original denied delivery case, with an
explicit handled startup fixture and both choices still default-On. The test-only
`WARDPULSE_NOTIFICATION_FIRST_FOREGROUND=true` define selects only the focused real-request
case. Never combine their incompatible OS prerequisites. Both are mandatory HOST acceptance;
neither case proves normal production scheduling or durable process-restart behavior.

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
an SDK build message alone establishes no installed identity. Before any device mutation,
record original permission state **and flags**, app/channel presence, blocking and importance,
and normal-live profiles/rules/bookkeeping without exporting credentials. Qualify exact
restoration of every touched setting; an originally absent channel is not automatically safe
to delete. HOLD the affected route if restoration is unproved.

Immediately before OS denial, freshly qualify the **complete existing WardPulse post set**,
not only the unused case identities. Denial may kill the UID and cancel its notifications.
Preserve legitimate posts or HOLD the case if reversible preservation is unproved; never
automatically cancel or repost them. An actually observed empty app-post set can qualify this
guard alongside the original permission flags and channels. The baseline is Unknown until
observed. Finish preflight and arm restoration before launching the timed case.

Install the verified target without removing the app or clearing its data:

```sh
adb -s "$PHONE_SERIAL" install -t -r build/app/outputs/flutter-apk/app-debug.apk || exit 1
```

**Stop on installation failure.** Do not uninstall, clear data or substitute a convenience
`flutter drive` route that installs the target. After verified successful installation and
before launching the default isolated target, qualify genuine Android OS denial and its
reversible restoration through the admitted permission route. Recheck preservation and
restoration guards before any mutation. Do not use revoke, permission-flag resets, AppOps,
clear/uninstall, force-stop or a fake permission result to manufacture a convenient baseline.
If the required baseline is unavailable, leave this acceptance Pending.
Then launch the target already denied:

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
**Continue** barrier only after inspecting and retaining the requested OS evidence. READY
requires the prelaunch denial/restoration receipts, and real `canPost` must be false. While
denied, the case consumes 90, exercises exhausted 100 → usable 20 recovery/tracking, and publishes
90 again so its alert marker is consumed while recovery tracking is clear. DENIED ALERT and
DENIED RECOVERY require absence observations for both case identities.

At the single **GRANT** barrier, retain before/after receipts proving the same actual PID,
process start ticks and Dart VM-service identity. Enable Android notifications ON once and
verify permission/channel policy; the case must observe real `canPost` changing false → true.
Grant continuity remains unverified on API36 until these receipts exist. Continue only after
continuity is established. Do not revoke again while the case is alive. NO BACKLOG reobserves
unchanged 90 and requires both identities absent with no new alert or recovery adapter attempt.
The case then clears to 20 before the positive crossed→unchanged→clear→rearmed, independent
mute/no-backlog and positive exhausted→usable recovery outcomes.

Intended identities must be unused at entry; an occupied identity stops the case without
canceling it. Preserve private original shade frames and bounded UID/channel/tag/ID/post-update
facts at CROSSED, UNCHANGED, CLEAR, REARMED, EXHAUSTED and RECOVERED; inspect absence at denial,
NO BACKLOG and mute barriers. Do not dismiss case posts during comparisons. Retain each receipt
and original throughout the run, including partial evidence on abort; do not wait for JSON.
The stock driver's awaited callback writes available response JSON before validating the selected
case's completed report; failure diagnostics are retained too. Retained JSON can be null or
incomplete. Callback rejection prevents successful wrapper completion, and framework failure or
timeout remains failure even if the driver prints success. Default `reportData` remains assigned
after the final RECOVERED Continue and notification assertions. A completed report still requires
the actual OS evidence above. Killed or aborted cases remain incomplete; retain failed results
as failures. If a permission change kills the process or continuity is unproved, stop the case
and restore after driver termination. Never relaunch with reconstructed memory and call it a
resumed case.

The adapters distinguish attempts from successful plugin completion, and the case queries its
own active Android identities. Neither a completed Future nor unchanged tags/counts proves
delivery, no repost or exactly-once behavior. OS observations remain necessary. This proves only
the injected pipeline with real adapters; separately verify production `main` Off/restart, the real foreground timer
and actual headless dispatch. Leave unexercised real-edge/background/physical scope Pending.

On success or failure, await the case and driver's terminal result and retain teardown's
outcome. Cleanup cancels only posts created by this case; never reset notifications globally.
If interrupted before teardown, retain partial private originals and reconcile only its
recorded identities. Restore an originally denied policy only after the case and driver have
finished, never during the remaining barriers.
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

### Focused first-foreground request case

Use a qualified existing AVD with a naturally eligible, ungranted Android notification
permission baseline and reversible channel/policy preservation. Do not create an AVD or reset
data/permission flags to obtain it. Apply the same whole-DONE/CLI-exit/retirement/fresh-idle,
artifact/install/UID joins, case-identity and normal-APK restoration guards above. Build and
attach separately from the default denied case, from `apps/phone_flutter`:

```sh
flutter build apk --debug --target=integration_test/notification_delivery_test.dart --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false --dart-define=WARDPULSE_NOTIFICATION_FIRST_FOREGROUND=true
flutter drive -d "$PHONE_SERIAL" --target=integration_test/notification_delivery_test.dart --driver=test_driver/notification_delivery.dart --dart-define=WARDPULSE_NOTIFICATION_FIRST_FOREGROUND=true --use-existing-app="$WARDPULSE_NOTIFICATION_VM_URI" --keep-app-running
```

Retain the ordinary APK first; install and launch the verified selected APK through the
existing guarded route between those commands. The focused case has a three-minute deadline
within the stock driver's timeout. Observe and retain the actual automatic Android permission
dialog and both discoverable system channels **before any case post**, then deny the dialog.
The case uses real coordinator/notifiers, unhandled case-owned bookkeeping and no crossed
input. It checks channel identity/metadata and retained importance, zero adapter posts, one
request, denial, and refresh/remount without a second request. Method invocation alone is not
dialog proof: if Android suppresses the dialog, keep that acceptance Pending.

Separately build/run the ordinary `lib/main.dart` debug APK to prove durable denial/restart
anti-nag, explicit-toggle blocking feedback and bounded background non-prompting. Qualify the
actual timer/headless dispatch where safely possible; this target's inert schedulers cannot
prove it. Preserve scheduled work and prove actual process replacement through the documented
background `am kill` route, never force-stop. Restore the verified normal current APK and
legitimate newer data, not an old snapshot over newer publications. Physical/OEM menu behavior
and public screenshots/release remain Pending separate work.
