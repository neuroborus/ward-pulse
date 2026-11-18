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

Headless WorkManager sync leaves Mock publications alone. In debug builds, each
`providerSyncOnce` invocation reads the saved Mock choice before creating Live bindings.
Mock, or a choice that cannot be read, skips the run without collection, admission,
watch/widget writes, recovery, alerts or STALE, and never loads or reseeds Demo data. The
invocation asks again after awaited setup and loads, before each effect, inside recovery
and alert currentness checks and before every pending widget write or redraw. Once it sees
Mock it retires; the next Mock-off run starts normally. Queued widget requests carry their
own guard. A failed load marks STALE only while its stamps and the credentials the run
admitted stay current; obsolete failures and rejected snapshots leave rows unmarked. A
plugin call that was already dispatched cannot be retracted. Technical correction
(2026-11-09): native widget publication commits one complete six-slot cache across engines;
retained-row STALE uses the same process monitor for its snapshot and flag-only commit.
This gives no chronological ordering or rollback after disk failure. Persistence/consumer
and foreground/Activity-free Dart roundtrip HOST proofs remain pending; see
[atomic publication](../../docs/product/PHONE_WIDGET_DESIGN.md#atomic-cache-publication--2026-11-09-technical-correction)
for the isolated fixture invocation and limits. Release builds never read the debug choice.

After collection, each headless surface reads its own saved selection immediately before
publication and rechecks Live ownership after that read. A selection read failure retains
that surface's prior output without marking widget rows STALE; sibling publication,
recovery and alerts continue under their own guards. Wholly skipped polls do not read
surface selections or publish them. Saved defaults and explicit empty selections retain
their existing meaning.

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

**Docs preset revision 2** is seed **280** with an explicit anchor. Set
`WARD_PULSE_MOCK_SEED=280` and `WARD_PULSE_MOCK_ANCHOR` to the actual current whole-second
UTC anchor **A** for the capture cohort. `2026-11-02T12:00:00Z` is the semantic regression
anchor, not a permanent capture date. This preset maintains these normalized values:

| Metric | Used % / left % | Reset |
| --- | --- | --- |
| Claude 5h | 20 / 80 | A+5h |
| Claude Weekly | 30.6 / 69.4 | A+7d8h |
| Fable Weekly | 36.9 / 63.1 | Same Weekly boundary |
| Codex Weekly | 46 / 54 | A+597337s |
| Cursor Models | 2 / 98 | Next UTC month |
| Cursor Other | 20 / 80 | Same billing boundary |

Only anchored seed 280 receives these percentage adjustments, the 5h reset adjustment and
omission of optional Cursor on-demand Purchased data. Both Cursor pools remain
percentage-first, with absent quantities and no purchased-credit suffix. Codex retains
**1200** finite purchased credits. Unanchored 280 and every other seed retain their existing
behavior. Claude Extra and other missing optional amounts remain absent; do not infer Money
or quantities from percentages. Calendar Today, UTC-Monday Week, Month and history remain
date-aware rather than fixed across boundaries.

Representative OpenAI Today spend at the regression anchor is **USD 50 minor units ($0.50)**.
The existing phone-local `ConnectionBudget.today` input for capture is **USD 10000 major
($10K, 1000000 minor)**, set through the ordinary admitted UI and restored afterward.
It is not a Rust preset limit or application default. The resulting **0.005% used / 99.995%
left** may display **100%**; the spend is still $0.50.

For a healthy capture, the overall snapshot, every included account and every rendered
allowance must be OK. Verify the complete native screen has zero app-bar/family problem
counters, including grey Unknown badges; healthy selected metrics alone are insufficient.
Other seeds can still produce unhealthy states, and missing optional values remain missing.

Save these Watch IDs in order:

1. `allowance.codex.plan`
2. `allowance.claude.plan`
3. `allowance.claude.claude-seven-day-fable`
4. `allowance.cursor.cursor-plan-models`
5. `allowance.cursor.cursor-plan-other`

The ordinary Claude ring collapses to Weekly because 30.6% used exceeds 5h's 20%; Fable
stays independently selectable. There is no separate Watch Weekly checkbox. Existing
tighter-half ordering places Codex inner/top, Claude/Fable middle and Cursor outer/bottom:
three bands with two completed pairs, retaining the Claude/Fable half identities.
One/two-band views use recorded subsets of this same cohort; restore the master selection
between cases.

Save these widget IDs in order:

1. `allowance.codex.codex-primary`
2. `allowance.claude.claude-seven-day`
3. `allowance.claude.claude-seven-day-fable`
4. `allowance.cursor.cursor-plan-models`
5. `allowance.cursor.cursor-plan-other`
6. `budget.openai.platform.today`

The existing depleted-first display order is Codex 54 / Fable 63 / Weekly 69 / Other 80 /
Models 98 / Money 100. All five selected allowance resets are known; the budget has none.
Codex alone shows **1.2K** purchased credits. The 5h window remains available on the phone
but is not a seventh widget row or a separate Watch ring.

Use one accepted cached cohort and ordinary guarded phone-to-watch publication across
phone/widget/Glance/face and related themes or selection subsets. Do not refresh, reseed or
restart between related views: refresh or Mock-toggle invalidation advances the seed,
while process restart restores the configured seed. Every new view and its caption/alt/index
provenance from this preset must identify **Mock/demo**.

Before enabling Mock, freshly qualify the established ordinary-Mock custody/restoration
route: actual normal package/preferences, secure/core recovery watchlist and future wake,
notification bookkeeping, no eligible or in-flight background work, temporary polling cadence
**15→60 minutes**, a hard Mock cutoff and a restoration reserve. HOLD if custody is unproved.
Ordinary Mock clears unbound recovery history. It cancels the wake only when no qualified
live history remains. Qualified live recovery partitions, stored reset evidence and their
pending wake survive Mock cleanup. Mock-off alone cannot restore discarded unbound history
or a cancelled wake. Persistent connection snapshot cleanup is separate: changing Mock mode
clears those snapshots, and Mock-off does not restore them.
Debug headless runs skip while Mock is saved, so they neither restore discarded history nor
overwrite Mock frames; an already-dispatched background write still needs custody.
Restore the actual normal package/preferences, cadence **15 minutes**, selections, OS/bridge
state and genuine newer Live data, including derived widget/watch frames. Preserve newer
data and real errors; never restore old secrets or snapshots to manufacture equality.

Source tests do not establish native projection, rendering or public capture acceptance.
Root separately owns both Android Rust ABI rebuilds and dated/normal APK provenance,
native/common-data proof and safe restoration. Public captures/index updates remain separately
admitted, with real default Day/weather and headless-publication proof still separate gates.

## Fractional watch usage witness

Watch publication trims float noise to one decimal, but keeps the original value when that
rounding would turn positive usage into `0` or a positive remainder into `100`: Wear reads
exact zero as a full ring. Ordinary rings and split halves share this rule.

`watch_sync_service_test.dart` *publishes fractional usage as positive partial use* sends the
core-produced `dashboard_watch_fractional.json` (USD 4 of 10000 minor units, 0.04% used)
through `MethodChannelWatchSyncService.sync`. The unpaired `budget.openai.platform.today`
ring keeps exact Money and 0.04%; a separate Cursor Models/Other pair keeps its identities,
order and 0.04%/0.03%. Both captured publications must equal
`watch_dashboard_summary_fractional.json` and `watch_dashboard_summary_fractional_pair.json`,
which `WatchSummaryStoreTest` decodes on Wear.

For a fresh producer→phone→Wear witness, set `WARDPULSE_WATCH_WITNESS_DIR` to a new private
empty directory. The Rust test writes its actual output there; the phone test then reads only
that export, rejects a missing, malformed or different one and writes both raw publications
before its usage assertions. Every file is created exclusively, so a reused directory fails:

```sh
export WARDPULSE_WATCH_WITNESS_DIR="$(mktemp -d)"
(cd core && cargo test -p ward-pulse-ffi tests::fractional_watch_snapshot_matches_fixture -- --exact)
(cd apps/phone_flutter && flutter test test/watch_sync_service_test.dart \
  --plain-name 'publishes fractional usage as positive partial use')
```

Then pass both publications to the
[Wear replay](../wear_android/README.md#adaptive-face-complication-contract) using the same
`WARDPULSE_WATCH_WITNESS_DIR`. After replay and retaining the required witness evidence,
remove this task's private directory and unset the variable before Native or full ordinary
checks:

```sh
rm -r -- "${WARDPULSE_WATCH_WITNESS_DIR:?}"
unset WARDPULSE_WATCH_WITNESS_DIR
```

Ordinary checks compare with the committed fixtures without exporting. This proves
publication and decoding/classification only, not Data Layer delivery or paint.

## Android widget geometry case (HOST only)

`android/app/src/androidTest/kotlin/app/wardpulse/PhoneWidgetGeometryTest.kt` is one focused
platform instrumentation case for the production widget publication, RemoteViews and XML.
It uses the installed SDK's `android.test.runner` and `android.test.base` facilities, without
a downloaded test framework. SDK 36's optional JARs were inspected for the runner,
InstrumentationTestCase and JUnit 3 classes; this source qualification is not compilation
or execution evidence. The base library is optional in the test manifest because API24–27
already supply those classes on the boot class path. Production APK runtime dependencies
and versions are unchanged.

The case runs on the main thread with synthetic in-memory data and unattached
`AppWidgetHostView` instances. It registers no widget, writes no preferences and never
activates the tap listener. It asserts actual root/card/layer dimensions, centering and
every exterior pixel's alpha for an unchanged fitting plan under equal, larger and smaller
measured allocations. It reapplies after deliberately changed view state, covers wide and
primary-only complete rows, real synthetic reset instants, exact accessible Money, Extra
quantities, stale/empty/no-fit transitions, three/four responsive sizes, the sixteen-input
guard, sanitized/null/missing/empty list fallbacks, portrait/landscape selection and aggregate
budget fit/exhaustion. Run the same case on API31+ and a supported pre31 phone AVD; one API
cannot establish the other's behavior. No launcher registration or real fold transition is
claimed by this unattached-host case.

Native review qualifies this test's source; compilation and execution require separate HOST
evidence. After whole Runner DONE, actual CLI exit, all known-owned retirement and fresh idle
ownership, Root runs the unchanged full `just check-phone`, `just check-docs`, normal APK build
and this HOST case. Select an explicitly qualified existing phone AVD; do not run this
instrumentation case on a physical device. Retain the actually installed normal APK,
signer/hash/version identities, app data and original incident frames under the existing
[Android toolchain workflow](../../docs/ANDROID_TOOLCHAIN.md). Preserve newer legitimate data
and failed observations. Do not reset/readd a real widget or change its data to make the case
pass. Adding or reviewing the test does not establish a runtime result or real-launcher acceptance.

Build the ordinary candidate from `apps/phone_flutter` with `flutter build apk --debug`.
From `apps/phone_flutter/android`, build the test APK and run only on the selected AVD:

```bash
: "${PHONE_SERIAL:?Set the qualified existing phone AVD serial}"
./gradlew --no-daemon :app:assembleDebug :app:assembleDebugAndroidTest
adb -s "$PHONE_SERIAL" install -t -r ../build/app/outputs/apk/debug/app-debug.apk
adb -s "$PHONE_SERIAL" install -t -r ../build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$PHONE_SERIAL" shell am instrument -w -r -e class app.wardpulse.PhoneWidgetGeometryTest app.wardpulse.test/android.test.InstrumentationTestRunner
```

Record actual commands, elapsed times, selected API/density, APK identities and instrumentation
results, including failures or missing SDK/runtime facilities. Do not use Gradle's connected
test task to discover or touch other devices. Preserve an installed newer normal candidate
and its data; the retained normal APK is a recovery handle, not a required rollback. Use it
only when recovery is needed through the existing device-preserving workflow. Do not remove
a preexisting test package; remove only a test package introduced solely by this case if
appropriate. Verify final rendering and retained data.
Root separately proves real launcher resize/fold/orientation retention, both themes,
complete rows/details/header, exterior alpha, visible accessibility and full-allocation
cold/warm Dashboard taps, joining the active artifact/widget/data/options/variant and measured
root/card/paint to untouched original frames. Include the existing Pixel case; physical
cause/acceptance remains Pending until renewed physical access. This case does not replace
that bounded proof or make HOST acceptance a Native commit prerequisite.

## Persistent Connection Recovery

`PhoneLiveBindings` wires all six live connections to `ConnectionSnapshotCache` and the
headless-safe native `ConnectionCacheEngine` channel. Only canonical normalized snapshots
are cached; provider credentials stay in platform-secure storage. Fresh repositories after
restart can merge current data with stale failed connections without changing their original
success times. Mock data never enters this store.

Watch and widget freshness follows each surface's resolved metrics and displayed purchased
credits independently. A retained stale owner marks its displayed data stale even when a
newer warning determines the aggregate status. Fresh-only selections ignore unrelated stale
accounts; empty or unavailable output with no contributors keeps the aggregate fallback.
`WatchRingMetric` retains its exact owning account and connection locally; payload formats
and metric statuses remain unchanged.

Credential generation, OAuth revision and cache epoch are separate. Reconnect/disconnect
barriers and conditional writes prevent old requests from restoring removed accounts. The
native service coordinates concurrent Flutter engines in the application's single Android
process, including WorkManager; separate OS processes are unsupported. Foreground and
headless callers validate ownership before publication.

Plan removal returns `Future<void>` and separately forwards an optional synchronous
`onRetired` receipt through the secure stores and services. Only accepted native `deleted`
state with a complete generation/revision/epoch stamp notifies, under the deletion lease and
before cleanup. The owned open row settles and starts normal app invalidation/reload once at
that checkpoint; cleanup or downstream failure cannot undo retirement. Later feedback uses
`observeLifecycle` under a read lease to match the exact deleted stamp. A newer active/pending
owner suppresses old feedback; unreadable evidence releases busy state with Retry check and
reconnect available. Retry check observes evidence without deleting again. Codex disconnect
alone tolerates general encrypted-session read failure and continues to the existing deletion
path without revocation material. Other reads retain unavailable errors. Malformed-session
cleanup stays separate, propagates cleanup errors and forwards at most one retirement receipt;
readable removal retains best-effort refresh-token revoke after storage leases release.

### Completed absence reads

`MergingConnectionRepository` observes each connection's actual credential/report read,
excluding cache probes, fallback loads and cleanup. A successful null/blank credential read
with completed native missing-credential retirement, or an established deleted read whose
native lease release completed, contributes an absence stamp to the existing phone-private
`connectionVersions` map. `ConnectionCacheEngine.validAll` accepts it only while the matching
deleted generation/revision/epoch remains well formed and unfenced. Unchanged absence stays
usable; activating that connection retires previously captured absence before later guards.
Healthy siblings and their caches remain usable.

Failed/unavailable or tolerated optional reads, parsing/identity retirement alone, pending
sign-in, skipped polling, accountless active reports and stale/Unknown data do not establish
absence. Genuine evidence survives successful/stale/fallback merges, merge errors, captured
and rejected failures, settings transformations and headless failure proxies. It cannot own
accounts, positive reporting outcomes or recovery history. The private stamps stay out of
shared JSON, persisted normalized snapshots, watch/widget output, diagnostics and UI text.
Guards stop subsequent effects; they do not retract dispatched calls or make validation and
cross-engine delivery atomic.

### Original19 independent SAME-final replay

Original19 runtime acceptance is pending. After whole code DONE, known/scoped process
retirement, a separate fresh public idle observation and the actual owning foreground CLI
exit when used, Root/HOST establishes FINAL → OLD → restored-FINAL independently. Original18's
controller, OLD choice and results supply no original19 PASS. Native must not execute this replay.

The executable route and Root-admitted release-envelope contract are owned by the
[phone cache harness README](../../tools/test-phone-cache/README.md#host-invocation-and-acceptance-boundary).
From the canonical repository root, after those whole-run release gates:

```sh
python3 -B tools/test-phone-cache/replay_original19.py \
  --final <second-corrective-commit> \
  --release-receipt <Root-admitted-whole-release-receipt> \
  --output <fresh-external-evidence-directory>
```

1. Take sole canonical Source/index custody. Bind HEAD, all refs, raw index bytes and a
   logical index manifest, plus the complete Source identity/content/mode manifest. Positively
   qualify every substituted path as a stable regular file with known link/ownership identity;
   absent, null or unreadable evidence proves nothing. Keep immutable OLD and final manifests
   with named tree/blob identities, byte hashes and modes. Bind the final changed-owner manifest
   and inspect the complete test/support/import graph: no production change may escape the
   following eight-owner closure under `apps/phone_flutter/`:
   `lib/providers/connection_lifecycle.dart`,
   `lib/dashboard/merging_connection_repository.dart`,
   `lib/dashboard/connection_snapshot_cache.dart`, `lib/dashboard/dashboard_repository.dart`,
   `lib/dashboard/dashboard_load.dart`, `lib/sync/provider_sync_once.dart`,
   `lib/sync/recovery_watchlist.dart`, and
   `plugins/ward_pulse_watch_sync/android/src/main/java/app/wardpulse/watchsync/ConnectionCacheEngine.java`.
2. OLD consists of those exact blobs and modes from immutable base
   `ddc53fcbb139f221e9a46bd05566ab7e379de950`. Seal identical final test/support/input bytes
   and the unchanged, qualified host FFI artifact across all three legs. The complete graph
   must compile unchanged through pre-existing public APIs; compile the actual Java engine
   afresh for each leg. Identify the FFI artifact actually loaded, not merely one built nearby.
3. Before any substitution, including a partial attempt, arm exact final restoration and open
   a durable, bounded, sanitized journal. Record positive Source/controller identities,
   transitions and restoration outcomes. Run each Flutter/JVM invocation as bounded owned
   processes; establish actual reader retirement before every Source transition. Unknown
   ownership or restoration retains custody and holds further work.
4. Run the identical `connection absence ownership retains accepted A+B after late work`
   test in `test/connection_snapshot_cache_test.dart` with Flutter's JSON reporter on FINAL,
   OLD and restored-FINAL. It uses real stores/native owners, ordinary repositories and Rust
   normalization, separate widget coordinators, `buildPhoneWidgetPayload` and
   `writeHomeWidgetPayload`. Retain its completed native-read observations, full late outcome,
   aggregate identities/values/order, healthy B, actual publication arguments and redraw/store
   readback before evaluating validity assertions. OLD must actually replace accepted A+B
   with late B-only output; both final legs must preserve A+B. Compile/load/setup/transport/
   timeout failures are infrastructure failures, never semantic RED. Keep only bounded
   sanitized oracle evidence; do not retain credentials, raw reports or private stamps.
5. Restore exact final bytes and modes without rewriting the index or refs, even on partial
   failure. Before releasing custody, prove final Source/runtime manifests and HEAD, refs,
   raw and logical index preservation against their captured identities. Do not continue
   ordinary work on uncertain restoration. A matching test result alone is insufficient.

Native's complete two-commit FINALIZE inventory is `git diff --check HEAD` (both commits),
`python3 -B -m unittest discover -s tools/test-phone-cache -p 'test_*.py'`, `just check-docs`
and `just release-status` (the latter three in commit 2), all from the canonical repository
root. FIRST Worker/Reviewer DISCOVERY inventories applicability, capabilities and observed
blockers without execution. Root independently qualifies the merged schedule, step assignments
and current subsets by actual command identity. Diff and docs use ordinary Worker FINALIZE;
the exact Python command uses selected trusted execution with scratch, and release status uses
selected trusted execution with scratch/cache. Selected trusted commands execute only through
Runner's persisted vectors, never inside agent turns. Implementation and semantic review do
not execute or satisfy these gates. Focused Flutter regressions, the
three-leg replay, qualified host FFI build/load, unchanged complete `just check-phone`, and
normal Android build/install/active APK and FFI/native-frame acceptance remain HOST-owned and
pending. They are not a Native wait or scoped-commit prerequisite; no check result is claimed
by this procedure.

The `plan retirement reconciliation` group in `test/app_test.dart` exercises the production
`PhoneLiveBindings.create` factory, real Java lifecycle/cache engine, synthetic reports and
`FakeSecureStorage`. A scoped tall test view retains the existing logical width and keeps
the complete Providers catalogue laid out through removal publication. Both Disconnect and
help → Advanced paste → Remove hold label cleanup after retirement; Advanced Remove invokes
the actual row-scoped help `IconButton`, selected by its tooltip property, and retains the
callback Future. Before releasing cleanup to fail, the unchanged joint oracle requires the
original mounted `CursorPlanRow` State with visible `Not connected` content, accepted app and
Providers snapshots and actual watch-summary payload with a healthy sibling. Failure details
distinguish default-finder absence from offstage retention; absence or a replacement row
cannot satisfy the oracle. The earlier disappearance does not establish a sorting, lazy-layout
or product-staleness cause. Each entrypoint also covers downstream sync failure; cleanup
feedback remains separate and requests no second reload. The `Claude credential-store ownership`
cases in the `Claude plan sign-in recovery` group in `test/providers_screen_test.dart` keep the
same row State and account service while replacing only the credential store during login start,
code completion and already-started pasted cleanup. They use the real login dialog, retain
replacement credentials, reject obsolete callbacks and allow a current login; the unchanged
store case proves successful cleanup and callbacks. Owned operations are released and awaited
even on test failure, including test-view restoration and native bridge closure. Source review
is not PASS.

Providers navigation and scrolling join actual native request/reply and secure-store read
completions, including sequential discovery, currentness checks, mounted plan-row reads and
their serial successors, after navigation and removal publication. Frames then render completed
work; animation settlement alone does not establish I/O readiness. Rows mounted during
scrolling use the same boundary; no Cursor-only lease barrier or request-count assumption
establishes readiness. Proof leases are released in `finally` before awaiting app loads, sync,
readiness or editing. Finite dialog transitions retain animation settlement. The Claude cases
emit only bounded `HOST16-T2` phase labels and completion flags around submission, cleanup-start,
editing, framework frames and teardown. Their shared deletion hook records the connection,
signals cleanup entry and awaits the held cleanup Future without framework assertions. The
test body asserts that argument after observing entry and before releasing cleanup; the
observed unchanged-store case showed the earlier hook assertion preventing the signal under
`tester.pump`. The other cleanup window shares that hook by Source, without retrospective
runtime proof. Submission/dialog pop and row cleanup remain separate operations; no await-order
or route-advancement correction is inferred from Source.

Root runs these on HOST after WHOLE code DONE, owning foreground CLI exit if used, known/scoped
process retirement and a separate fresh public idle observation, alongside mandatory
`just release-status`, affected Flutter/JVM, the unchanged full phone check, supplemental
formatting, host FFI qualification, Android builds and native/device/active-artifact acceptance.

For the original total-item16 SAME-final replay, Root binds OLD to causal predecessor
`4f0b3a9061c7706a90522abaf481f55978849f3d`. Separately compare Advanced Remove and Claude
store-ownership regressions against corrective predecessor
`a3690eb343b4de327f35aa844f2549e6aa3b07d0`. On HOST, focus `test/app_test.dart` with
`--plain-name 'plan retirement reconciliation'` and `test/providers_screen_test.dart` with
`--plain-name 'Claude credential-store ownership'`. Keep identical final tests/support/inputs,
Java engine and FFI library; substitute the complete Dart repair closure, including lifecycle,
secure account/provider stores, services, shared row settlement and the three plan rows.
Qualify immutable blobs/modes, final loader/test identities and index/refs before mutation.
Use journaled in-place Git-blob substitution with unconditional final restoration and reader
retirement before transitions; retain no Source backup, clone or worktree. Bound setup
separately and each focused warm leg to 60 seconds with qualified framework/process deadlines
and awaited Flutter/JVM retirement. OLD must reach the substantive stale-surface or obsolete
completion oracle (including established retirement for removal); compilation, setup, fixture,
loading, transport and timeout failures are not causal RED. Root retains journal/restoration
custody and repeats its whole independent ZERO after restoration and the last correction.
All runtime acceptance remains pending.

`ConnectionSnapshotCache.stamp` binds each normalized account's private `historyOwner` to
the captured committed credential's connection and accepted identity digest. Native cache
provenance can qualify an ownerless cached snapshot; conflicting persisted owners are rejected.
Generation, revision, epoch and committed activation still fence currentness, not history
identity. Session account evidence preserves same-principal rotation and unchanged reconnects;
changed opaque credential bytes start a new local scope without identifying another organization.
No additional identity request or native lifecycle field is used.

`syncPlanRecoveries` reconciles captured snapshot, reporting, retained and skipped provenance
without rereading credentials. `SecureRecoveryWatchlistStore` writes separate owner partitions,
including empty observed partitions, so a delayed old-owner write or clear cannot replace a
sibling's history. Alert consumed markers use the complete typed condition key; recovery
notification addressing includes the owner too. Owner metadata stays in local normalized
data and bookkeeping, outside watch/widget payloads and notification text. Mock cleanup is
currentness guarded and clears only unbound history, preserving qualified live partitions,
stored reset evidence and their pending wake; cancellation during cleanup requires no
qualified live history to remain.
Each partition also retains the last known reset for its spent windows, so an incomplete
or skipped report cannot postpone an earlier wake when a sibling supplies a later reset.
When that window's own captured native start or matching owner/account success is at or after
a known reset that is now due, its history no longer prevents cancellation of the obsolete
wake if no other work is due. Serving the reset does not clear recovery history or stored
reset evidence; unknown or unserved resets remain protected.
Legacy ownerless recovery keys and consumed markers are never adopted by a qualified owner:
each unbound window can lose its pending recovery edge, and each unbound condition can become
eligible on its first qualified crossed observation. Delivery remains best effort, including
possible repeats from overlapping isolates and losses after failed notification attempts.

The `accepted connection history` group in `test/connection_snapshot_cache_test.dart` exercises
real client wrappers, Rust normalization, native lifecycle/cache machinery and secure history
stores with synthetic transports. It covers Codex and fixed-ID Cursor recovery replacement,
Codex and OpenAI reporting threshold replacement, same-owner continuity and persisted isolation.
Its runtime replay, unchanged full phone checks, Android rebuild and startup/FFI/storage
acceptance remain HOST work after the whole owning run completes and its scoped processes
retire, with a separate fresh idle observation (and owning foreground CLI exit if used).

Automatic attempt admission is durable and separate from ephemeral fetch exclusion.
Startup, foreground timer and headless periodic loads share a per-generation/principal
start anchor; token revisions, cache invalidation, failed work and engine detach retain it.
Periodic starts use the current preference and provider floor; reset wakes use the shared
anchor with a five-minute/provider floor and rebook denied pending resets at eligibility.
Native admission reports that anchor for admitted and denied starts. Each spent window's
wake is floored from its own connection's anchor, so denied or unrelated loads cannot
postpone it; loads without that timing, including manual ones, floor from their own time.
A skipped connection's reset already behind stays due, rather than cancelled or replaced by
another connection's wake, until its own later start or successful load serves it.
Manual refresh/check/reconnect loads bypass admission without moving the anchor.
Denied work rereads current cache and supplies no fresh success or recovery evidence,
including skipped connections in partially fresh aggregates. Wholly skipped loads do not
publish watch/widget data or deliver alerts. Scheduling remains subject to Android delays.

`just check-phone` includes `just test-phone-cache`, which runs the production Java transaction
engine's adversarial tests with the existing Android JDK (`javac` and `java`). Flutter tests also
exercise the real engine through a test-only JVM bridge with fake encrypted storage and HTTP
responses. No live credentials, emulator state or provider network are used by these tests.

The cache regression `late older Codex report retains newer normalized cache` in
`test/connection_snapshot_cache_test.dart` also uses the production Rust
`normalizeCodexReportJson` and `mergeDashboardSnapshotsJson` bindings. On Linux, build the
native HOST library before phone tests and select its verified output directory through
the stock `LD_LIBRARY_PATH` loader route. From the repository root:

```sh
(cd core && cargo build -p ward-pulse-ffi)
test -f core/target/debug/libward_pulse_ffi.so
LD_LIBRARY_PATH="$PWD/core/target/debug${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" just check-phone
```

The phone CI workflow performs the same HOST build before its existing `flutter test` step.
The full `check-phone` recipe is unchanged. For the focused HOST regression, from
`apps/phone_flutter/` after that build:

```sh
LD_LIBRARY_PATH="$PWD/../../core/target/debug${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  flutter test test/connection_snapshot_cache_test.dart \
  --plain-name 'late older Codex report retains newer normalized cache'
```

The test records the sanitized normalization inputs and unchanged production outputs. It
lets B (`.800Z`, 90% used) persist after A (`.100Z`, 60%) releases its managed fetch ticket,
then releases A's completion. It collects late return, durable payload, reader-visible memory
fallback and recovery after native-engine/repository restart before asserting B retention;
precision diagnostics follow. A separate equal-instant control accepts a later refresh at
`.100000Z` after `.100Z`.

Causal replay and runtime acceptance remain Root/operator HOST work after whole code DONE,
owning CLI exit, known process retirement and a separate fresh public idle observation.
Run the same final focused test in separate fresh Flutter processes with the retained old
production library and freshly built final library. Expose the retained library as
`libward_pulse_ffi.so` through an ordinary directory symlink and select that directory via
`LD_LIBRARY_PATH`; keep test inputs, Dart source and the native bridge/engine identical.
Record actual loaded-library paths/hashes, test/input/native-engine hashes and normalization
outputs for both runs. Only successful setup followed by failure at B retention is causal
RED; loading, compilation, transport or timeout failures are infrastructure failures.
Source review and the earlier normalization-only precision probe supply no runtime PASS.

Final-APK emulator acceptance on 2026-10-13 covered three real plan connections (Codex,
Claude and Cursor), a production periodic WorkManager task in a fresh background process,
offline cold-start recovery with unchanged cached data/success times, and restored live
phone-to-watch delivery. Hardware and whole-phase release acceptance remain separate gates.

### Codex encrypted-read removal regression (HOST only)

`Codex disconnect retires the managed owner when encrypted reads fail` in
`test/connection_credential_lifecycle_test.dart` uses the production Java engine, secure Codex
store/service and normalized cache without Rust FFI. It verifies an active owner and healthy
reporting sibling, then faults only the observed encrypted session slot. It collects service
outcome, stamped retirement, old-owner/cache eligibility, late publication, recovered reads
and engine-restart observations before its joint oracle. Its framework timeout is 45 seconds.
`CODEX-READ-ORACLE` contains only non-secret observations. OLD must reach that oracle with its
old owner/cache still eligible; an early service error alone is not semantic RED. The joint
assertion uses the fixed reason `Codex encrypted-read retirement oracle;`, without service
errors or native event payloads. The projection's 16,384-byte record bound and fatal errors
remain unchanged. The oversized failed record's origin remains unproven; HOST replay must
establish compatibility.

The Codex case in `test/app_test.dart`'s `plan retirement reconciliation` group observes the
actual deletion lease's completed native release through `ObservingCachePlatform`. Only then
does it hold the separate companion delete. The original owned row, accepted app/Providers
data and watch summary must reconcile once with the healthy sibling while held; failure of
that call produces separate cleanup feedback without another reload. Other controls retain
malformed cleanup errors/one deletion, readable revoke success/failure and a failed native
barrier: no receipt, fenced observation, then the prior durable owner/cache after restart.

For this change, the complete Native catalogue is `git diff --check HEAD`, `just check-docs`
and `just release-status`, all exclusively Runner-owned writable FINALIZE. Discovery,
authoring and read-only review execute none. All Flutter/JVM and artifact/device execution
below remains Root-owned HOST acceptance, with no Native wait before its step commit.

After WHOLE code DONE, actual owning foreground CLI exit if used, known/scoped process
retirement and a separate fresh public idle observation, Root independently reviews this
procedure and assumes sole Source custody. Warm the existing toolchain/dependencies before
custody; qualify Linux `/proc`, subreaper and pidfd support. Root must identify current index
custody and quiesce identified refresh producers through their owning controls before launch;
unknown ownership or an existing index lock holds execution. Do not kill refresh producers
or unrelated processes. Build the unchanged host FFI library once with
`cargo build --locked -p ward-pulse-ffi` from `core/`. Set
`WARDPULSE_CODEX_HOST_LIBRARY` to its absolute real path and
`WARDPULSE_CODEX_FINAL_COMMIT` to the focused final commit's full hash. The procedure pins that
artifact but does not load it. Invoke this one-shot block from the repository root; its new
journal directory must be under `LOCAL_ARTIFACTS/` and must not already exist.

The controller retains `GIT_OPTIONAL_LOCKS=0` and exclusively creates only the resolved index
path's `.lock`, without waiting or following a symlink. It retains the descriptor and journals
its device/inode and controller PID/start time, process group, session and boot identity.
Acquisition and cleanup defer catchable interrupts. Admission requires baseline qualification
and durable custody journaling; rejection retains acquired custody without focused Source
writes. FINAL restoration is armed immediately before attempted substitution, including
partial writes. Current custody requires that actual
owned lease and Root's current owner evidence; it identifies no historical writer. Release
requires the same descriptor/path/controller identity, retired readers, safe FINAL restoration
and successful Source/runtime/HEAD/refs/logical-index/raw-index comparisons. Uncertainty retains
the lock and custody. Never rewrite or restore the index, adopt a changed baseline or excuse
raw drift with logical equality; add no broad Git lock, global configuration or new refs.

It runs FINAL → exact OLD → restored FINAL. Every invocation owns a fresh process group,
has a 60-second wall deadline and a five-second TERM grace before KILL. A Linux subreaper
retains escaped/orphaned descendants; pidfds bind individual signals/waits to actual process
identities. Retirement requires an empty owned descendant census after reaping, including
Flutter and JVM readers, before any Source transition. No unowned process is signalled.
Timeouts, interrupts and infrastructure failures remain failures even after restoration.
OLD must exit normally with status 1, the joint oracle's assertion reason and a completed
summary with exactly one failed test; signal termination cannot establish semantic RED.
Merged Flutter stdout/stderr passes through a nonblocking pipe and bounded in-memory
projection before any evidence is written. The leg logs contain only typed test-owned oracle
fields, the fixed joint-assertion identifier, completed-summary facts and fixed acquisition
error categories. Raw records, failure tails and VM-service data are never emitted or saved.
Missing, invalid or incomplete projected evidence is an infrastructure failure, not causal RED.
Uncatchable termination or uncertain retirement/restoration leaves custody unresolved: keep
the durable journal and lock, qualify its recorded owner/identity, establish retirement and
restore its exact final blob/mode before any further work. Release only the matching owned
lock after successful integrity comparisons. Controller exit or pipe EOF alone grants no
acceptance. Preserve `LOCAL_ARTIFACTS/codex-read-replay-20261118` and its failed evidence unchanged;
its prior non-PASS status and separate safe Source recovery establish neither restored replay
proof nor original acceptance.

```sh
python3 - "$WARDPULSE_CODEX_FINAL_COMMIT" "$PWD/LOCAL_ARTIFACTS/codex-read-replay-correction-20261118" <<'PY'
import ctypes, hashlib, json, os, pathlib, re, select, shutil, signal, stat
import subprocess, sys, time

root = pathlib.Path.cwd().resolve()
final, journal_name = sys.argv[1:]
focus = 'apps/phone_flutter/lib/providers/codex_account_service.dart'
old = '833f5061fec4ec356762f201e65042f71adb1a26'
old_blob = 'd26e5e45941678c7238a85c9565b2b9f604cd472'
env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
def git(*args):
    return subprocess.check_output(['git', *args], cwd=root, env=env)
def digest(data):
    return hashlib.sha256(data).hexdigest()
def identity(path):
    s = path.lstat()
    data = os.fsencode(os.readlink(path)) if stat.S_ISLNK(s.st_mode) else path.read_bytes()
    return [stat.S_IMODE(s.st_mode), digest(data)]
def source():
    names = git('ls-files', '-z').split(b'\0')[:-1]
    return {os.fsdecode(n): identity(root / os.fsdecode(n)) for n in names}
def metadata():
    index = pathlib.Path(os.fsdecode(git('rev-parse', '--git-path', 'index').strip()))
    head = pathlib.Path(os.fsdecode(git('rev-parse', '--git-path', 'HEAD').strip()))
    return [git('rev-parse', 'HEAD').decode().strip(),
            digest(git('symbolic-ref', 'HEAD')), digest(git('show-ref', '--head')),
            identity(index), digest(git('ls-files', '--stage', '-z')), identity(head)]
def tree_entry(commit):
    fields = git('ls-tree', commit, '--', focus).decode().split()
    assert fields[0:2] == ['100644', 'blob'] and fields[3] == focus
    return fields[2]

assert sys.platform == 'linux' and hasattr(os, 'pidfd_open')
assert hasattr(signal, 'pidfd_send_signal')
assert ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0  # child subreaper
assert re.fullmatch('[0-9a-f]{40}', final) and git('rev-parse', 'HEAD').decode().strip() == final
assert not git('status', '--porcelain=v1', '--untracked-files=all')
assert tree_entry(old) == old_blob
final_blob = tree_entry(final)
assert final_blob != old_blob
allowed = {focus, 'apps/phone_flutter/test/connection_credential_lifecycle_test.dart',
           'apps/phone_flutter/test/app_test.dart', 'apps/phone_flutter/test/codex_account_service_test.dart',
           'apps/phone_flutter/test/connection_cache_test_support.dart', 'apps/phone_flutter/README.md',
           'docs/product/SECURITY_MODEL.md', 'docs/product/PRIVACY_POLICY.md',
           'docs/product/user-guide/PROVIDERS.md', '.changeset/codex-disconnect-read-failure.md'}
assert set(git('diff', '--name-only', old, final).decode().splitlines()) <= allowed
# This constrains every other tracked production dependency's bytes and Git mode.
target = root / focus
assert stat.S_ISREG(target.lstat().st_mode) and stat.S_IMODE(target.stat().st_mode) == 0o664
assert target.read_bytes() == git('cat-file', 'blob', final_blob)
executables = [pathlib.Path(shutil.which(n)).absolute() for n in ('flutter', 'dart', 'java', 'javac')]
sdk = executables[0].resolve().parent.parent
runtime_paths = executables + [sdk / 'bin/cache/dart-sdk/bin/dart',
    sdk / 'bin/cache/dart-sdk/bin/dartaotruntime', sdk / 'bin/cache/flutter_tools.snapshot',
    root / 'apps/phone_flutter/.dart_tool/package_config.json']
machine = os.uname().machine
engine = sdk / 'bin/cache/artifacts/engine' / {'x86_64': 'linux-x64', 'aarch64': 'linux-arm64'}[machine]
runtime_paths.append(engine / 'flutter_tester')
library = pathlib.Path(os.environ['WARDPULSE_CODEX_HOST_LIBRARY'])
assert library.is_absolute() and library.resolve().is_file()
runtime_paths.append(library)
def runtime():
    return {str(p): [str(p.resolve()), identity(p), identity(p.resolve())] for p in runtime_paths}
index_path = pathlib.Path(os.fsdecode(git('rev-parse', '--git-path', 'index').strip())).resolve(strict=True)
lock_path = pathlib.Path(str(index_path) + '.lock')
baseline, meta, tools = source(), metadata(), runtime()
directory = pathlib.Path(journal_name).resolve()
assert directory.is_relative_to(root / 'LOCAL_ARTIFACTS')
directory.mkdir(exist_ok=False)
journal = (directory / 'journal.jsonl').open('x')
def record(event, **values):
    journal.write(json.dumps(dict(event=event, **values)) + '\n')
    journal.flush()
    os.fsync(journal.fileno())
record('baseline', final=final, final_blob=final_blob, old=old, old_blob=old_blob,
       git_mode='100644', filesystem_mode='0664', source=baseline, metadata=meta, runtime=tools,
       environment_sha256=digest(json.dumps(env, sort_keys=True).encode()))

class Evidence:
    def __init__(self, output):
        self.output, self.pipe = output, None
        self.pending, self.dropping, self.eof = bytearray(), False, False
        self.oracle, self.summary, self.assertion = None, None, False
        self.oracle_seen, self.errors = False, set()
    def emit(self, event, **values):
        if 'evidence-write' in self.errors:
            return
        try:
            self.output.write(json.dumps(dict(event=event, **values)) + '\n')
            self.output.flush()
            os.fsync(self.output.fileno())
        except OSError:
            self.errors.add('evidence-write')
    def reject(self, category):
        if category not in self.errors:
            self.errors.add(category)
            self.emit('projection-error', category=category)
    def project(self):
        line = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '',
                      self.pending.decode('utf-8', errors='replace')).strip()
        self.pending.clear()
        match = re.search(r'(?:^|: )CODEX-READ-ORACLE (\{.*\})$', line)
        if 'CODEX-READ-ORACLE ' in line:
            if self.oracle_seen:
                self.reject('oracle-count')
                return
            self.oracle_seen = True
            def unique_fields(pairs):
                value = {}
                for key, item in pairs:
                    if key in value:
                        raise ValueError
                    value[key] = item
                return value
            try:
                value = json.loads(match[1], object_pairs_hook=unique_fields) if match else None
                flags = ('current', 'cacheEligible', 'retainedCache', 'latePublished',
                         'coldCurrent', 'coldCacheEligible', 'coldCache', 'coldPublished',
                         'encryptedReadFailed', 'siblingUnchanged')
                valid = (type(value) is dict and set(value) == set(flags) | {'mode', 'receipts'}
                         and (value['mode'] is None or value['mode'] in ('active', 'deleted'))
                         and all(type(value[key]) is bool for key in flags)
                         and type(value['receipts']) is int and 0 <= value['receipts'] <= 2147483647)
            except (ValueError, RecursionError):
                valid = False
            if valid:
                self.oracle = {key: value[key] for key in ('mode', *flags, 'receipts')}
                self.emit('oracle', fields=self.oracle)
            else:
                self.reject('oracle-invalid')
        if 'Codex encrypted-read retirement oracle;' in line and not self.assertion:
            self.assertion = True
            self.emit('assertion', identifier='Codex encrypted-read retirement oracle')
        match = re.fullmatch(r'(?:\d{2,}:\d{2}(?::\d{2})? )?\+(\d{1,6})'
                             r'(?: ~(\d{1,6}))?(?: -(\d{1,6}))?: '
                             r'(All tests passed!|Some tests failed\.)', line)
        if match:
            summary = dict(passed=int(match[1]), skipped=int(match[2] or 0),
                           failed=int(match[3] or 0),
                           result='passed' if match[4] == 'All tests passed!' else 'failed')
            if self.summary is None:
                self.summary = summary
                self.emit('summary', **summary)
            elif self.summary != summary:
                self.reject('summary-conflict')
    def drain(self, limit=16):
        if self.pipe is None or self.eof:
            return
        # Bound each drain so continuous output cannot starve deadline/retirement checks.
        for _ in range(limit):
            try:
                data = os.read(self.pipe.fileno(), 4096)
            except BlockingIOError:
                return
            except OSError:
                self.reject('pipe-read')
                self.pipe.close()
                self.pipe = None
                return
            if not data:
                self.eof = True
                if not self.dropping:
                    self.project()  # Accept a final fragment without a line terminator.
                return
            for byte in data:
                if byte in (10, 13):  # Compact reporter redraws use CR; expanded output uses LF.
                    if not self.dropping:
                        self.project()
                    self.pending.clear()
                    self.dropping = False
                elif not self.dropping:
                    if len(self.pending) < 16384:
                        self.pending.append(byte)
                    else:
                        self.pending.clear()
                        self.dropping = True
                        self.reject('record-limit')
    def finish(self):
        # Retirement has its own descendant census; never wait for inherited pipe EOF.
        self.drain(limit=256)
        if self.pipe is not None:
            if not self.eof:
                self.reject('pipe-incomplete')
                if not self.dropping:
                    self.project()
            self.pipe.close()
            self.pipe = None

def census():
    while True:
        table = {}
        for path in pathlib.Path('/proc').glob('[0-9]*/stat'):
            try:
                text = path.read_text()
                fields = text[text.rfind(')') + 2:].split()
                table[int(path.parent.name)] = [int(fields[1]), int(fields[2]), fields[19]]
            except (FileNotFoundError, ProcessLookupError):
                pass
        # A child may be adopted after its stale PPID was scanned and its parent
        # disappeared. The controller's direct-child list closes that census gap.
        direct = {int(pid) for pid in pathlib.Path(
            f'/proc/self/task/{os.getpid()}/children').read_text().split()}
        if direct <= table.keys():
            break
    family = {os.getpid()} | direct
    while True:
        expanded = family | {pid for pid, v in table.items() if v[0] in family}
        if expanded == family:
            break
        family = expanded
    return table, {pid: table[pid] for pid in family - {os.getpid()}}
def owned():
    return census()[1]
def send(proc, sig):
    table, children = census()
    group = {pid for pid, v in table.items() if v[1] == proc.pid}
    assert group <= children.keys(), 'Uncertain process-group ownership; retain custody.'
    record('signal', signal=sig, identities=children)
    if group:
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            pass
    for pid, ident in children.items():
        if pid in group:
            continue
        try:
            fd = os.pidfd_open(pid)
            try:
                current = census()[0].get(pid)
                if current is not None:
                    assert current[2] == ident[2], 'PID identity changed; retain custody.'
                signal.pidfd_send_signal(fd, sig)
            finally:
                os.close(fd)
        except ProcessLookupError:
            pass
def retire(proc, evidence=None):
    if proc is None:
        assert not owned(), 'Outstanding reader; retain custody.'
        return
    if owned():
        send(proc, signal.SIGTERM)
    grace = time.monotonic() + 5
    while True:
        if evidence is not None:
            evidence.drain()
        for pid in owned():
            if pid != proc.pid:
                try:
                    os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    pass
        children = owned()
        # Keep the leader unreaped until its descendants retire, reserving its
        # PID/process-group identity against reuse while group signals are possible.
        if set(children) == {proc.pid}:
            fd = os.pidfd_open(proc.pid)
            try:
                if select.select([fd], [], [], 0)[0]:
                    proc.wait()
            finally:
                os.close(fd)
            children = owned()
        if not children:
            proc.wait()
            record('retired', leader=proc.pid, returncode=proc.returncode)
            return
        killed = time.monotonic() >= grace
        if killed:
            # Include descendants adopted since the preceding signal/census.
            send(proc, signal.SIGKILL)
        fds = []
        try:
            for pid in children:
                try:
                    fds.append(os.pidfd_open(pid))
                except ProcessLookupError:
                    pass
            ready = select.select(fds, [], [], 0)[0] if fds else []
            waiting = [fd for fd in fds if fd not in ready]
            if evidence is not None and evidence.pipe is not None and not evidence.eof:
                waiting.append(evidence.pipe.fileno())
            if waiting:
                select.select(waiting, [], [], 0.1 if killed else min(0.1, max(0, grace - time.monotonic())))
        finally:
            for fd in fds:
                os.close(fd)

interrupts, cleaning = [], False
def interrupted(sig, frame):
    interrupts.append(sig)
    if not cleaning:
        raise InterruptedError('HOST replay interrupted')
for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, interrupted)
def controller_identity():
    text = pathlib.Path('/proc/self/stat').read_text()
    fields = text[text.rfind(')') + 2:].split()
    return dict(pid=os.getpid(), start_ticks=fields[19], process_group=os.getpgrp(),
                session=os.getsid(0), boot_id=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip())
controller = controller_identity()
lock_fd, lock_identity, lease_ready = None, None, False
def lease_owned():
    assert lock_fd is not None and lock_identity is not None, 'Index lease uncertain; retain custody.'
    assert controller_identity() == controller, 'Index lease owner changed; retain custody.'
    index = pathlib.Path(os.fsdecode(git('rev-parse', '--git-path', 'index').strip()))
    assert stat.S_ISREG(index.lstat().st_mode) and index.resolve(strict=True) == index_path
    descriptor, path = os.fstat(lock_fd), lock_path.lstat()
    assert all(stat.S_ISREG(s.st_mode) and s.st_nlink == 1
               and [s.st_dev, s.st_ino] == lock_identity for s in (descriptor, path)), (
                   'Index lease replaced; retain custody.')
def install(blob):
    assert not owned()
    lease_owned()
    record('substitute', path=focus, blob=blob, git_mode='100644', filesystem_mode='0664')
    target.write_bytes(git('cat-file', 'blob', blob))
    target.chmod(0o664)
def preserved(expected):
    assert not owned()
    lease_owned()
    assert source() == expected and metadata() == meta and runtime() == tools

proc, evidence, results, expected = None, None, [], baseline
restoration_needed = False
try:  # Restoration is installed before the first substitution, including partial writes.
    # Fence acquisition until the descriptor and durable owner evidence are retained.
    cleaning = True
    try:
        lock_fd = os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        descriptor = os.fstat(lock_fd)
        lock_identity = [descriptor.st_dev, descriptor.st_ino]
        lease_owned()
        record('index-lease-acquired', index=str(index_path), lock=str(lock_path), descriptor=lock_fd,
               device=lock_identity[0], inode=lock_identity[1], controller=controller)
        preserved(baseline)
        record('custody', index=str(index_path), lock=str(lock_path), descriptor=lock_fd,
               device=lock_identity[0], inode=lock_identity[1], controller=controller)
        lease_ready = True
    finally:
        cleaning = False
    for leg, blob in [('FINAL', final_blob), ('OLD', old_blob), ('RESTORED_FINAL', final_blob)]:
        if interrupts:
            raise InterruptedError('HOST replay interrupted')
        preserved(expected)
        if leg != 'FINAL':
            restoration_needed = True
            install(blob)
        expected = dict(baseline)
        expected[focus] = [0o664, digest(git('cat-file', 'blob', blob))]
        preserved(expected)
        log = directory / (leg + '.log')
        started = time.monotonic()
        outcome = 'launch-failed'
        entry = None
        try:
            with log.open('x', encoding='utf-8') as output:
                evidence = Evidence(output)
                try:
                    # Record signals without raising until the launched child has a
                    # retained handle and pipe; normal child signal masks are unchanged.
                    cleaning = True
                    try:
                        proc = subprocess.Popen([str(executables[0]), 'test',
                            'test/connection_credential_lifecycle_test.dart', '--plain-name',
                            'Codex disconnect retires the managed owner when encrypted reads fail'],
                            cwd=root / 'apps/phone_flutter', env=env, start_new_session=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
                        try:
                            os.set_blocking(proc.stdout.fileno(), False)
                        except OSError:
                            proc.stdout.close()
                            evidence.reject('pipe-setup')
                            raise
                        evidence.pipe = proc.stdout
                    finally:
                        cleaning = False
                    record('started', leg=leg, leader=proc.pid, identities=owned())
                    if interrupts:
                        raise InterruptedError('HOST replay interrupted')
                    outcome = 'controller-failed'
                    fd = os.pidfd_open(proc.pid)
                    try:
                        while True:
                            if interrupts:
                                raise InterruptedError('HOST replay interrupted')
                            evidence.drain()
                            remaining = started + 60 - time.monotonic()
                            if remaining <= 0:
                                outcome = 'timeout'
                                break
                            readers = [fd]
                            if evidence.pipe is not None and not evidence.eof:
                                readers.append(evidence.pipe.fileno())
                            if fd in select.select(readers, [], [], min(0.1, remaining))[0]:
                                outcome = 'exited'
                                break
                    finally:
                        os.close(fd)
                except BaseException as error:
                    if isinstance(error, InterruptedError):
                        outcome = 'interrupted'
                    record('failure', leg=leg, outcome=outcome, category='acquisition-failed')
                    raise RuntimeError('HOST replay acquisition failed; retain journal.') from None
                finally:
                    # Catchable repeated interrupts cannot bypass reader retirement/restoration.
                    cleaning = True
                    try:
                        retire(proc, evidence)
                        if interrupts:
                            outcome = 'interrupted'
                        elif outcome == 'exited' and proc.returncode < 0:
                            outcome = 'signal-terminated'
                    except BaseException:
                        outcome = 'retirement-failed'
                        raise RuntimeError('HOST reader retirement uncertain; retain custody.') from None
                    finally:
                        evidence.finish()
                        entry = dict(leg=leg, outcome=outcome,
                                     returncode=None if proc is None else proc.returncode,
                                     elapsed_seconds=time.monotonic() - started, interrupts=list(interrupts),
                                     oracle=evidence.oracle, assertion=evidence.assertion,
                                     summary=evidence.summary, projection_errors=sorted(evidence.errors))
                        results.append(entry)
                        record('leg', **entry)
                        cleaning = False
        except BaseException as error:
            if isinstance(error, InterruptedError):
                outcome = 'interrupted'
            if entry is None:
                record('leg', leg=leg, outcome=outcome,
                       returncode=None if proc is None else proc.returncode,
                       elapsed_seconds=time.monotonic() - started, interrupts=list(interrupts),
                       category='evidence-acquisition')
            raise RuntimeError('HOST replay failed; retain journal and projected evidence.') from None
        proc = None
        evidence = None
        preserved(expected)
finally:
    cleaning = True
    try:
        if lease_ready:
            retire(proc, evidence)
            if restoration_needed:
                install(final_blob)
            preserved(baseline)
            record('restored', source_identity=True, runtime_identity=True, metadata_identity=True,
                   results=results, interrupts=interrupts)
            lease_owned()
            os.unlink(lock_path)
            os.close(lock_fd)
            lock_fd = None
            record('index-lease-released', device=lock_identity[0], inode=lock_identity[1],
                   controller=controller)
        elif lock_fd is not None:
            record('admission-failed', category='admission-failed', index=str(index_path),
                   lock=str(lock_path), descriptor=lock_fd, identity=lock_identity,
                   controller=controller)
            raise RuntimeError('Index lease acquisition uncertain; retain custody.')
    except BaseException:
        record('restoration-failed', category='restoration-failed', results=results, interrupts=interrupts)
        raise RuntimeError('HOST restoration uncertain; retain custody.') from None
    finally:
        journal.close()
        cleaning = False

assert not interrupts and len(results) == 3
for entry in results:
    leg, outcome, code, oracle = (entry[key] for key in ('leg', 'outcome', 'returncode', 'oracle'))
    assert outcome == 'exited' and oracle is not None and not entry['projection_errors'], (
        leg, outcome, code, 'infrastructure failure')
    assert oracle['encryptedReadFailed'] and oracle['siblingUnchanged'], (leg, oracle)
    if leg == 'OLD':
        assert code == 1 and entry['assertion'] and entry['summary'] == dict(
            passed=0, skipped=0, failed=1, result='failed')
        assert oracle['mode'] == 'active' and all(oracle[k] for k in
            ('current', 'cacheEligible', 'retainedCache', 'coldCurrent', 'coldCacheEligible', 'coldCache'))
    else:
        assert code == 0 and entry['summary'] == dict(passed=1, skipped=0, failed=0, result='passed'), (
            leg, code, oracle)
print('Replay complete; Source/runtime/index/refs/HEAD restored. HOST acceptance remains pending.')
PY
```

Retain the journal, all three projected leg logs, outcomes and elapsed times, including
allowed partial evidence from failed/interrupted legs. Root then runs focused app/service
coverage and unchanged full `just check-phone`
(both nonmutating format checks, analysis, all Flutter tests and JVM harnesses). Select the
unchanged host library's absolute directory with the documented `LD_LIBRARY_PATH` route;
record its actual loaded path from the owned test process's mappings and hash that resolved
file wherever FFI is consumed. A requested loader path is not loading evidence. Build the
final debug phone APK, verify source-bound JNI inputs and packaged/installed native artifact
identity, install on the qualified phone emulator, and smoke-test startup and Providers
navigation without live account operations or data clearing. The encrypted-read claim belongs
to the bridge tests. No Wear matrix is triggered. Root repeats full independent ZERO after
the last correction and replay restoration; all HOST evidence remains pending until executed.

## Configured empty dashboard (HOST only)

Saved rules and bare local budgets pass through `applyUserAlertSettings` to the Rust
`apply_alert_settings` transform. With no accounts, settings clear alerts and conditions while
preserving the supplied snapshot, including healthy idle status or genuine nonhealthy status.
They do not manufacture reporting data or successful-sync evidence. The configured regressions
in `test/watch_sync_service_test.dart` use the default production effect and the real
`MethodChannelWatchSyncService`, capturing its `syncWatchSummary` argument at the existing
messenger boundary. They collect the result and emitted payload before the joint health
assertion. Separate Plan `at: 80` and bare Today-budget cases contrast disabled settings; a
nonhealthy control protects phone-only issue, rejection, credential-version and reporting metadata.

All execution here is Root/operator HOST work after WHOLE code DONE, known/scoped process
retirement and a separate fresh public idle observation. Require actual owning foreground CLI
exit only if one was used. Native source review supplies no runtime PASS and does not wait for
HOST acceptance. Keep the unchanged full `just check-phone`, final documentation/contracts/
release-status gates, Android Rust build, normal debug APK and device acceptance pending until
their owning HOST checkpoint.

Use the same final focused tests for both replay legs. Before any Source transition, qualify
the final closure and record test/input hashes, Source hashes/modes, HEAD, index and logical
refs. Pin the actual final commit and alerts-module blob as immutable Git identities; retain
no Source backup, private export, clone or worktree. Register a durable restoration journal
and unconditional final restoration for every exit, including partial operations, cancellation
and timeouts, before mutation. Retire owned readers before each transition. Materialize only
`core/ward-pulse-core/src/alerts/mod.rs` from baseline
`6c074d279a05cf1e8395a530d750f6b021b18ff7`, verifying exact historical blob
`1cd9af1bf05db8368f1f75ea242c7264d39ee61e`. From `core/`, build OLD into an absolute,
task-owned output directory:

```sh
CARGO_TARGET_DIR="$WARDPULSE_EMPTY_OLD_TARGET" cargo build --locked -p ward-pulse-ffi
```

Restore the pinned final module through stock Git worktree operations, including its mode,
and verify complete Source/index/ref restoration before the FINAL build or other ordinary
work. Use a separate absolute, task-owned output directory for FINAL:

```sh
CARGO_TARGET_DIR="$WARDPULSE_EMPTY_FINAL_TARGET" cargo build --locked -p ward-pulse-ffi
```

Library builds exclude the historical unit tests. Keep every other production input and the
final Dart tests identical. From `apps/phone_flutter/`, select each leg's verified `debug`
directory through `LD_LIBRARY_PATH` and run the identical command in separate fresh processes:

```sh
LD_LIBRARY_PATH="$WARDPULSE_EMPTY_TARGET/debug${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  flutter test test/watch_sync_service_test.dart --plain-name 'configured empty settings preserve health' --timeout 60s
```

Fresh processes prevent the binding singleton from retaining the other library. Qualify the
existing owned 60-second invocation budget before each launch; `--timeout 60s` is only the
framework timeout. Builds/setup have separate qualified bounds. Capture `LD_DEBUG=files,libs`
diagnostics in memory and project only the loaded library path/hash and owned PID before any
output or storage, including Flutter-forwarded stdout, JSON print events and failure tails.
Never save raw traces and sanitize later. Retain the allowlisted projection, build inputs,
identical test/input hashes and the synthetic result/emitted-payload records from both legs.
OLD must load, invoke the public Rust settings transform and emit its result before failing
the joint health assertion with Unknown statuses. FINAL must pass both configured cases.
Compilation, setup, loading, empty selection and timeout failures are infrastructure failures.
The historical semantic failure is an external negative witness, not a Native pipeline gate.

### Native idle integration case

`integration_test/configured_empty_test.dart` mounts the public `WardPulseApp` with a fixed
empty repository and in-memory saved rules. Its default shared settings evaluation stays real.
Default credential/account/settings stores are inert; scheduling, widget publication,
notification/recovery delivery and wakes are disabled. The real watch sender is intercepted
only at its messenger publication boundary, and its refresh listener and widget navigation
are inert, so the case neither publishes to other devices nor consumes ordinary queued intents.
It does not call production `main`, retire credentials, clear data or mutate persisted settings.
Existing OS-scheduled writers still require HOST custody; the constructor does not retire them.

The case asserts the accepted snapshot and captured publication, the saved Today-cap scope,
the idle **Connect a provider** prompt and absence of problem badges. Stock Android integration
capture retains the original `configured-empty-idle` frame in the `screenshots` entry of
`reportData`; the SDK restores its temporary image surface during teardown. The small
`test_driver/configured_empty.dart` adapter uses the existing SDK driver and writes that report,
including failure data. No manual barrier, selector or alternate harness is used.

After qualifying final JNI inputs and retaining the verified normal APK, build this separate
test target from `apps/phone_flutter/`:

```sh
flutter build apk --debug --target=integration_test/configured_empty_test.dart --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
```

Reuse only the artifact identity, data-preserving `install -t -r`, fresh PID/VM qualification,
owned port forwarding and existing-app attachment steps in
[Android notification integration case](#android-notification-integration-case-host-only).
No notification-policy changes or notification-case prerequisites apply here. Set
`FLUTTER_TEST_OUTPUTS_DIR` to a fresh task-owned evidence directory and attach with the qualified
case VM URI, without automatic install/uninstall cleanup:

```sh
flutter drive -d "$PHONE_SERIAL" --target=integration_test/configured_empty_test.dart --driver=test_driver/configured_empty.dart --use-existing-app="$WARDPULSE_EMPTY_VM_URI" --keep-app-running
```

Qualify the effective 60-second case deadline, driver request limit and separate owned-process
bound before launch; setup has its own bound. Require actual framework success and the
non-null case-bound report with `completed: true`, matching input/settings/result/emitted data,
and one nonempty named native frame. Inspect that original frame before visual acceptance;
serialized values or a connected normal-main frame cannot substitute for it. Identify this
test-target APK/runtime/frame separately from normal-main startup. Retire owned case/driver
processes, remove only its forwarding, restore the retained normal APK with data preserved,
and verify normal artifact, state, derived surfaces and library identity. Do not uninstall or
clear storage on restoration failure. All replay, device and restoration evidence remains
Pending until HOST performs it; item acceptance also requires Root's complete independent ZERO
after the last correction.

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

## Notification sound

Alert notifications and Plan recovery share one bundled click. On Android 8.0 and newer,
only newly created notification categories default to this sound. Existing categories retain
their previous system default, custom sound or silence, along with their other Android
settings. Updating WardPulse does not replace those sounds or reset categories.
On older supported Android versions (API 24–25), both notification types use the same click
on each post. Saved delivery choices, Android notification permission, notification volume
and Do Not Disturb remain authoritative.

The shared `phoneNotificationSound` in `lib/sync/notification_coordinator.dart` uses
`flutter_local_notifications` 22.3.0's `RawResourceAndroidNotificationSound` with the
extensionless name `wardpulse_notification_click`. Both channel declarations and both
notifiers' per-post Android details reference it. The narrow `tools:keep` rule in
`android/app/src/main/res/raw/keep.xml` retains this resource for release shrinking.

`android/app/src/main/res/raw/wardpulse_notification_click.wav` is an owner-provided,
first-party original sound, copied without conversion or byte changes. This audio asset is
explicitly licensed under the [Apache License 2.0](../../LICENSE). WardPulse brand rights
remain separate.

SHA-256: `c056547acf175ddc7e46c0e35fdb586f8737dc83e533e5391de6e366885f9306`.

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

### Granted-baseline sound case

`WARDPULSE_NOTIFICATION_GRANTED_SOUND=true` selects a separate, bounded case with an
already-granted Android baseline and both `wardpulse.alerts` and `wardpulse.plan_recovery`
channels already present. Combining it with `WARDPULSE_NOTIFICATION_FIRST_FOREGROUND=true`
fails before binding initialization. The default denied case and focused first-foreground
case keep their existing prerequisites, assertions and report contracts; this route does
not replay them or turn their earlier failed diagnostics into passes.

Root alone performs this HOST acceptance after the whole owning execution is DONE, the
original CLI/tool/observer have actually exited, all known owned processes have retired,
controllers are zero and a separate fresh public idle/freelease check passes. Complete
unchanged full `just check-phone`, full `just check-docs` and the existing extra nonmutating
`dart format --output=none --set-exit-if-changed integration_test test_driver` from the phone
directory. Native completion and its local commit do not await HOST sound qualification.

Before any build or installation, retain the **exact actually installed normal APK** at
an unused task-owned path outside `build/`, resolving the current package-manager APK path
and retaining its hash, signer, version, package, installed UID and ABI facts. Stop if the
installed artifact set cannot be uniquely resolved and retained. A newly built `lib/main.dart`
APK is a separate ordinary-build candidate and cannot substitute for this restoration
artifact. Preserve current normal data, profiles, rules, notification bookkeeping, permission
flags, effective channel policy and legitimate posts without exporting credentials or
overwriting newer state with an old snapshot. Qualify the complete restoration route first.

Build the ordinary and selected SDK artifacts only after retention. Use the existing
both-ABI Rust build route, or qualified unchanged JNI reuse explicitly owned by Root.
For **each** `arm64-v8a` and `x86_64` library, join the owned JNI input to the Gradle merged
library, the actual strip-task output, the APK member and the installed/active artifact.
Inspect the actual strip result, including a documented unchanged output when stripping
was legitimately skipped; do not demand byte equality between unstripped and stripped
libraries or infer the strip result from an APK alone. Bind the APK hash, signer, application
ID and version before installation, then rejoin installed bytes, UID, current PID/start ticks
and active process to that artifact. Source, a build message or matching version alone is
insufficient. Keep the retained normal APK and failed evidence outside overwritten outputs.

From `apps/phone_flutter`, build the selected target:

```sh
flutter build apk --debug --target=integration_test/notification_delivery_test.dart --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false --dart-define=WARDPULSE_NOTIFICATION_GRANTED_SOUND=true
```

Between build and attach, use the guarded `adb -s "$PHONE_SERIAL" install -t -r` route and
launch the verified target through the existing `am start -W` route. Stop on any failed leaf;
there is no automatic install retry, uninstall, data clear, force-stop or baseline reset.
Require a genuine existing grant and both existing channels **before** launch. Preserve their
effective blocking, importance, sound and other policy; inspect notification volume, DND and
the qualified output route without changing them. If prerequisites or reversible preservation
are unknown, hold launch. This selected existing-channel case does not prove fresh-channel
sound defaults. No permission, channel, volume, DND or audio-routing mutation is part of it.

Discover the fresh VM-service URL from the verified current process, establish only the
owned forward with the existing `adb forward tcp:0` route, and bind its device/host ports to
that PID/start and VM identity. Keep the exact authentication path private; never publish
the VM/auth URL or attach using an old process log. Then attach the stock driver:

```sh
flutter drive -d "$PHONE_SERIAL" --target=integration_test/notification_delivery_test.dart --driver=test_driver/notification_delivery.dart --dart-define=WARDPULSE_NOTIFICATION_GRANTED_SOUND=true --use-existing-app="$WARDPULSE_NOTIFICATION_VM_URI" --keep-app-running
```

Before launch, qualify the phase commands and actual operator/model/tool round trips,
capture arming, posting and OS/original-shade observations against this fixed budget.
These are conservative proposed allocations, **not measured HOST feasibility**. Failed
qualification holds launch for reconciliation; it never extends an active case or permits
automatic retry. The monotonic clock starts in the actual case body, before driver attachment
can finish; attachment does not restart it. The eight-minute framework timeout is a backstop,
not cancellation of delivery Futures or proof that teardown ran.

| Case elapsed time | Required checkpoint |
| --- | --- |
| 0–60 seconds | Launch/attach and clear20 baseline; arm alert capture before GRANTED READY Continue publishes 90. |
| By 210 seconds | First 150-second witness allocation finished; ALERT POSTED Continue validates and retires the alert before nonposting100, and recovery preparation is complete. |
| By 360 seconds | Second 150-second witness allocation finished; RECOVERY READY Continue publishes 20 and final-phase entry is complete. |
| By 420 seconds | RECOVERY POSTED observations, Continue and final assertions complete. |
| By 480 seconds | Protected final 120-second phase ends after awaited cleanup and report; its last 60 seconds are reserved for cleanup/report. |

Each sound witness requires its **own** 90-second recording of isolated canonical-emulator
playback output, excluding microphone and unrelated host audio. Arm it before its triggering
Continue, allow a 30-second completion margin and set every process/tool completion deadline
to at least 120 seconds. Require publication within 45 seconds of actual capture start and
inside its recording window, while respecting the case cutoffs. Retain actual capture start/end
and actual owned OS post times: a recording that misses the event is not a witness. If a
witness is missed, stop progression; never publish a later post to repair its evidence.

The four manual barriers are GRANTED READY, ALERT POSTED, RECOVERY READY and RECOVERY POSTED.
At the first, retain the settled clear20 and unused alert/recovery identities, then arm the
alert capture. At ALERT POSTED, retain the real alert UID/channel/tag/ID/time and original
shade frame plus completed independent sound witness before Continue validates the matching
owned alert, awaits its cancellation and proves absence, then publishes nonposting100.
Retirement preserves the consumed crossing and empty window memory; Rust 100 then remembers
the exhausted window without a second alert. Preserve unrelated, changed/replaced and summary
posts; unknown ownership or unproved removal fails the case.
At RECOVERY READY, require the earlier alert absent and recovery identity unused, then arm
the separate recovery capture before Continue publishes 20. Publication and recovery dispatch
recheck both identities. At RECOVERY POSTED, retain the recovery witness and its real
identity/time/original shade frame alongside the earlier historical alert evidence before
Continue permits recovery-only final assertions and teardown. Join both sound observations
to the original WAV SHA-256 `c056547acf175ddc7e46c0e35fdb586f8737dc83e533e5391de6e366885f9306`.
Packaging, sound URIs, route readiness, plugin Futures and reports alone never establish sound.
Other preserved posts or platform policy may still suppress playback: retain actual per-key
reasons and each separate audio witness. This SDK isolation neither changes nor certifies
ordinary production coexistence behavior.

The case inspects grant and both channel policies before readiness, preserves real readiness,
uses handled case-memory permission attempts and a forwarding real Android observer, and
requires zero permission requests. Provider polling, normal preferences/credentials/bookkeeping,
headless scheduling and watch/widget effects remain outside its injected memory/inert route.
Only successful Continues and their assertions record stages. Null/error/expired `runAsync`
results fail outside `runAsync`, and deadline/vacancy guards precede publication.

Success and failure both unmount and await outstanding refresh, wake completion and queued
alert delivery before reconciling attempted identities, including a lost plugin reply. Cleanup
cancels only matching newly owned posts, preserves unowned or changed identities and restores
pointer/platform state. Unsettled delivery or failed cleanup keeps the outcome incomplete.
Only successful body **and awaited teardown** publish scope
`granted baseline / real FFI and Android adapters`, `completed: true`, the exact ordered
four stages followed by COMPLETE, and one integer attempt/plugin completion per identity.
The stock awaited callback persists available response JSON before validation. Missing, null,
malformed or incomplete reports fail; framework failure/timeout wins over driver/wrapper exit 0.
Retain all old failed REARMED, report and capture diagnostics unchanged.

After the case and driver terminate and owned teardown is established, remove only the owned
forward and restore the **retained actually installed normal APK** through guarded `install -t -r`
with data preserved. Stop on restoration failure without fallback. Reverify its actual installed
and active identity, native libraries, normal operation and preserved current state; inspect
original restoration frames before declaring success. Normal restoration has a separate HOST
budget. Root then completes the full independent whole-Source zero-findings pass and native/audio
acceptance. Ordinary timers/headless work, fresh-channel defaults, Wear, physical devices and
general audibility remain separate claims.
