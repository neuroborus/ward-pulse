# Phone-to-Watch Acceptance

The ordinary `just test-phone-watch-sync` entry point owns the complete paired-emulator
acceptance gate. It orchestrates the Flutter debug build, full Wear instrumentation,
update installs, real Data Layer delivery, and saved-summary retention. Source review,
an isolated manual sync, screenshots, old receipts and partial test suites do not establish
acceptance.

## Bounded foreground observation

`run.sh observe` provides a separate metadata/event session with fixed lifecycle controls.
It does not run `verify` or establish acceptance, quiet, lifecycle/work preservation, or
measurement results. `prepare`, `verify` and the ordinary acceptance recipe keep their
existing canonical round-watch target and defaults.

Select one existing Wear serial **and** its supported geometry explicitly:

```sh
WEAR_SERIAL=emulator-5556 tools/test-phone-watch-sync/run.sh observe 384-round
WEAR_SERIAL=emulator-5558 tools/test-phone-watch-sync/run.sh observe 360-notround
```

The targets are `wardpulse_wear_round_api36_1` (384×384, `round`) and
`wardpulse_wear_square_api36_1` (360×360, `notround`). The phone must be
`wardpulse_phone_play_api36`; set `PHONE_SERIAL` explicitly when other phones are online.
Ports do not prove identity. Both selected devices must already be online with
`app.wardpulse` installed. Observation needs Bash 4.4+, GNU `timeout`, an existing SDK's
executable ADB, and the ordinary `awk`, `cat`, `mktemp`, `mkfifo`, `sort`, `sed`, `tr`,
`wc`, `grep`, `rm` and `sleep` tools. It needs no Flutter, Java reader, build tools,
install, pairing change or `run-as` access.

Discovery and repeated boundary checks bind the actual AVD name, live role/features,
exact package UID with exclusive ownership, boot ID and UID-wide PID/start-tick
identities. Wear size must have no override, and its live resource configuration must
match the selected watch shape. Shared, isolated, unknown or ambiguous process ownership,
boot/UID changes and unexplained PID reuse fail closed. Existing installed apps may
produce observed lifecycle and sync events; the lifecycle ledger must reconcile them.

The process stays in the foreground. Keep its stdin and stdout open and consume output
promptly, retaining stdout in the caller's evidence stream. Wait for `READY` before the
first request, and for `ACK` before each subsequent request. Send ASCII lines with exactly
one space and a newline; request IDs must be consecutive decimal integers starting at 1,
with at most 32 requests including close:

```text
DRAIN 1
STOP PHONE 2
STOP WEAR 3
LAUNCH WEAR 4
LAUNCH PHONE 5
DRAIN 6
CLOSE 7
```

`DRAIN` rechecks identity, reconciles inventories and acknowledges fresh log boundaries on
both roles. `STOP PHONE`, `STOP WEAR`, `LAUNCH PHONE` and `LAUNCH WEAR` use the already-bound
phone or selected watch, within the same live observer. Each lifecycle request checks both
roles before acting and reconciles both roles again before its acknowledgement. No serial,
PID, activity or command argument is accepted. The examples require an interactive caller
that waits for each acknowledgement; do not send them as an unattended batch.

`STOP` uses the existing lifecycle helper: it backgrounds the target with `KEYCODE_HOME`
and uses `am kill app.wardpulse`, never force-stop. One overall 15-second deadline includes
timer rearming, both-role prechecks, the action, waiting and final reconciliation. A surviving
old process, replacement start, raced inventory or deadline overshoot fails the session.
An initially absent app is allowed and claims no old death. Otherwise, all sampled old
PID/start-tick identities must retire with stable UID-wide absence. A KILL event is only
pending intent; it establishes neither death nor absence. The ledger retains that ownership
until an ordered DEATH or reconciled stable absence, guards PID reuse and late DEATH, and
retains transient START/KILL/DEATH evidence without inventing unsampled start ticks.

`LAUNCH` requires absence, then normally starts the fixed phone `app.wardpulse/.MainActivity`
or Wear `app.wardpulse/app.wardpulse.wear.MainActivity` through the existing helper. It
requires a successful COLD activity result, observed START events, a unique new main
process and genuine new PID/start-tick identity; an already-running app (HOT) fails.
Launch retains its existing 15-second helper
bound within the request deadline. Neither lifecycle acknowledgement establishes quiet,
work preservation, saved-summary retention or product acceptance. All drained publications
and receipts remain evidence, including late events and identical-data sends.

When the existing composite launch-result guard rejects a bounded result, its existing
`FAILED`/`HOLD` reason includes finite ASCII diagnostics from that same capture (at most
16 KiB). `StatusCount` and `LaunchStateCount` are `MISSING`, `ONE` or `MULTIPLE`, counting
only lines anchored at `Status:` and `LaunchState:`. `Status` is `OK` only for a single
exact `Status: ok` line; otherwise it is `NON_OK`. For a single exact `LaunchState: <token>`
line, `LaunchState` recognizes `COLD`, `WARM`, `HOT` and `RELAUNCH`. The exact complete
`LaunchState: UNKNOWN (0)` line maps to `UNKNOWN`; missing, multiple or other
values/whitespace produce `OTHER`. Other unknown numeric formatter values stay opaque.

Independent `0`/`1` warning flags are `SWITCHES_CANCELED`, `INTENT_DELIVERED_TO_TOP`,
`RETURN_INTENT_TO_CALLER`, `TASK_TO_FRONT` and `OTHER_WARNING`. The first four recognize
the exact complete Android warning lines for a kept current activity, delivery to the
running top-most instance, handling by the caller and bringing the current task forward.
For `SWITCHES_CANCELED`, the exact line is
`Warning: Activity not started because the  current activity is being kept for the user.`
with two ordinary spaces between `the` and `current`.
Any other line containing `Warning:` sets `OTHER_WARNING`. `ERROR` flags any `Error:`
substring and `EXCEPTION` flags any `Exception` substring. For subsequent bounded calls,
zero or one whole-line byte-exact
`Warning: Activity not started, its current task has been brought to the front`
is permitted only with exactly one `Status: ok` and exactly one `LaunchState: COLD`.
Duplicate canonical warnings, every other warning (including `OTHER_WARNING`), error or
exception, altered text, whitespace violations and field-cardinality violations still
reject the launch. Acceptance only permits continuation to the existing lifecycle checks
before ACK; task reuse proves neither HOT nor sufficient restart evidence. Command failures and
results rejected by the existing size/control check retain their existing fixed reasons;
an unavailable parser diagnostic uses `DIAGNOSTIC_UNAVAILABLE`. No raw body, value,
component, Intent or environment is emitted by these diagnostics.

These diagnostics localize a subsequent bounded actual call. Historical composite launch
evidence remains `UNKNOWN`; the classifications establish no WARM/HOT behavior, lifecycle
proof or product acceptance, and do not authorize retry-until-green.
Historical held outcomes, unknown causes and retained evidence remain unchanged.

`CLOSE` performs the boundary checks plus final acknowledged closing drains. It then
retires the owned logcat producers, complete projectors and deadline timer, removes owned
temporary pipes/records, and emits `COMPLETE <id> OBSERVATION_ONLY` only after successful
retirement and cleanup. Require that terminal record **and a zero exit status** for
completion. A finite input file without `CLOSE` fails; EOF never proves quiet.
A single `CLOSE 1` after readiness is sufficient for a session with no intermediate drains.

Deadline, handled-signal and EXIT failures use that same bounded retirement path. Its
guard and failure latch are persistent state initialized before traps are armed. A signal
before the guard is claimed completes retirement before exiting, even at the earliest
EXIT entry; once claimed, additional signals only latch failure. The guard precedes local
initialization, and signal handlers use only persistent state throughout retirement.
They cannot exit recursively or abandon cleanup. A signal during monitor/timer launch still
waits for every ownership entry to be registered before exit.
Timer arming then waits for that child's PID acknowledgement on a separate internal pipe,
written only after its cancellation handlers are installed. PID registration or liveness
alone is not readiness. The deadline read uses the remaining absolute phase budget;
the readiness wait must finish within that same budget. Before the next timer is launched,
the previous timer must be cancelled, proved absent and waited successfully, even for
immediately queued controls. Failed or expired readiness and abnormal cancellation use
the same failure cleanup and watchdog backstop.
Individual cleanup failures retain failure while the remaining retirement work continues.
Producer process-group absence is required before wait and retirement evidence; owned
pipes and records are retained whenever any monitor tree or timer remains unproved.
After timer absence is proved, owned scratch removal has the same two-second bound plus
one second to kill as stdout copies.
Expiry, signals and forced or unproved retirement keep a nonzero status, with bounded
`FAILED` delivery when stdout remains usable. A `COMPLETE` record without zero status
never establishes completion.

Output is a small line protocol (`id` is 0 during startup):

| Record | Meaning |
| --- | --- |
| `IDENTITY <id> <phase> <role> <avd> <serial> <geometry> <uid> <boot>` | Validated device/package binding; phone geometry is labelled `phone`. |
| `PROCESS <id> <phase> <role> <pid> <start-ticks> <name>` | Sanitized process identity sampled by the existing inventory path. |
| `RESULT <id> <phase> <role> <typed-event>` | Every drained projector record, before ledger normalization or `EVENTS` replacement. |
| `READY 0 OBSERVATION_ONLY` | Startup bindings, drains and reconciliation completed. |
| `ACK <id> DRAIN` | Both roles completed the requested boundary. |
| `ACK <id> STOP <PHONE\|WEAR>` | Fixed stop completed, including both-role reconciliation; initial absence claims no death. |
| `ACK <id> LAUNCH <PHONE\|WEAR>` | Fixed normal launch proved a new load and completed both-role reconciliation. |
| `RETIRED <id> retirement <role> <host-pid>` | Owned monitor exited, was waited and is absent. |
| `FAILED <id> <reason>` | Session failed; exit status is nonzero and no completion is valid. |
| `COMPLETE <id> OBSERVATION_ONLY` | Explicit close and retirement completed; this is observation only. |

Phases are `startup`, `input`, `operation`, `closing` and `retirement`. Typed events retain
`START <pid>`, `KILL <pid>`, `DEATH <pid>`, `PUBLICATION`, `RECEIPT`, `GAP`, and numeric
`MARK wp-gate-<pid>-<sequence>-<tick>` boundaries. Acknowledged explicit projector closure
uses `CLOSE wp-gate-<pid>-0-<uid>`. Only that exact owned marker permits normal projector
termination; unrequested EOF still emits `GAP`. No GAP is filtered, and no lifecycle or
sync event is hidden by normalization. Failed startup/operations also retain their
available role-labelled results during retirement. A monitor's finite EOF cannot substitute
for its closing acknowledgement. Cleanup and retirement failures also emit `FAILED` when
stdout remains usable. If output is broken or its bound is exhausted, complete evidence
cannot be delivered and the session fails.

Startup has 60 seconds, each request at most 30 seconds (STOP has 15), each idle input wait
15 seconds and the whole session 180 seconds. Previous-timer retirement and new-timer
readiness consume the new phase's original budget without resetting its deadline;
nested waits and calls are clamped to existing deadlines. A deadline timer covers
blocked work as well as reads/writes;
an unresponsive shell has a further 20-second termination ceiling. ADB calls have at most
five seconds (clamped to the current phase deadline), followed by at most one second to
kill. Stdout copies have two seconds plus one second to kill. Monitor retirement has four
seconds before forced termination makes the session fail, then one second to prove absence
after KILL; exit statuses are collected only after child absence is proved. Timer retirement,
including rearming, allows four seconds for TERM and one second to prove absence after KILL;
forced or unproved retirement fails the session. Each input line has at most 16 characters;
NUL, CR, tabs, other controls, unknown commands, repeated/skipped/out-of-range
IDs and oversized lines fail. Each role retains the whole existing projector's 262,144-byte
ceiling; total typed output is bounded below 1 MiB, including terminal records. Events,
role guards, control-character checks, publication/receipt validation and loss detection
use the same complete projector as verification.

EOF, errors, signals, expiry, monitor loss, malformed controls, changing bindings or
unproved retirement produce a nonzero exit. Observation issues device metadata reads,
logcat reads, acknowledged `WardPulseGate` log markers and the fixed lifecycle actions above,
with owned host temporary pipes. Helper diagnostics go to stderr; stdout remains the typed
protocol, including sampled process identities. There is no observer restart, gap bridge,
keepalive or silent deadline extension. It does not access the work reader or read, back up,
inject or restore summaries. It does not invoke other app APIs, build/install/run suites,
read keys/private payloads, force-stop/reset/re-pair devices, change settings/jobs or accept
arbitrary device/process commands. Full paired acceptance, work preservation and
measurement access remain separate work.

## Prerequisites

- Bash 4.4 or newer, GNU `timeout` (including `--kill-after`), `sha256sum`, `mktemp`,
  `mkfifo`, Python 3 (standard library only), and the usual `awk`, `sort`, `sed`, `grep`,
  `tr`, `cut`, `wc` utilities.
- An existing Android SDK selected by `ANDROID_HOME`, or `ANDROID_SDK_ROOT` when
  `ANDROID_HOME` is unset. Its `platform-tools/adb` must be executable.
- Executable Flutter on `PATH`, or its executable path in `WARDPULSE_FLUTTER_BIN`.
  The Android build tools, JDK and dependencies needed by Flutter and the Wear Gradle
  wrapper must already be usable; builds may need the host's ordinary network access.
- Existing `javac` **21** on `PATH`, SDK `platforms/android-36/android.jar`, and executable
  `build-tools/36.0.0/d8` and `aapt2`. The reader is compiled for Java 17/API36 in an owned
  host temporary directory; no SDK, Java, SQLite binary or dependency is installed.
- The online canonical AVDs `wardpulse_phone_play_api36` (phone) and
  `wardpulse_wear_round_api36_1` (watch), already paired, with both debug apps installed.
  Existing packages are necessary to prove data-preserving **updates**.
- ADB shell access to live AVD names, build characteristics, process start times,
  redacted logcat events, installed-APK hashes, package update times, and bounded
  native scheduling metadata. Both installed debug packages must support `run-as`;
  the phone must support standalone `app_process` DEX execution under its existing UID.
  The Wear package must support `stat` for its saved summary. Unavailable or raced
  evidence is a HOLD.
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
Package UID discovery validates a bounded inventory and selects exactly `app.wardpulse`;
legitimate substring siblings such as watchface packages are retained during validation.
Missing, duplicate, malformed or oversized UID evidence fails without choosing a first match.

All of the following are required for a future Pass:

1. Preservation evidence before disruptive stages, reconciled afterward. Unknown work
   correspondence, cancellation, missing specs or unexplained rescheduling is a HOLD.
2. A successful current `flutter build apk --debug`, the **entire** Wear
   `connectedDebugAndroidTest` with `--rerun-tasks`, and both successful `adb install -r`
   updates. The two output APKs are removed before building so stale artifacts cannot
   satisfy this stage.
   Each update must advance the installed package timestamp and match the current APK's
   SHA-256. Update process deaths must agree with observed lifecycle events.
   The installed-equivalent phone APK must establish merged-component/process coverage;
   shared/isolated/uncovered processes HOLD. Every process under the package UID is
   observed, and installed sender identity is rechecked before completion.
3. Background/`am kill` handling for both apps before delivery. Record every observed
   app PID and start identity, reconcile death events and absence, then prove new launch
   identities. Initial absence is reported as absence. Foreground `am kill` exit status
   and a HOT bring-to-front are insufficient evidence of death or restart.
4. A new phone INFO `WardPulseSync` **`Watch summary queued.`** publication after the
   measurement boundary, and a fresh Wear INFO **`Watch summary received.`** callback
   after that boundary, independently followed by a stable saved-summary hash and metadata.
   The phone event follows `putDataItem` success; the Wear event follows valid `TYPE_CHANGED`
   decoding/save. Both survive launch/death/install reconciliation as distinct event types;
   only START/DEATH records enter lifecycle set comparisons. Expected initial publication
   is evidence, never a gap or a substitute for the Wear callback. Old logs, invalid-summary
   warnings and matching saved data cannot satisfy delivery.
5. Verified phone separation followed by actual observed Wear death and a new Wear
   process. Equal saved-summary hashes and unchanged file metadata must persist through
   that transition and ten further seconds. The phone must stay absent with no new
   start/death events or fresh app publication; no receipt is allowed, including
   identical-byte delivery. The standalone observer has a separate, verified identity and
   lifetime; it never counts as a UI/worker process, sender death or phone separation.
   Unexpected background/replacement processes, PID reuse, raced reads, summary writes,
   lost monitor boundaries, slow observations or expired deadlines invalidate retention.
6. Stable final persistence and work-preservation evidence. Only then may the script print
   Pass, successful phone/watch role/serial identification and the final summary hash.

### Conditional current-summary publication

The existing `wait_for_summary` in [run.sh](run.sh) retains the prelaunch measurement
boundaries and separate real publication/receipt flags. When no fresh phone publication
has been observed, it qualifies rendered Dashboard data, opens Settings through its
visible navigation destination, confirms **Mock data is off without changing it**, and
seeks **Diagnostics → Send to watch → Sync** by bounded upward content scrolling. There
is at most one Sync attempt. Publication observed before navigation or at the final
monitored boundary skips the action; the script never retries Sync. After UI acquisition
and parsing, event, process and deadline qualification must finish successfully. Both
accepted events then complete delivery immediately, including just before expiry, without
further targeting, phone barriers or input-only freshness checks. Publication alone moves
to distinct-receipt observation and suppresses further targeting and input. The retained
pre-input boundary also recognizes completion immediately. Encountered process, monitor
and deadline failures still HOLD, even if both event flags are set. A clipped row/control
is revealed only far enough for usable bounds, allowing for Flutter's drag threshold at the
observed display density; seeking stops when the control is usable.

This reaches `_onSettingsSyncWatch` in
[ward_pulse_app.dart](../../apps/phone_flutter/lib/app/ward_pulse_app.dart), which passes
owned current data through the existing repository currentness, revision and identity
guards without calling `repository.load`. It does not force a provider fetch, change
Mock/preferences/selections, inject a summary, cancel work or use a private app caller.
A rendered timestamp qualifies the Dashboard route; it does not replace those app guards.

Every input requires fresh boot/UID/PID/start identity, the exact foreground package and
MainActivity, stable native window frames, the selected page, hierarchy semantics and
actual viewport bounds. Labels match both text and content descriptions, including
merged multiline semantics. Navigation and Sync require unique enabled visible controls;
Sync must belong to its Send to watch row or merged Diagnostics card in the Settings list;
the card must own the complete Diagnostics label group and its sole action. Scrolling uses
that qualified list's viewport and moves content upward, avoiding pull-to-refresh. Each scroll
requires a new capture. Wrong/ambiguous hosts or pages, disabled controls, unknown bounds and
unresolved obstructions HOLD before input. UI evidence must also be fewer than five clock
ticks old, counted from the start of its hierarchy capture, once qualification completes and
again immediately before each tap or scroll. An older snapshot is discarded without input;
its target is never reused or re-stamped. The next pass requalifies from a new complete
capture under the same original deadline, and a discarded scroll consumes no scrolling bound.
Persistent staleness therefore ends in the original-deadline HOLD without input. Five ticks
is a deliberate engineering bound, not Android timing guidance. Its tradeoff is that input
may act on a capture up to four integral ticks old, rather than discarding every capture
whose acquisition, qualification and pre-input work cross three or four tick boundaries. It
claims neither an atomic native snapshot nor a passing native gate, and it is not raised
further to obtain one. Retention's separate three-tick gap rule is unchanged. Native
frames from the full WindowManager service bracket the hierarchy capture; per-window records
are qualified separately from global/display records. Every surfaced visible window other
than the focused host is an obstruction, whatever its type. A tap uses the center of its hit
area: the semantic box less only a fringe, where an obstruction spans one whole side and
stops short of the box's would-be center. Any other overlap stays in the hit area and blocks
the tap. The hit area needs at least 24 pixels in each dimension and only places the tap; it
establishes no uniqueness, ownership, association or visibility. Frame/display containment
and unrelated-control checks still use the whole semantic box, and scroll strips and the
Mock proof remain whole-box. Raw UI/native captures stay in owned scratch, and owned device
hierarchy staging is removed during cleanup. Python 3 parses these bounded observations
using its standard library; no new package is installed.

Readiness, navigation, scrolling, stale-evidence requalification, Sync and both event
observations consume the **same original 30-second delivery deadline**, including
subprocess kill grace. The prospective 300-second native-work exclusion and
observation-age margin remain unchanged; due or unknown work still HOLDs before delivery.
All 51 connected cases, canonical cohort, normal builds, preserving `install -r`,
lifecycle/cold-load/quiet handoffs, UID coverage, logical/native work, exact selections and
protected Push/Legacy identities remain required.

Delivery HOLD diagnostics run before cleanup, using retained parent-shell facts rather
than new reads after expiry: `FRESH_PUBLICATION` and `FRESH_RECEIPT` separately, finite
phase, elapsed/remaining time, process-proof status, Sync-attempt flag, the number of stale
UI snapshots discarded before input (`stale_ui_snapshots`) and each role's last completed
event boundary (`cursor@tick`). A nonzero count keeps persistent staleness identifiable
behind the deadline HOLD; discard records below attribute each aged capture. Coverage is
`CompleteThroughBoundary`, `Incomplete` for an unfinished drain, or `Unknown` when no
boundary is available. Completion through a recorded boundary is not coverage after it. A
zero flag means no accepted observation; missing/incomplete coverage and causal absence
remain Unknown. Settings result text, equal payloads and saved-summary hashes establish
neither DataClient success nor a Wear `TYPE_CHANGED` receipt. Both distinct real events
remain mandatory. Historical HOLD causes remain undiagnosed; these changes claim no
HOST/device or finding6 acceptance. Failed delivery-diagnostic writes preserve the failure
and let owned cleanup continue. The delivery report, a delivery HOLD reason and owned
staging-removal failure reports each use a bounded, best-effort write, so a closed or full
undrained stderr cannot stall staging cleanup or monitor retirement. A failed removal
still fails the run and is never reported as removed.

Each discarded snapshot keeps one closed `Delivery UI discard:` record in parent-shell
memory; only the delivery report writes these records. A record names the host
PID/invocation number, route (`dashboard`, `mock` or `sync`) and check site
(`after_qualification`, `before_tap` or `before_scroll`). It then gives the original capture
tick and the durations of `acquisition` (hierarchy and NativeAfter reads), `parse` (target
parser), `qualification` (both roles' event/process proof and its deadline check) and
`pre_input` (the phone event barrier, process proof and deadline check before a tap or
scroll), followed by the checking tick, the computed age and the original deadline's
remaining ticks at that check. All use the integral `SECONDS` clock of the age check: each
duration counts the tick boundaries its stage crossed, so a short stage reads 0 or 1, and a
discard's durations sum to its age. An unreached stage, such as `pre_input` for a
post-qualification discard, remains `Unknown`. A HOLD or other failing exit during a UI
attempt, whose route is then the reported phase, adds one `Delivery UI attempt:` line with
the same facts so far (`captured=Unknown` before the capture tick), its `unfinished` stage,
that stage's start tick and the remaining ticks there. That stage is `preparation` before
the capture, a measured stage, or `input` after a passing input check, and it never
receives a duration. An attempt publishes its route only after its new invocation, facts
and stage, and one assignment command publishes each capture tick, stage change or discard.
Bash never runs a signal trap inside one assignment command, so a report after an
interrupting signal never pairs a route with another attempt's facts, or a closed duration
with that unfinished stage. Each discard needs its own capture at least five ticks old, so
the original budget bounds these records to six. Retention adds no write, pacing or retry
inside the delivery loop and changes no predicate, deadline, recapture or input. A later
complete ordinary HOST gate passed all 51 Wear cases, both preserving updates and the quiet
handoff, then held with `Delivery deadline expired.` after six discarded snapshots, without
accepted publication, receipt or Sync attempt. Its captures, routes, check sites, ages and
stage durations remain Unknown. These records are prospective: they neither explain that
HOLD nor establish runtime freshness acceptance, and a fresh complete ordinary HOST gate
remains required.

UI qualification also retains one failure record on stderr before cleanup. Literal guard
identities distinguish predicate rejection from acquisition, parse and subprocess failures.
The record includes the finite UI phase, host PID/invocation number, read and producer
identity (with producer PID when measured), actual available exit/timeout status and an
allowlisted error class. Parser facts include measured presence/unique-match counts,
owner and semantic matches, validity booleans and available target, tap hit-area,
viewport and blocking rectangles. A tap's target is its whole semantic box, while its
obstruction overlap count and blocking window refer to its hit area; unmeasured facts remain
`Unknown`. Control facts name their measured scope; rejecting a disabled Settings list
cannot retain the navigation control's enabled state. UID acquisition retains the ADB
exit/timeout status, while bounded UID inventory rejection is a separate predicate failure.
The parser keeps stdout action-only. Records contain no raw capture, arbitrary
label or exception payload, are capped at 2,048 detail characters and use a bounded,
best-effort writer. Reporting failure neither retries input nor prevents owned staging
removal and monitor retirement.

ADB calls have five-second deadlines; discovery has a 30-second deadline. Flutter has
900 seconds, full Wear instrumentation 1,200 seconds, and each install 90 seconds.
Lifecycle observation loops have 15-second deadlines in addition to bounded background,
kill and launch commands; fresh delivery has 30 seconds and summary stability 15 seconds.
Retention has an overall 60-second deadline and rejects observation
gaps of three clock ticks or more (conservatively rounding elapsed time). Subprocess
failures propagate. Owned log readers have a finite lifetime and are retired on exit;
temporary pipes and sanitized event records are removed. Reader compilation and DEX
conversion each have 30 seconds. Each observer has a six-second internal watchdog, a
seven-second ADB timeout, a four-second observation budget and an eight-second host
protocol deadline. Owned device staging is removed before completion; cleanup failures
cannot produce Pass. Whenever `timeout` is available, an ordinary or delivery HOLD writes
its reason with the bounded, best-effort writer of the delivery diagnostics, so a closed or
full undrained stderr can neither keep that failure from reaching owned cleanup nor change
its status. Cleanup's reader-retirement and UID-reconciliation HOLDs use the same writer
after their unchanged eight-second loops: unproved retirement still retains device staging,
fails the run and reaches monitor and scratch retirement.
Without `timeout`, a run fails before any owned cleanup exists and prints its HOLD reason
directly.
No subprocess failure can be overridden to obtain Pass.

## Preservation and bounded work evidence

The script does not force-stop WardPulse, clear app data, cancel/fabricate work, alter
connectivity, cadence, credentials, connections, recovery, Mock mode, selections, summaries
or pairing. It uses backgrounding and bounded `am kill`; an unkillable process causes HOLD.
The narrow unrelated Wear SystemUI recovery exception remains in
[Android toolchain guidance](../../docs/ANDROID_TOOLCHAIN.md#preserving-emulator-state).
It is not invoked here and does not authorize app force-stops.

`HeadlessProviderSync` in
[headless_provider_sync.dart](../../apps/phone_flutter/lib/sync/headless_provider_sync.dart)
declares `wardpulse.providerSync` / `providerSync`: connected-network periodic work using
UPDATE, with the existing cadence floored at 15 minutes. `WorkmanagerRecoveryWakeScheduler`
in [recovery_wake.dart](../../apps/phone_flutter/lib/sync/recovery_wake.dart) declares
`wardpulse.recoveryWake` / `recoveryWake`: connected-network one-off work using REPLACE
and a delay derived from the next reset. These source policies remain requirements.
A database sample establishes neither historical enqueue policy, the original reset time,
nor every transition between samples. Initial delay is a stored spec, not a countdown.

[WorkSnapshot.java](WorkSnapshot.java), through `snapshot` and `project`, is the single
fixed-query metadata reader. It runs through existing `run-as app.wardpulse` and installed
`app_process`, without an application Context, Activity, Room, WorkManager, worker,
broadcast, diagnostic job or app hook. Only its compiled classes/DEX are staged, in bounded
owned temporary host storage and a newly allocated `/data/local/tmp/wardpulse-sync.*`
directory. No artifacts enter existing application storage. The staged DEX is read-only.
DEX loading, execution security policy and UID compatibility must succeed on HOST; their
availability is not assumed from the compiler's presence. The GO stdin handshake is
intentional; all ordinary ADB shell calls use `-n`, including the discovery inventory loop,
so they cannot consume later inventory records.

The reader resolves only `no_backup/androidx.work.workdb` or the historical
`databases/androidx.work.workdb`, rejecting missing, ambiguous or redirected locations.
It binds the installed APK's WorkManager **2.11.2** marker, generated Room schema **24**
current identity `08b926448d86528e697981ddd30459f7`, required column types, and that version's
state/network converters (ENQUEUED=0, RUNNING=1, SUCCEEDED=2, FAILED=3, BLOCKED=4,
CANCELLED=5; CONNECTED=1; exponential/linear backoff=0/1). The generated legacy identity
`149fd8ad55885d3fe3549a37a0163243` is not accepted as an alternative. The requested
2.10.2 dependency or a cached artifact does not establish the resolved/installed tuple;
HOST must reconcile the resolved 2.11.2 generated schema/converters with the installed
APK marker, current identity, columns and actual values. Unknown versions/schemas HOLD. It joins
only the two logical WorkNames through WorkSpec to SystemIdInfo, matching both ID and
current generation; an older mapping's job ID never substitutes for the current mapping.
WorkManager 2.11.2's SystemIdInfo foreign key references WorkSpec by ID alone. UPDATE can
legitimately retain an older-generation mapping. Every mapping still requires a canonical
work ID and integer generation/job metadata in 0..2147483647; duplicate mapping keys or job
IDs, invalid referenced generations and ambiguous WorkSpec IDs HOLD. A genuinely missing
work ID remains `ORPHAN_SYSTEM_ID`; a future mapping generation gives `FUTURE_SYSTEM_ID`.
At most 32 work rows and 12 KiB of metadata leave the reader. Allowed fields are
logical name, opaque ID, worker, state, interval/flex, initial delay, network/constraint
flags, generation/job ID, enqueue/schedule, attempt/period, backoff, override and stop
markers, including schema24's nullable `backoff_on_system_interruptions` (null=-1,
false=0, true=1), which must remain unchanged for a retained work identity.
Constraint blobs yield only absence flags; their contents are never exported.
No input/output/progress, arbitrary tags, accounts, credentials, preferences or whole rows
are read/exported. All exceptions become fixed, sanitized HOLD categories.

Successful evidence has exactly one `SCHEMA`, `SQLITE`, `TIME`, then `MAPPINGS` record,
followed by the `WORK` records and the identity-bound `END`. `MAPPINGS total missing current
older future` contains five canonical decimal integers in 0..2147483647. The four classes
must sum to the total; missing and future must be zero for acceptance. All counts come from
the same read-only transaction as the generation-matched projection. The consumer requires
the current count to equal the number of projected job mappings and rejects missing,
duplicate, misplaced, unknown, malformed, inconsistent or overflowing evidence.

After a safely completed snapshot rejected for missing/future mappings, the reader emits
only `MAPPINGS` followed by the corresponding `HOLD` (missing takes precedence), exits 1
and emits no `END`. After reader retirement and surrounding process/event checks, the
consumer validates and prints this as **rejected** count-only evidence, then HOLDs without
advancing the accepted pair. Invalid metadata or failed safety checks emit HOLD without
counts. Counts never certify quietness or establish the cause of a prior device failure;
HOST must classify the actual current rows through this guarded path.

The standard-library regressions in [test_work_snapshot.py](test_work_snapshot.py) execute
the production fixed SQL on neutral in-memory metadata and the production shell/AWK
consumer. They protect the older/missing distinction, current-generation job selection,
invalid/ambiguous/mixed metadata and closed count protocol, including rejection diagnostics.
They also execute the production inventory functions and device-shell body against controlled
process lists, start reads and absence results. Cases cover reader disappearance between
listing and lookup and across reconciliation boundaries, strict pre-GO reads, real-app
disappearance, PID reuse, unknown identities (including another process with the reader
name), reappearance, malformed/oversized inventories and boot/UID guards. Representative
rejections (an acquisition timeout with its caller phase, row validation, an app stat read in
the second traversal, an invalid start value, a changed reader start, a new identity between
list boundaries, boot continuity and the expected boot) must each exit nonzero with empty
stdout and retain only their own closed record, without injected rows, stat records or boot
identities. One rejected pre-update sample inside `update_install` must also reach production
cleanup through the sampler's ordinary HOLD and the outer update HOLD while a full stderr
pipe stays open but undrained: reader staging removal, monitor kill/wait and scratch removal
precede its asserted status 1. Under that open full pipe, two production `work_snapshot`
failures also reach cleanup with their reader flags still set: unproved absence of the
handshake PID, and a pre-handshake reader HOLD that leaves a new app-UID identity. A
controlled clock ends each unchanged eight-second loop after one retry. Staging stays
retained; monitor kill/wait and scratch removal are asserted before the cleanup summary and
status 1. The expected predecessor assertion failure, where either HOLD is written directly,
is the missing monitor kill/wait after that loop. These controlled facts do not reproduce any
historical HOLD.
The enclosing reader path must still reject missing END, failed wrapper exit and unproved
retirement, including during the reader-released separation phase. These sequences need no
sleeps or timing retries. Run `python3 tools/test-phone-watch-sync/test_work_snapshot.py` to
print the suite duration. These cheap regressions provide no Java/DEX/device acceptance.

`DeliveryTests` also exercises the existing `wait_for_summary` entry with controlled clocks
and fake ADB/event effects: accepted rendered data without automatic publication requires
exactly one guarded Sync after scrolling and then both events; observed publication avoids
another action; rejected UI guards prevent input; neither/send-only/receipt-only timeouts
retain independent facts and the original deadline. Lost observations still HOLD with
incomplete coverage. Acquisition fakes distinguish full-service focus from the windows
subsection; a merged Diagnostics card must own Sync, and a nearby unrelated button is rejected.
The one-pixel-clipped reveal uses a high-density display; undersized fake swipes leave
content stationary, so successful scrolling must exceed the effective drag threshold.
These tests execute the owning shell functions and UI parser, with no new harness or devices.
A closed diagnostic stream must also leave owned cleanup and monitor retirement intact,
including the new UI rejection path and when UI staging removal fails. A full stderr pipe
left open but undrained must likewise let an expired delivery attempt both owned staging
removals, keep reader staging `failed` and retire the monitor with status 1. The controlled-clock
completion witness accepts events during UI qualification or the retained phone boundary,
finishes proof at tick 29 of the original 30-second budget and makes any unnecessary next
effect exhaust that budget. Adjacent publication-only and deadline-crossing cases protect
distinct receipt and strict qualification. An obstructed-target witness uses the owning
parser/wait and production cleanup, retaining only a trace outside removed scratch; a
separate UID acquisition-timeout case protects subprocess-status attribution. A full-width
window over only the Settings control's fringe still allows the guarded tap inside its
unobstructed interior and then the one Sync; the same window reaching the would-be center
HOLDs before input, recording both the semantic box and the selected hit area. The
`test_disabled_scroll_reports_its_own_control_facts` and
`test_uid_inventory_rejection_is_not_an_acquisition_failure` cases protect scoped control
facts and the distinction between invalid inventory and failed acquisition. Stale-evidence
fakes age evidence by five ticks, the first rejected age. One stale-evidence case ages the
first Mock proof capture during its qualification, then the qualified reveal scroll and Sync
tap at their pre-input boundaries. The Mock proof performs no input, so only the
post-qualification check can discard it. Each aged snapshot gives way to a new complete
capture without input, and delivery still completes with the one Sync inside the original
budget; a fake input probe flags any input made on aged evidence. When evidence ages before
every input, no input occurs and delivery HOLDs at the original deadline, reporting the
discarded-snapshot count. Two attribution cases read that report itself. The persistent
case retains five `before_tap` records, each with its own invocation and capture tick, five
ticks of pre-input aging and fewer remaining ticks, then names the sixth attempt's
unfinished `pre_input` stage without a duration. A window covering the revealed Sync
control ends the once-stale sequence with its own `target_unobstructed` record after two
discards: the Mock proof aged during acquisition and never reached pre-input, while the
reveal scroll aged before input. A third case sends one real TERM from a Bash `DEBUG`
trap, under function tracing, at the first command boundary where the attempt after the
first persistent discard has exposed its route. That is where a signal can land between
publication commands, and the report there reads every transition published before the
route. The signal trap's exit status 143 reaches the failing EXIT cleanup, which removes
owned staging, retires the monitor and reports once without a HOLD. The report pairs the
second attempt's route only with its own invocation, Unknown facts and unfinished
`preparation`, while the discard keeps its closed record. That one boundary covers the
discard and attempt-reset publications. No case interrupts inside the capture or
stage-change publications, so coherence there rests on single-command publication and Bash
trap semantics. An age-boundary case ages one capture once, after every earlier check has
accepted it: the first Dashboard capture during acquisition, or qualified evidence before
the Settings tap or the second reveal scroll. At four ticks, that check accepts the capture
and the input names its original capture tick, with no discard. At five, that check
discards it with its own site record and no input uses it; replacement evidence still
reaches the one Sync before the original-deadline HOLD that withheld events cause.
Controlled ticks exercise only this representation and reproduce no HOST timing.

After the entire owning run is DONE, its CLI exits, known processes retire and separate
fresh idle is established, HOST runs the full owning regressions above and the causal
assertion witnesses against old and fixed source. The only
source override is `WARDPULSE_SYNC_TEST_SOURCE`; it defaults to the sibling `run.sh` and
prints the selected source path and SHA256. The completion and rejected-guard witnesses
use the unchanged Source05 artifact preserved before correction at
`LOCAL_ARTIFACTS/paired-sync-witness/source05-49bf593b-run.sh`, SHA256
`49bf593bae4a80f1151fa01a4515c5a7ff087fd3f863d85dfae99e133bc12bee`:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/source05-49bf593b-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/source05-49bf593b-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_qualified_delivery_completes_before_expiry_without_more_effects DeliveryTests.test_obstructed_target_retains_closed_facts_through_cleanup
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_qualified_delivery_completes_before_expiry_without_more_effects DeliveryTests.test_obstructed_target_retains_closed_facts_through_cleanup
```

Keep the exact test file, witness bodies and arguments unchanged between each old/fixed
execution, and retain test/source digests, both outputs and actual exit statuses. Expected
Source05 assertion failures are nonzero delivery status after accepted qualification and a
missing measured UI failure record. These are expected outcomes, not executed proof.

Keep the original common-entry publication witness separate, with its original baseline:

```sh
mkdir -p LOCAL_ARTIFACTS/paired-sync-witness
git show 75fd9dadfe20c6413ae678426462fff1ad84156f:tools/test-phone-watch-sync/run.sh > LOCAL_ARTIFACTS/paired-sync-witness/old-run.sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/old-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/old-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_cached_data_gets_one_sync_then_distinct_events
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_cached_data_gets_one_sync_then_distinct_events
```

The baseline is the exact `run.sh` from commit
`75fd9dadfe20c6413ae678426462fff1ad84156f`, SHA256
`97a35454dfadea160421db5b675daf405fa38984b2c4c5b04925b47ba46cf6b5`.
Verify that digest before comparison and retain both command outputs and exit statuses.
The expected old-source assertion is zero Sync actions versus one required; the fixed
source must satisfy the identical assertions and exit zero. Missing helpers, setup/parser
errors and historical HOLDs do not establish assertion RED. No old behavior is repaired
or adapted for the witness.

The fringe hit-area correction has its own measured predecessor, the unchanged
pre-correction `run.sh` preserved at
`LOCAL_ARTIFACTS/paired-sync-witness/fringe-5cdc024a-run.sh`, SHA256
`5cdc024aaafc8fe3c630edaf190fcdfdaf02209e9214feec2a25ad9fe169956d`. Neither baseline above
proves this case. Run both fringe cases under the same digest, output and exit-status rules:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/fringe-5cdc024a-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/fringe-5cdc024a-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_fringe_overlap_taps_the_unobstructed_interior DeliveryTests.test_overlap_reaching_the_would_be_center_holds_before_input
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_fringe_overlap_taps_the_unobstructed_interior DeliveryTests.test_overlap_reaching_the_would_be_center_holds_before_input
```

Expected predecessor assertion failures are no guarded tap for the fringe positive, whose
record names `target_unobstructed`, and only the missing hit-area fact for the negative,
which still HOLDs before input. The fixed source must pass both and exit zero. These are
expected outcomes, not executed proof.

The stale-evidence requalification has its own measured predecessor, the unchanged
staged-candidate `run.sh` preserved before this correction at
`LOCAL_ARTIFACTS/paired-sync-witness/stale-d4c16035-run.sh`, SHA256
`d4c160353c4a8a90e68f1afa450625942aaff13ab83e8f38a6b4790345e33a7c`. None of the baselines
above proves this case. Run both stale-evidence cases under the same digest, output and
exit-status rules:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/stale-d4c16035-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/stale-d4c16035-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_stale_evidence_requalifies_from_a_new_complete_capture DeliveryTests.test_persistent_stale_evidence_holds_without_input_at_the_original_deadline
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_stale_evidence_requalifies_from_a_new_complete_capture DeliveryTests.test_persistent_stale_evidence_holds_without_input_at_the_original_deadline
```

The first-stale-then-fresh case is the causal witness. Its expected predecessor assertion
failure is zero Sync actions versus one required, because the predecessor HOLDs at the
first aged snapshot. The persistent case's no-input assertions hold on both sources; its
expected predecessor assertion failure is the original-deadline expectation, since the
predecessor HOLDs at its first aged snapshot instead of requalifying until that deadline.
The fixed source must pass both and exit zero. These are expected outcomes, not executed
proof. The controlled clocks do not reconstruct the retained HOST HOLD, whose target, hit
area, captured tick and firing age check remain Unknown.

The open-backpressure liveness correction is a separate check, not one of the witness
families above. Its predecessor is the unchanged candidate `run.sh` preserved before the
correction at `LOCAL_ARTIFACTS/paired-sync-witness/bounded-report-e9eed4e7-run.sh`, SHA256
`e9eed4e7503e374b009be8f480b0468174ab40fc47f1936459ecc2d9e3bce423`. Run it under the same
digest, output and exit-status rules:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/bounded-report-e9eed4e7-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/bounded-report-e9eed4e7-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_undrained_stderr_cannot_stall_failed_delivery_cleanup
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_undrained_stderr_cannot_stall_failed_delivery_cleanup
```

The expected predecessor assertion failure is a missing delivery UI staging removal attempt
in an empty trace: its first unbounded delivery-report write blocks on the full pipe before
cleanup starts, until the test's five-second subprocess bound ends that run. Cleanup effects
are asserted before the exit status, so the bound alone cannot supply this failure. The
fixed source must pass and exit zero. These are expected outcomes, not executed proof.

The ordinary process-rejection liveness correction is another separate check. Its
predecessor is the unchanged candidate `run.sh` preserved before the correction at
`LOCAL_ARTIFACTS/paired-sync-witness/ordinary-process-bbcfadd0-run.sh`, SHA256
`bbcfadd0956904a78056144cabf58cf8d7497714b7533d023bcdd1f82b250334`. None of the baselines
above proves this case. Run it under the same digest, output and exit-status rules:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/ordinary-process-bbcfadd0-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/ordinary-process-bbcfadd0-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py InventoryTests.test_undrained_stderr_cannot_stall_process_rejection_cleanup
python3 tools/test-phone-watch-sync/test_work_snapshot.py InventoryTests.test_undrained_stderr_cannot_stall_process_rejection_cleanup
```

The expected predecessor assertion failure is a missing reader staging removal attempt
after exactly one rejected sample. Its bounded `Process identity:` write ends, but the
sampler's unbounded ordinary HOLD write blocks on the full pipe before the outer update
HOLD and cleanup, until the five-second subprocess bound ends that run; closing the pipe
then ends the blocked subshell. Cleanup effects are asserted before the exit status, so
the bound alone cannot supply this failure, and a missing or repeated sample, an
unexpected effect or a Python error is a setup failure instead. The fixed source must pass
and exit zero. These are expected outcomes, not executed proof.

The stale-discard attribution has its own measured predecessor, the unchanged candidate
`run.sh` preserved before this correction at
`LOCAL_ARTIFACTS/paired-sync-witness/delivery-attribution-934a7784-run.sh`, SHA256
`934a778446781c10e331b62bb03bdbb915c12f6aca522dfac830f4294741ac66`. None of the baselines
above proves this case. Run both attribution cases under the same digest, output and
exit-status rules:

```sh
sha256sum LOCAL_ARTIFACTS/paired-sync-witness/delivery-attribution-934a7784-run.sh
WARDPULSE_SYNC_TEST_SOURCE="$PWD/LOCAL_ARTIFACTS/paired-sync-witness/delivery-attribution-934a7784-run.sh" python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_persistent_stale_discards_retain_each_capture_and_the_unfinished_stage DeliveryTests.test_stale_discards_retain_their_check_site_and_aged_stage
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_persistent_stale_discards_retain_each_capture_and_the_unfinished_stage DeliveryTests.test_stale_discards_retain_their_check_site_and_aged_stage
```

Both sources reach the same deadline HOLD after five discards, and the same
`target_unobstructed` rejection after two, without a Sync. The expected predecessor
assertion failures are only the missing `Delivery UI discard:` records: zero versus five,
and zero versus two. A missing helper, setup error or subprocess bound is a setup failure
instead. The fixed source must pass both and exit zero. These are expected outcomes, not
executed proof, and neither case reconstructs the six historical discards.

The five-tick UI age bound has its own measured predecessor, the unchanged pre-revision
`run.sh` blob `7e0e8615913177969d428b34bfab2fd60e69c441`, SHA256
`cf7d43a9da521425c19a1073403d64a25859a24b4587c901a94f6fc4c4089d50`, which applies a
three-tick bound at the same checks. None of the baselines above proves this case. The
existing override reads that blob once from standard input, so no baseline copy is written.
Run it under the same digest, output and exit-status rules:

```sh
git cat-file blob 7e0e8615913177969d428b34bfab2fd60e69c441 | sha256sum
git cat-file blob 7e0e8615913177969d428b34bfab2fd60e69c441 | WARDPULSE_SYNC_TEST_SOURCE=/dev/stdin python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_each_age_check_accepts_four_ticks_and_discards_five
python3 tools/test-phone-watch-sync/test_work_snapshot.py DeliveryTests.test_each_age_check_accepts_four_ticks_and_discards_five
```

The expected predecessor assertion failures are only the three age-4 subtests' missing input
on the original capture: each check discards that capture and a replacement receives the
input. The age-5 subtests pass on both sources. A missing helper, setup error, wording
difference or subprocess bound is a setup failure instead. The fixed source must pass and
exit zero. These are expected outcomes, not executed proof.

HOST must subsequently run complete ordinary `just test-phone-watch-sync` with the existing
preservation and cleanup contracts; regressions and Native checks alone do not establish
paired acceptance. These executions remain pending until actual HOST evidence exists.

The projection uses explicit `SQLiteDatabase.OPEN_READONLY | NO_LOCALIZED_COLLATORS` with a
throwing, nondeleting corruption handler and a short `beginTransactionReadOnly` transaction.
It never deliberately creates/edits/deletes database or sidecar files, upgrades, migrates,
repairs, checkpoints, changes journal mode, disables locking, asserts immutability,
copies/exports a database or retries writable. The sole permitted incidental writes are
SQLite's bounded automatic SHM reader coordination, index initialization/reconstruction
and read marks. This includes first-reader work after the phone app dies; the reader
never requires keeping or relaunching the app to open its observer. **Read-only flags
do not by themselves prove safe WAL behavior or zero filesystem effects.** The opening path
first holds a nonblocking shared `FileChannel` lock over SQLite's default Unix VFS lock
bytes (PENDING, RESERVED and the complete SHARED range), using one retained read-only
`ParcelFileDescriptor`. This excludes rollback RESERVED writers and EXCLUSIVE journal-mode
changes before inspecting the header or opening SQLite. A conflicting main-file lock causes HOLD; the
reader does not wait/retry or alter scheduling to obtain the lock. Header 1/1 requires
rollback/delete mode without journal/WAL/SHM sidecars. Header 2/2 admits WAL only with
both existing regular, app-owned, canonical WAL and SHM sidecars, opened read-only and
bound by descriptor/inode identity. Missing/redirected/oversized sidecars, a rollback
journal or unsupported header/mode gives a sanitized HOLD. The main file is bounded at
64 MiB, WAL at 64 MiB and SHM at 4 MiB. Sidecar contents are not exported.

`requireStableJournalMode` reads at most 4 KiB from **only that owned descriptor's**
`/proc/self/fdinfo` record. It binds kernel POSIX READ lock coverage, PID, inode and
read-only descriptor flags; Java `FileLock.isValid()` alone cannot establish lock survival.
The reader reuses the same descriptor for header reads: closing an additional descriptor
for that inode would release all of this process's POSIX locks. Extra main/WAL/SHM
descriptors remain open until SQLite has ended its transaction and closed, so their
closure cannot release SQLite's locks during the read. The reviewed Android16
`SQLiteConnection.open` path skips journal/sync/checkpoint configuration for `OPEN_READONLY`,
and `NO_LOCALIZED_COLLATORS` skips locale/metadata queries before BEGIN.
Kernel main-file coverage is required before and after open,
after BEGIN and before the first pager read, and during the consistent read transaction.
SQLite's transient PENDING read unlock is allowed only after that first pager read;
RESERVED and the entire SHARED range must remain held. These locks exclude rollback
writers and journal conversion; **they do not exclude WAL writers**. The first pager read
inside the read-only transaction establishes the committed snapshot using SQLite's
ordinary WAL/SHM read and recovery locks. Every schema/value query uses that same
transaction. No further SQLite operation follows transaction end/close, where SQLite
may release same-process locks. File/sidecar identity is checked during the transaction
and after close. Concurrent commits/checkpoints and permitted SHM coordination can
change whole DB/WAL/SHM bytes, sizes and timestamps; unchanged byte stamps are neither
required nor used as snapshot consistency proof.

Unavailable/shared-lock-incompatible behavior, missing or malformed kernel evidence,
lost coverage or unknown inode/descriptor identity gives a concrete safety HOLD. There is
no unconditional WAL/projection HOLD or manual bypass. Fixed `sqlite_version()` and
`sqlite_source_id()` queries emit only bounded version/date/source identity and journal
mode metadata. Preflight prints that tuple and the installed WorkManager/schema binding
so HOST can retain it after scratch cleanup. The candidate admits the reviewed SQLite
3.44.3/3.44.4 family; any other version or malformed identity HOLDs, and the complete
binding, including database location, must stay equal across samples.
API36 or an Android16 source branch alone does not identify the installed
SQLite binary or prove its open/read/transaction-end/close behavior. HOST must bind
that actual implementation and exercise normal/concurrent WAL reads, first-reader SHM
initialization/reconstruction after phone death, lock survival, missing sidecars,
corruption and close behavior before runtime acceptance. In particular it must prove
that open/end/close perform no forbidden creation, deletion, repair, checkpoint or
journal conversion, while permitting only the bounded automatic SHM effects above.
Unknown/unsafe behavior remains a concrete HOLD. The [Dated status](#dated-status) checkpoint
records the executed HOST evidence and its limits; version metadata is evidence for binding,
not its substitute. Ordinary read access-time updates are possible; no zero-filesystem-effect
claim is made.

The host records the observer's actual PID/start identity before GO, verifies its process
under the app UID, checks normal exit and `/proc` absence, and reconciles surrounding app
processes and events. A separate internal watchdog bounds even a lost ADB session. An
observation-induced app start, publication or work change cannot be concealed as reader
activity or phone absence. Unproved observer retirement or scoped cleanup is HOLD.

Before GO, inventory verification is strict. Only after GO does the existing inventory
account separately for the independently attested reader across its repeated before/after
lists and identity traversals. UID records are validated and bounded before this accounting;
a live reader must match its attested UID, PID, start and name. A failed reader start read
permits retirement only with confirmed `/proc` absence. Unreadable-but-present identities,
changed identity or UID, observed reappearance and another process using the reader name
remain HOLD. Every other app identity is independently sampled and strictly reconciled.
The reader-released separation check remains mandatory; tolerating retirement there does
not accept a work sample. Matching END, normal wrapper exit, actual PID absence and all
surrounding process/event checks are still required, followed by owned cleanup.

A rejected UID-wide process sample leaves stdout empty and writes one closed
`Process identity:` record to stderr before the existing HOLDs. It names the role, the owning
lifecycle action (`none` or, for example, `phone:update`), the caller phase where known
(`pre-update` or `post-update` around the preserving install, otherwise `Unknown`), the guard,
the identity traversal (`first`/`second`) and list boundary (`before`/`after`) in progress,
the subject (`app` or the attested `observer`) and the measured ADB/timeout pipeline status.
Facts that were not measured are `Unknown`. `uid_input` and `observer_input` reject host
inputs before any device read. `acquisition` means that no allowlisted device record arrived:
its status (for example 124 when the ADB bound expires) is the only retained failure fact,
and a nonzero status alone never establishes a race. The device guards are `boot_read`,
`list_read`, `list_size`, `list_rows`, `observer_reappeared`, `stat_read`, `start_value`,
`observer_start`, `observer_present`, `boundary_mismatch`, `traversal_mismatch` and
`boot_continuity` (the final boot identity was unreadable or different); the device exits
with status 1 after each. `expected_boot` is the separate host comparison with the bound
boot after a successful read, so its status is 0. The device discards the stderr of its
process-list, stat and boot reads. The record contains no list, stat record, boot identity,
PID, start tick, process name, command line or environment. It uses the bounded, best-effort
writer of the delivery diagnostics, and so do the existing HOLDs that follow it before
cleanup, including the outer `update_install` HOLD: a failed or blocked write neither changes
the failure nor delays cleanup and retirement. Process predicates, bounds and successful
output are unchanged.

The 2026-10-31 inventory failure remains historical HOLD: later successful cleanup does
not reconstruct that inventory, exclude intervening reuse/app movement or supply its
undrained END. This repair and its regressions claim neither an atomic snapshot nor zero
races or completed device acceptance. A fresh complete ordinary HOST gate remains required.

A later ordinary HOST gate completed all 51 Wear tests, then held after the preserving phone
update. It retained only `Process identity read failed or raced.` and
`Cannot observe post-update processes.` Its failed acquisition, list traversal, PID/stat
sample and rejection remain Unknown, and later process observations cannot reconstruct that
sample. The record above is prospective. It neither explains that HOLD nor establishes an
app, race or Runner defect; a fresh complete ordinary HOST gate remains required.

Logical work samples bracket full instrumentation, both updates, each initial death/launch,
phone separation and the retention Wear death/relaunch, and completion. They preserve the
periodic provider's identity, cadence, kind, worker, constraints and delay; legitimate
UPDATE generations and execution/scheduling metadata require observed phone activity and
compatible monotonic transition markers. Recovery replacement may introduce a new ID with
compatible enqueue/generation evidence while a real sender ran. Already-terminal work
pruning and an initially absent recovery are allowed; no filler work is introduced.
Terminal identities retain their state, generation, spec and execution counters; only
native mapping/schedule retirement with observed phone activity is permitted in place.
Recovery execution/retry/completion transitions follow the one-off state graph, and REPLACE
requires a new identity rather than reviving a terminal row or updating its generation.
Active work loss without explainable replacement, cancellation, spec changes or
ambiguous/raced transitions HOLD.

Each already-scheduled ENQUEUED spec must resolve a generation-matched SystemIdInfo mapping
and an actual connected-network WorkManager job. An empty native inventory cannot satisfy
that obligation. Mapping/generation changes and disappearance of previously correlated
jobs require compatible execution, generation, counter or scheduling transitions plus
observed phone activity. A live RUNNING worker can explain consumed native work; an
explicit unscheduled reset can explain a bounded intermediate rescheduling sample, never
the final Pass. The accepted logical/native pair advances only after both checks pass.
Native IDs may change during explained rescheduling, and native flags do not determine
WorkSpec periodicity. Whole volatile-dump equality and fixed IDs are not required.

`native_jobs` recognizes four-field API36 namespaced `JOB` headers and validated legacy
`JOB #` headers. The numeric scheduler ID comes from the UID/job identity, never the
object hash. The fourth field is checked for its package substring without assuming a
literal tag or bare component. Ownership requires the current package UID/user,
`androidx.work.systemjobscheduler` namespace (or the legacy default namespace), and a
separate exact `app.wardpulse/androidx.work.impl.background.systemjob.SystemJobService`
record. Every block requires exactly one service and required-constraints record.
The complete constraints record must contain only supported, unique constraint names
followed by one bounded hexadecimal mask equal to their combined bits. Missing, extra or
contradictory mask bits HOLD; an owned block requires an exact `CONNECTIVITY` token and
its matching bit. Constraint names and masks never establish logical WorkSpec periodicity.
Every job header and section boundary clears the previous block; foreign records
cannot supply its service or constraints. Unknown or malformed headers/required records,
duplicates, missing evidence and failed/partial dumps HOLD. Acceptance also requires the
registered-jobs section, its closing section boundary and a terminal `PersistStats` record
with bounded load/save counts before the subprocess completion marker. Diagnostics
(including stderr), exceptions, missing/unknown completion structure and nonblank trailing
output HOLD even on a zero subprocess exit status. Streaming input is bounded to 1 MiB,
16,384 lines, 8 KiB per line and 256 job blocks; only a complete, nonempty inventory of at
most 64 jobs and 8 KiB of sanitized metadata leaves the device. No raw dump or tag is retained.

## Publication boundary and proof guard

A **fresh phone publication** is a new post-separation invocation of the app's summary-send /
`putDataItem` path, **including the same payload**. Gms settlement/retry of a request already
initiated before separation is not a new app invocation. This gate makes no claim that all
pending transport operations are absent. Every observed Wear callback/write, process
replacement or monitoring gap still invalidates retention, whatever caused it.

`MethodChannelWatchSyncService.sync` in
[watch_sync_service.dart](../../apps/phone_flutter/lib/sync/watch_sync_service.dart) uses
`WardPulseWatchSyncPlugin.queueWatchSummary` in
[WardPulseWatchSyncPlugin.kt](../../apps/phone_flutter/plugins/ward_pulse_watch_sync/android/src/main/kotlin/app/wardpulse/watchsync/WardPulseWatchSyncPlugin.kt).
The plugin belongs to each Flutter engine. Workmanager's resolved `BackgroundWorker`
creates the headless engine; `callbackDispatcher` registers plugins and runs the same sync
path. `WatchRefreshListenerService.onMessageReceived` in
[WatchRefreshListenerService.kt](../../apps/phone_flutter/android/app/src/main/kotlin/app/wardpulse/WatchRefreshListenerService.kt)
can launch the phone Activity. None of these source manifests alone proves installed sender
coverage. The HOST guard must bind all installed merged components/processes to the
monitored UID, reconcile all old deaths, prove absence with no new starts across the quiet
interval, and preserve event continuity through the final boundary/Pass. Missing sender
coverage or an insufficient causal/observation boundary is HOLD, never assumed quiet.
Queued success logs alone cannot exclude a still-running app's in-flight send invocation.

`summary_hash` remains the sole content reader of `watch_summary.xml`: SHA-256 runs entirely
on Wear through the existing app-UID `run-as` seam. Only a complete, validated 64-character
lowercase hexadecimal digest leaves that pipeline after successful command completion;
failed commands or malformed, oversized, incomplete or trailing output fail the read.
Original summary bytes never reach host hashing, stdout, stderr, evidence, DEX or staging.
Only final hashes and bounded metadata are retained. Host `sha256sum` remains required for
the unrelated APK and reader-DEX comparisons. `stat` observes file identity/write times
independently of the callback. Equal hashes, a receipt, or a WorkSpec sample alone does not
prove quiet. Continuous sanitized role-aware event streams, lifecycle reconciliation, UID-wide process
observations and acknowledged markers supply the bounded guard. They are not intrinsically
lossless; malformed/unrecognized events, detectable loss, races or unavailable continuity
must HOLD. HOST failure probes must establish the guard's actual boundaries before runtime
acceptance can be claimed. There is no manual override or source-review substitute.

This digest transport slice leaves four-gap completion, installed sender binding, cohesive
reader/FD/staging/whole-pair cleanup, opt-in all-nine integration and full runtime
compatibility/fit proof pending. It establishes no runtime or product acceptance.

## Dated status

- 2026-10-20: bounded timer readiness correction authored. Cancellation readiness and
  previous-timer absence are required before rearming returns. The historical signal
  mechanism remains UNKNOWN; Square positive F2 remains HOLD at timer cancellation.
  Historical Round20 and Square idle evidence is not current both-shape acceptance.
  Both-shape lifecycle/retirement and original-preservation proofs remain pending after
  whole Runner completion, full retirement and quiescence; no product acceptance is claimed.
- 2026-10-20: observation retirement entry correction authored. Historical idle-retirement
  evidence remains HOLD; its exact signal/EXIT scheduling interleaving remains unproved.
  Source changes establish no runtime or product acceptance. Both-shape behavioral,
  retirement and original-preservation proofs remain pending after whole Runner completion,
  full retirement and quiescence.
- 2026-10-18: preservation correction authored. The previous force-stop/old-log approach
  is replaced by bounded lifecycle and independent callback/persistence requirements,
  with an explicit preflight HOLD for unavailable logical work evidence. No runtime
  acceptance is claimed. Full ordinary sync acceptance, documentation validation and
  other applicable HOST checks remain pending after Runner completion and retirement.
- 2026-10-18: discovery stdin isolation, role-aware publication/receipt reconciliation and
  the bounded reader correction authored. The earlier unconditional work HOLD is replaced
  with schema-bound samples and transition checks; concrete compatibility/safety/coverage
  HOLDs remain. Compilation/DEX/SQLite safety, ownership/continuity proofs, failure probes,
  full ordinary `just test-phone-watch-sync`, documentation validation and all other
  applicable HOST acceptance remain **pending** after whole Runner completion, retirement
  and quiescence. No runtime Pass or unexecuted acceptance is claimed.
- 2026-10-18: review corrections add a pre-open journal-mode stability HOLD, pair logical
  and native preservation evidence, and reject terminal recovery resurrection. No SQLite
  projection, runtime acceptance or validation result is claimed; HOST acceptance remains
  pending.
- 2026-10-18: the unconditional journal-mode guard is replaced with a bounded, kernel-
  verified shared-lock opening path. WAL, busy/unsupported locking and uncertain evidence
  retain concrete HOLDs. Compilation, lock/SQLite safety probes and the complete ordinary
  acceptance gate remain pending on HOST; no runtime Pass is claimed.
- 2026-10-18: exact-package UID selection now tolerates valid substring siblings;
  Java/shell binding targets WorkManager 2.11.2/schema24/current identity and preserves
  nullable interruption-backoff metadata. WAL admission uses the retained descriptor
  guard plus SQLite's consistent read transaction and existing-sidecar identity checks,
  allowing only automatic SHM reader effects. Fixed SQLite version/source metadata
  supports the still-pending installed-platform binding. Independent review, helper
  compilation/DEX, failure probes, full ordinary `just test-phone-watch-sync`, docs
  validation and all other applicable HOST acceptance remain pending after whole Runner
  completion, retirement and quiescence. No executed acceptance or runtime Pass is claimed.
- 2026-10-18: namespaced native-job parsing and same-block UID/namespace/service/network
  binding authored, retaining validated legacy headers and downstream correspondence.
  Parser failure probes, full ordinary `just test-phone-watch-sync`, documentation
  validation and all other applicable HOST acceptance remain pending after whole Runner
  completion, retirement and quiescence. Prior reader projection evidence does not establish
  full sync, WAL safety, first-reader, concurrency or corruption acceptance. No runtime Pass
  or unexecuted validation is claimed.
- 2026-10-18 — current verification checkpoint, superseding the earlier pending status at
  implementation checkpoints: Java 21/API36/D8 compilation and the installed WorkManager
  2.11.2/schema 24/SQLite 3.44.3 WAL binding were verified. The complete ordinary
  `just test-phone-watch-sync` passed with thirteen normal reader cycles, including the
  first ordinary observer after UID-wide phone-app absence, transaction end/close and
  observer retirement. Two pairs of verified coexisting read-only instances received
  concurrent GO invocations; all four returned complete bounded DB results/END, exited
  successfully and retired. This exercises ordinary concurrent invocations, not observed
  post-GO process co-liveness, overlapping internal SQLite transactions or contention.
  The reviewed Source/compiled-reader correspondence supplies the nondeleting-handler
  proof; corruption dispatch, missing-sidecar failures and individual internal SHM branches
  are not claimed as dynamically exercised. No deliberate database mutation or zero-
  filesystem-effect claim follows. Full HOST checks and separate complete round/square
  connected-suite results are recorded in
  [Routine Verification](../../docs/ANDROID_TOOLCHAIN.md#routine-verification).
