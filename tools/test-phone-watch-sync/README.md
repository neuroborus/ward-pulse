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
cannot produce Pass.
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
generation. At most 32 rows and 12 KiB of metadata leave the reader. Allowed fields are
logical name, opaque ID, worker, state, interval/flex, initial delay, network/constraint
flags, generation/job ID, enqueue/schedule, attempt/period, backoff, override and stop
markers, including schema24's nullable `backoff_on_system_interruptions` (null=-1,
false=0, true=1), which must remain unchanged for a retained work identity.
Constraint blobs yield only absence flags; their contents are never exported.
No input/output/progress, arbitrary tags, accounts, credentials, preferences or whole rows
are read/exported. All exceptions become fixed, sanitized HOLD categories.

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

`summary_hash` remains the sole content reader of `watch_summary.xml`: bytes go directly
through its hash pipeline. Only final hashes and bounded metadata are retained; XML/payloads
are never displayed or saved. `stat` observes file identity/write times independently of
the callback. Equal hashes, a receipt, or a WorkSpec sample alone does not prove quiet.
Continuous sanitized role-aware event streams, lifecycle reconciliation, UID-wide process
observations and acknowledged markers supply the bounded guard. They are not intrinsically
lossless; malformed/unrecognized events, detectable loss, races or unavailable continuity
must HOLD. HOST failure probes must establish the guard's actual boundaries before runtime
acceptance can be claimed. There is no manual override or source-review substitute.

## Dated status

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
