# Phone-to-Watch Acceptance

The ordinary `just test-phone-watch-sync` entry point owns the complete paired-emulator
acceptance gate. It orchestrates the Flutter debug build, full Wear instrumentation,
update installs, real Data Layer delivery, and saved-summary retention. Source review,
manual sync, screenshots, old receipts and partial test suites do not establish acceptance.

## Prerequisites

- Bash 4.4 or newer, GNU `timeout` (including `--kill-after`), `sha256sum`, `mktemp`,
  `mkfifo`, and the usual `awk`, `sort`, `sed`, `grep`, `tr`, `cut`, `wc` utilities.
- An existing Android SDK selected by `ANDROID_HOME`, or `ANDROID_SDK_ROOT` when
  `ANDROID_HOME` is unset. Its `platform-tools/adb` must be executable.
- Executable Flutter on `PATH`, or its executable path in `WARDPULSE_FLUTTER_BIN`.
  The Android build tools, JDK and dependencies needed by Flutter and the Wear Gradle
  wrapper must already be usable; builds may need the host's ordinary network access.
- The online canonical AVDs `wardpulse_phone_play_api36` (phone) and
  `wardpulse_wear_round_api36_1` (watch), already paired, with both debug apps installed.
  Existing packages are necessary to prove data-preserving **updates**.
- ADB shell access to live AVD names, build characteristics, process start times,
  redacted logcat events, installed-APK hashes, package update times, and bounded
  native scheduling metadata. The Wear debug package must support `run-as` and
  `stat` for its saved summary. Unavailable or raced evidence is a HOLD.
- Safe evidence of logical work preservation, as described below. Native job IDs
  or successful `am kill` commands alone do not provide it.

For an initial environment only, the separate one-time entry point remains:

```sh
just prepare-phone-watch-sync
```

It requires the SDK's `cmdline-tools/latest/bin/android`, `avdmanager`, and emulator
executables; installs the Play Store phone image and creates the phone AVD if absent.
The canonical Wear AVD must already exist. Start both in Android Studio and pair them
with Device Manager's Wear pairing assistant. Install the Google Pixel Watch companion
with a dedicated test Google account. Its optional `Associate` action is unnecessary
for Data Layer. Preparation is not a recovery action for this correction: do not install
SDKs, recreate/reset AVDs, or re-pair an existing pair to make acceptance pass.

## Ordinary invocation and evidence

```sh
just test-phone-watch-sync
```

When other phones or watches are online, explicit serial overrides select the canonical
identities. Ports and Wear node IDs never establish identity:

```sh
PHONE_SERIAL=emulator-5554 \
WEAR_SERIAL=emulator-5556 \
just test-phone-watch-sync
```

Discovery checks live phone/watch characteristics, hardware features and exact AVD names. Offline,
unauthorized, ambiguous, swapped or noncanonical targets fail without fallback. Every
ADB invocation has an explicit selector; only the server-wide `devices` inventory ignores
that selector by ADB design. Verification never prepares or resets the environment.

All of the following are required for a future Pass:

1. Preservation evidence before disruptive stages, reconciled afterward. Unknown work
   correspondence, cancellation, missing specs or unexplained rescheduling is a HOLD.
2. A successful current `flutter build apk --debug`, the **entire** Wear
   `connectedDebugAndroidTest` with `--rerun-tasks`, and both successful `adb install -r`
   updates. The two output APKs are removed before building so stale artifacts cannot
   satisfy this stage.
   Each update must advance the installed package timestamp and match the current APK's
   SHA-256. Update process deaths must agree with observed lifecycle events.
3. Background/`am kill` handling for both apps before delivery. Record every observed
   app PID and start identity, reconcile death events and absence, then prove new launch
   identities. Initial absence is reported as absence. Foreground `am kill` exit status
   and a HOT bring-to-front are insufficient evidence of death or restart.
4. A new, exact redacted `WardPulseSync` success callback after a fresh log-stream
   boundary, independently followed by a stable saved-summary hash and file metadata.
   Old logs, invalid-summary warnings and matching saved data cannot satisfy delivery.
5. Verified phone separation followed by actual observed Wear death and a new Wear
   process. Equal saved-summary hashes and unchanged file metadata must persist through
   that transition and ten further seconds. The phone must stay absent with no new
   start/death events; no fresh receipt is allowed, including identical-byte delivery.
   Unexpected background/replacement processes, PID reuse, raced reads, summary writes,
   lost monitor boundaries, slow observations or expired deadlines invalidate retention.
6. Stable final persistence and work-preservation evidence. Only then may the script print
   Pass, successful phone/watch role/serial identification and the final summary hash.

ADB calls have five-second deadlines; discovery has a 30-second deadline. Flutter has
900 seconds, full Wear instrumentation 1,200 seconds, and each install 90 seconds.
Lifecycle observation loops have 15-second deadlines in addition to bounded background,
kill and launch commands; fresh delivery has 30 seconds and summary stability 15 seconds.
Retention has an overall 60-second deadline and rejects observation
gaps of three clock ticks or more (conservatively rounding elapsed time). Subprocess
failures propagate. Owned log readers have a finite lifetime and are retired on exit;
temporary pipes and sanitized event records are removed.
No subprocess failure can be overridden to obtain Pass.

## Preservation and current observability HOLD

The script does not force-stop WardPulse, clear app data, cancel/fabricate work, alter
connectivity, cadence, credentials, connections, recovery, Mock mode, selections, saved
summaries or pairing. It uses backgrounding and bounded `am kill`; an unkillable process
causes HOLD. The narrowly targeted Wear SystemUI recovery exception remains documented
in [Android toolchain guidance](../../docs/ANDROID_TOOLCHAIN.md#preserving-emulator-state).
It is not invoked by this acceptance program and does not authorize app force-stops.

`HeadlessProviderSync` in
[headless_provider_sync.dart](../../apps/phone_flutter/lib/sync/headless_provider_sync.dart) declares
`wardpulse.providerSync` / `providerSync`: connected-network periodic work using UPDATE,
with the existing cadence floored at 15 minutes. `WorkmanagerRecoveryWakeScheduler` in
[recovery_wake.dart](../../apps/phone_flutter/lib/sync/recovery_wake.dart) declares
`wardpulse.recoveryWake` / `recoveryWake`:
connected-network one-off work using REPLACE and a delay derived from the next reset.
Recovery absence can be legitimate; filler jobs cannot establish preservation. Native
IDs may change during legitimate execution or rescheduling, so neither fixed-ID matching
nor whole volatile-dump equality proves these logical specs survived.

**The current allowed JobScheduler interface cannot establish that logical correspondence,
WorkManager kind, cadence/reset delay and state evidence. Verification therefore
currently exits HOLD at its preservation preflight, before builds, instrumentation,
installs or lifecycle disruption. It cannot currently issue Pass.** The device-side
projection exports only bounded native job identifiers, WorkManager service markers,
network-constraint presence and a count. It never exports a whole dump or raw job extras.
Those native records are explicitly insufficient; the script does not infer missing
logical specs or claim a before/after preservation comparison it cannot perform.

There is no manual override. No WorkManager database or other preferences are read, no
private diagnostics worker is scheduled, and no app/SDK/helper/dependency changes are made
to bridge this evidence gap. Permitted logical metadata and reconciliation would need to
be established before this gate could advance. Missing safe evidence remains a concrete
HOLD rather than a runtime acceptance claim.

`summary_hash` is the sole reader of `watch_summary.xml`: bytes go directly through its
hash pipeline. Only hashes and bounded safe metadata are retained; XML/payloads are never
printed or saved. `stat` observes file identity and write times without reading contents.
Continuous sanitized lifecycle/receipt streams plus explicit marker acknowledgements
reconcile observations; logcat and polling are not intrinsically lossless. Detectable gaps
fail, and unavailable continuity evidence must not be represented as proof of quiet.
A pending identical publication without an observable callback cannot be ruled out by
hash equality. The current preflight HOLD does not claim to solve that observability limit.

## Dated status

- 2026-10-18: preservation correction authored. The previous force-stop/old-log approach
  is replaced by bounded lifecycle and independent callback/persistence requirements,
  with an explicit preflight HOLD for unavailable logical work evidence. No runtime
  acceptance is claimed. Full ordinary sync acceptance, documentation validation and
  other applicable HOST checks remain pending after Runner completion and retirement.
