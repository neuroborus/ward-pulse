# WardPulse Wear OS App

Native Wear OS shell for compact WardPulse dashboard screens.

The app uses Kotlin, Compose for Wear OS Material 3, and Wear Data Layer. It validates the
versioned `WatchDashboardSummary` payload and persists only the latest successful summary.

## Ownership

- Home Glance text legend (`WEAR_GLANCE_DESIGN.md`): mini remaining arcs, OK/!OK refresh,
  Alerts pill. Summary-backed Glance has no clock, including empty selection; Plan windows,
  Alerts, Watch face utility and the pre-summary dashboard retain the straight clock.
- A second page listing plan windows and when each comes back (see **Plan windows** below).
- Alerts screen, reached from the Glance pill — the active list only, no rule editing.
- Watch face setup utility, reached after all Plan windows rows or below the no-summary sync
  prompt. It is a separate swipe-back route; the app still has two home pages.
- Local storage of the latest watch summary.
- Wear-specific navigation, rotary input, shape-aware layouts, and stale data states.
- Wear Data Layer receiver for `/wardpulse/watch-summary`.
- Wear → phone refresh request on `/wardpulse/refresh-request`.
- Ring + strip `RANGED_VALUE` complication data sources for the WardPulse watch face
  (family ColorRamp accents; credits only on the matching provider strip).

Provider credentials are never entered or stored on the watch.
The app shows a neutral sync prompt until the first valid phone summary arrives; it never creates
mock state on its own. Mock summaries are accepted only when explicitly marked by a debug phone
build, and release Wear builds reject them.
The app marks a summary stale when the phone reports stale data or its generation time is at
least two hours old, twice the longest planned MVP polling interval.

The phone and Wear APKs intentionally share the `app.wardpulse` application ID. Their
namespaces remain separate, and paired builds must use the same signing certificate for Data
Layer delivery.

## Entry and dismissal

`MainActivity` uses `singleTop`. Component WFF wordmark launches and existing complication
tokens are actionless; initial delivery and `onNewIntent` return the retained navigation to
Home/Glance, or the no-summary prompt. MAIN/LAUNCHER returns retain navigation. New complication
tokens add `NEW_TASK | REORDER_TO_FRONT | SINGLE_TOP` without changing PendingIntent identity;
already-issued tokens retain their original flags. The canonical component WFF Launch and
missing-app Play routing are unchanged, so this repair requires no face update.

At settled Home, Back and committed Compose swipes background the whole task with
`moveTaskToBack(true)`. They preserve Activity/controller/permission owners and leave other
tasks alone. Nested routes keep their usual Back behavior; canceled previews do not dismiss.
The theme disables inherited window swipe-to-finish so it cannot expose an older same-task
Glance beneath the current owner.

Candidate HOST acceptance is **Pending**. Two added `WardPulseNavigationStateTest` device
cases cover production-composition redelivery/launcher navigation, old-flag tap compatibility,
no-summary entry, recreation, current summaries and retained dismissal. A third case checks
the callback count for committed/canceled root gestures. Production cases use isolated owned tasks
and restore the saved summary; synthetic intents do not prove real WFF/launcher routing.
After Runner retirement, HOST must run the full affected navigation/consent suites on Round,
Square and API34, measure added test cost, and verify real entries, preserving updates/old
tokens and measured historical N=2 same/separate-task records. The dated results below remain
evidence of their earlier builds, not acceptance of this candidate.

## Plan windows

The Glance answers *how much is left*. The second page answers the other question — *when does
it come back* — and that is why it exists rather than repeating the Glance:

```text
  Plan windows

  Claude · 5-hour session      ← coloured by the window's own status
  0% left · back at 19:00

  Claude · Weekly Opus
  6% left · back Aug 25, 12:00

  Cursor · Cursor Models
  100% left · back Sep 1, 00:00

  Codex · Weekly plan          ← no reset in this payload: the line just ends
  9% left
```

Rules:

- **Every plan window, spent or not.** Glance retains selected known exhausted metrics; this
  page adds reset times and the full window inventory. Untouched ones stay too — the list is
  also the inventory of what the watch knows, and hiding them would change its shape from poll
  to poll, leaving "not spent" indistinguishable from "not reported".
- **Purchased meters never appear** (`source: purchased` — Extra usage, on-demand, purchased
  credits). They do not come back; they are bought again. Cursor's on-demand pool does carry an
  instant, but it is the billing cycle turning over, not capacity returning — the page would be
  promising something it cannot deliver. Their home is the phone's cards.
- **Order: exhausted first, then soonest return.** The screen is read when something has run
  out, so what is waited on comes first. A window that cannot name a **future** moment — none
  published, or one already behind — cannot compete for "soonest", so it sorts last inside its
  own group; still listed, just after everything that can name a time.
- **No future moment, no time on the line** — the line simply ends after the percentage, and
  never says "unknown": a provider that publishes no reset is not the same as one publishing an
  unknown. A reset already behind counts as none, because the provider has not caught up with
  its own clock (Cursor aggregates about hourly), and printing a moment that has passed would
  say the window is late rather than that the number is.
- **A window with no share shows its remainder** (`1.7K credits left`, compact as everywhere
  else on the watch — `WEAR_GLANCE_DESIGN.md`, revision 2026-10-11) — a plan whose ceiling
  the provider does not publish, Cursor's among them, still knows how much is left, and a
  remainder at zero counts as exhausted like any full percentage.
- **An unlimited window says so** (`Unlimited`), and one that can say neither a share nor a
  moment reads `Unavailable` — the word the rest of the watch already uses for a meter that
  reported nothing. A blank line under a label would read as a rendering fault, not as silence.
- Time is the device's own clock, and "inside a day" means **today's date**, not the next
  twenty-four hours: `back at HH:MM` for a window rolling today, `back MMM d, HH:mm` for any
  other, so tomorrow evening never reads like tonight.

## Adaptive face complication contract

`WatchSummaryComplications.kt` resolves count, order, pools and semantics from one accepted
summary load per response. Each ordinary/budget/pair/known-zero entry counts once (0..3).
Main selections and extras preserve `RingSurfaceOrder` and split ordinals; invalid resolved
data and obsolete selections return actual `NoData`. A resolved singleton stays a full band.

Semantic percentages/text/descriptions/zero tokens precede generic `TYPE_UNDEFINED` scaling:
MAX200/400/800 encode N1/N2/N3 with factors 2/4/8. VALUE/MAX stays the percentage ratio;
MAX100 remains legacy 20/half 10 for any count, including credits and uncounted previews.
The face decodes each response independently. Valid extras survive an absent delivered main;
there is no cross-slot atomicity promise. Third-party raw-value readers/OEM speech are not
universally supported, and the older slot 109 marker boundary remains documented in
[Split band](../../docs/product/WATCH_RING_DESIGN.md#split-band-revised-2026-09-16).

`WatchComplicationTextTest` covers count/order/pools, independent budgets, semantic ranges,
zero, singleton and obsolete NoData. `AdaptiveRangedComplicationTest`, included in
`just test-wear-device`, invokes actual AndroidX validation and wire/Parcel roundtrips for
legacy and adaptive envelopes, endpoints and fractional semantics. Execution and native
acceptance are **Pending**; no new test/build/device pass is asserted here.

Current packaging is phone 0.1.0+3/Wear 4/legacy 2/Push default 3, all versionNames 0.1.0. Preserve
package identities, signers and release-tool parity; this is not a release cut. The
[adaptive revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-28--adaptive-bands-from-resolved-count)
owns required HOST delivery/retained-binding/transition/true-ambient acceptance and deferred
public captures. Native implementation alone does not close that work.

## Watch face setup

Scroll past the complete Plan windows list and tap **Watch face**. Before the first phone
summary, a compact label-only tonal button appears below **Sync from phone**. It uses the
ordinary full-text tonal button when the measured label width or line height does not fit
the compact component, preserving wrapping, system font scaling and the minimum touch area.
The pre-summary straight clock stays visible, with scrolling content kept clear of it at
every settled position. The heading and start of the sync prompt remain readable initially;
ordinary scrolling makes all prompt text readable, across multiple positions if needed,
and reveals the complete button and label together at a settled usable position.
See the [dated no-summary design](../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-28--compact-no-summary-watch-face-action).
Summary arrival, replacement or loss does not reset this route or a pending permission result.

On supported Wear OS 6+ devices, the bundled Push face can be installed with the Wear app.
If it is missing and a slot is free, **Install watch face** installs it without activating
it. An unknown occupied slot is left untouched; **Check again** only refreshes status after
capacity becomes available. A failed status check has the same read-only recovery action.

**Use watch face** is a separate explicit action. It may request activation permission once;
permission and activation-attempt history is committed before those effects and retained
across recreation. Denial, dismissal or an unavailable/consumed activation opportunity leads
to manual-picker guidance. The app never reactivates a face after the user chooses another.
Only a fresh platform observation can report **In use**.

**Update watch face** appears when the actual bundled version is newer than the installed
Push face. It updates only that package, preserving configuration and face selection. Even
an **In use** face can offer an update. Installation/update completion reports **Installed**;
it does not check current activity immediately after an update. **Try again** repeats only
the failed installation or update. Busy actions are disabled.

On compatible API 34+ devices without Push, the utility checks only the separate
`app.wardpulse.watchface` package. Presence confirms installation and offers manual selection;
absence explains separate installation followed by selection. An unavailable/failed query
says installation could not be checked. **Check again**, revisiting the utility and returning
from an external installation refresh this observation. No Push inventory, installation,
activation or permission operation is used on this path. Package presence proves neither
current selection nor update availability.

Install the separate face only if needed, then choose WardPulse through the watch's available
system or companion selector. OHealth was the owner's observed route on one physical Wear OS 5
watch, not a guarantee for other brands. The installed face, settings and data are preserved.
On Wear OS 4 / API 33 the dashboard remains usable; the utility reports the face as unsupported
without querying packages or attempting installation/activation.

Local development acceptance on **2026-10-16** covers final debug artifacts, API33/API34/API36
emulators, real summary delivery, explicit consent and N1-to-N2 customization/selection
retention. See the [acceptance record](../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance)
for exact evidence, observed system/scroll limitations and remaining production signing,
Play, API35 and hardware gates. The
[dated baseline](../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry)
and [indexed manual-selection capture](../../docs/assets/README.md#watch-face-utility-provenance-and-wear-freshness-2026-10-16)
are integrated. The setup-route change preserves Glance geometry; screenshots have their
own dated capture records.

The durable-consent device tests in `WatchFaceConsentStoreTest`, included in
`just test-wear-device`, verify synchronous on-disk history. The retained-navigation UI
tests use synthetic summary availability; the controller tests use injected effects.
Actual platform consent/data observations are recorded separately in the acceptance record.
The earlier setup-route HOST run passed `just check-wear`, including its validated Push bundle. An actual
API 34 native frame confirms the separately installed face's **Installed. Select WardPulse
from your watch-face list** guidance. Historical consent captures are not that evidence.
`WardPulseNavigationStateTest` holds an old absence across pause/resume, navigation re-entry
and rebuilding the utility from its saved state. Each case simulates external installation
and requires a fresh installed result from the retained controller without Push or consent
effects. Busy refresh requests live in the ViewModel's controller calls rather than a
composition-local flag. `WatchFaceControllerTest` also guards that a queued request after a
supported observation repeats neither inventory nor activity reads. These deterministic
cases ran in the HOST suites: Round's full suite passed 32 tests; Square and API 34 each
passed 12 navigation tests. The controller/navigation/manifest sources match the reviewed
preparatory hashes. These use injected lifecycle/installation events; actual Activity
recreation and real external-installer return remain separate, unverified cases.

## Isolated default instrumentation

`IsolatedWearRunner` selects `IsolatedWearApplication` through `newApplication`, without a
shared test-application manifest. `MainActivityDependencies` supplies only the Activity's
summary store, its ViewModel/controller's durable consent store and refresh dispatch.
Production defaults still use normal preferences and `WatchComplicationUpdater`; production
datasource services still construct `WatchSummaryStore` from their ordinary context.

`IsolatedActivityRule` scopes the existing navigation and consent cases to uniquely named,
private preferences. It keeps the real Activity, ViewModel, controller and store construction,
including retained owners, recreation, resume and synchronous consent claims on disk.
`onStart` executes normally: the runner verifies one recording-sink dispatch per invocation.
Assertions check the actual owners' backing stores, private fixture writes and the normal
datasource-storage constructor. They attribute this suite's effects without requiring live
phone/Data Layer publications to stop or restoring an older value over a newer publication.
These assertions do not establish effective renderer delivery or restoration.

The rule encloses test teardown. Every owned Activity must be destroyed and its lifecycle,
ViewModel and test composition jobs and consent workers retired before the private preferences
are deleted and isolation is released. A timeout fails the case while retaining isolation
and private storage; another default Activity cannot fall back to live dependencies. An
unscoped default launch fails before production store construction. No lifecycle callback
is suppressed and no existing case becomes opt-in. The default inventory remains **40 tests**
across the original six classes, including the distinct multi-owner durable-consent assertions.

**Provisioning and acceptance remain Pending.** This runner requires the rebuilt target APK
containing `MainActivityDependencies`; installing only its test APK cannot isolate the
baseline host. For item12, first complete the guarded stock-runner Push 3→4 witness against
the unchanged original host and bundled asset 3, record the result and separate settled native
observation, restore data and retire that instrumentation owner. Only afterward may ordinary
artifacts be rebuilt with candidate flags absent and the seam-bearing target be provisioned.
If that witness fails or is uncertain, preserve the original target and leave default-suite
acceptance Pending. Do not use a connected suite, `run-wear`, sync recipe or other target
installer to recover. The stock update route must not load this application or launch
`MainActivity`. See the [toolchain ordering](../../docs/ANDROID_TOOLCHAIN.md#wear-instrumentation-provisioning-order).

## Guarded native Push integration

`ManualNativeIntegration` marks six additional cases: `NativePushGuardTest` has three
negative/cleanup cases, including candidate file/FD cleanup on either callback outcome;
the journal case also exercises discovery through fake selection responses into one fake dispatch.
`NativePushUpdateTest` has individually selected `probeBaseline`,
`updateOwnedPush3To4` and `observeSettledUpdate` cases. `IsolatedWearRunner.onCreate` always
excludes that annotation, including explicitly selected manual classes. The original default
inventory remains 40. The stock `androidx.test.runner.AndroidJUnitRunner` entry in the test
manifest follows the configured isolated runner, because AGP applies its runner name to the
first instrumentation element. Verify both entries in the packaged test manifest during HOST.
The stock entry never substitutes `IsolatedWearApplication`. Never invoke the stock
entry without an explicit class/method; it does not isolate the original default tests.

The update class uses Android, the baseline Push SDK 1.0.0/complications 1.2.1 APIs and test-local helpers. It
does not reference the production wrapper, isolation ABI or `MainActivity`. `NativePushDevice`
resolves the baseline SDK method before mutation, verifies the ordinary target Application,
canonical emulator/image/display, original host code 4/APK/signer, actual bundled asset 3
archive and installed Push 3. All manager observations use `targetContext`, retaining the
host's ownership. Expectations are from fresh independent HOST observations **before** test-APK
provisioning, never from a newly installed target or a synthetic old baseline.

`NativeRenderer.parse` reads the applicable active runtime's instance, interactive state,
user style, enabled slots and cached delivered-data provenance. Neither a delivered
`dataSource` nor default datasource policy proves which provider is currently selected.
`NativeSelections` represents independent selection records for the exact resource package,
instance and all eight slots, including explicit empty choices. Only those records can supply
the five fixed lower bindings and three upper choices in the configuration fingerprint.
Changing a selection while cached delivery remains unchanged fails retention; changing cached
provenance alone does not change the selection fingerprint.

`NativePushDevice.readRenderer` queries the baseline's existing
`ComplicationDataSourceInfoRetriever.retrieveComplicationDataSourceInfo` for slot IDs discovered
from the actual active runtime. This API returns selected-provider configuration independently
of cached delivery. Its component-scoped results are accepted only while that same wallpaper
component has a single native registry/engine instance with matching IDs and resource package
before and after the query. Multiple instances, transitions, incomplete/null responses,
missing provider identities or denied access leave configuration retention **Pending before
dispatch**. A null response is unavailable; a null provider entry in a complete response is an
explicit empty selection. The five lower selections must still match their required services.
Caller-supplied expectations cannot supply missing records. Do not select providers, publish
fixtures or infer selections to make the guard pass.

The selection query uses a finite timeout without retries and tracks the service connection
before retriever construction. Closing the retriever and its scoped context releases bindings
on success, timeout and partial-construction failure. It creates no face instance and adds no
dependency or permission. Actual service access, API applicability and instance mapping remain
HOST verification duties. The reader observes only the active renderer: with legacy active it
cannot verify the inactive Push face's own existing instance/configuration.
`requirePushConfiguration` leaves that route Pending without activation; a legacy snapshot cannot complete the Push witness or
permit target replacement. No face is activated or reselected.

`AttemptJournal.dispatch` durably arms one SDK call and retains successful or uncertain
advancement in private `files/native_push_update/attempt.json`. The exact generated APK/token
pair is opened privately; every temporary APK/descriptor is owned through callback completion
and cleaned on success/failure. The manager has no public close API. No detached operation,
timeout cancellation, retry, downgrade or version loop is used. A missing callback leaves
that instrumentation owner unresolved; do not start another owner or replace the target.
Returned identities and installed APK/resource bytes are checked and recorded before any
later observation, which also requires the explicit successful resource-cleanup record.
There is no post-update `isWatchFaceActive` call. A dispatched record,
including an interrupted write, prevents another update; retain it for reconciliation.
SDK-result verification alone leaves `pushConfigurationRetention` and `targetReplacement`
Pending in the private receipt.

HOST later selects `observeSettledUpdate` once, after independent native settlement. It
requires the updated Push face's own instance and authoritative selections, separately from
delivered provenance; unavailable evidence fails Pending before capture. A legacy-only result
cannot mark Push configuration retention verified. When the required evidence is available,
it checks the original host/asset, candidate bytes, owned slot and retained Push configuration,
then captures one original PNG through this instrumentation's existing UiAutomation and
recycles the bitmap. Observation is armed once before capture, including failure paths, so
another invocation cannot overwrite the first frame. The private
`files/native_push_update/settled-original.png` needs HOST
inspection for a complete unobscured frame; the case's success is not visual acceptance.
No concurrent hierarchy owner is permitted. No summary, consent, binding, setting or bridge
is changed by these cases, so cleanup does not overwrite live producer data. Intended Push
advancement stays installed, including an uncertain advancement; never restore Push 3.
Any unverified retention/restoration remains Pending. Tokens/raw native records are not
logged; public diagnostics contain only bounded identities/hashes or sanitized reason codes.

Build/provision/run instructions and the strict pre-replacement ordering are in
[Guarded Push witness](../../docs/ANDROID_TOOLCHAIN.md#guarded-push-witness).
Candidate provenance belongs to
[the generated test bundle](watchface_push/README.md#native-integration-candidate).
Compilation, guards on actual devices, SDK results, settled rendering and restoration are
all **Pending** until ordered HOST execution after the whole Runner run retires. This harness
does not close the utility-button gap, earlier manager-update gaps or historical causality.

## Commands

From the repository root:

For item12, the provisioning order above applies before any target-installing command below.

```sh
just check-wear
just build-wear
just test-wear-device
just run-wear
```

`MiniRemainingArcPaintTest` is a focused device regression that reads bitmap pixels from
the production mini-arc painter at 384/450 and 360/450 scales. It distinguishes coloured
4% from track-only zero, checks proportional short-span extent through 4.6%/4.8% with
bounded raster tolerance, and covers both paired palettes, ordinary round ends and the
near-full usage gap. It does not establish screen fit or native scene acceptance.

`GlanceLegendLayoutTest`, also included in `just test-wear-device`, measures native text at
360/384/466 target sizes. It covers the preferred 27/23 ordinary three-row/detail scene,
independently rounded complete rows, bounded fitting, scaled wrapping/exhaustion spans,
height-only overflow and the small-font arc floor. `WardPulseNavigationStateTest` adds a
bounded ActivityScenario case with synthetic in-memory summaries at composition-local 2×
text scale. It targets the local legend and Home Pager separately, invokes actual forward/
backward accessibility scroll/page actions and checks visible movement, Glance isolation,
page changes/return and clock visibility through navigation, empty selection, summary changes
and recomposition. It changes no device settings and accesses no provider data.
Its focused back-preview case checks that the dismissing page's clock moves/clips with that
page, restores after cancellation and leaves no clock on Glance after completion. The case
uses horizontal touch input on legacy hosts and predictive-back dispatcher events on API 36+.
On 2026-10-25, Round's full native suite passed 32 tests; Square and API 34 each passed 12
navigation tests, including local/Pager accessibility actions. Physical 466 active Glance
was verified while charging and securely unlocked. This does not establish every physical
gesture, rotary path, Activity recreation or unrun historical matrix under the
[clock-free revision](../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-24--clock-free-glance-and-larger-legend).
Earlier 20/18 iteration results do not validate the revised Source. Integration
preserves the admitted Glance SVG/PNG bytes and imports the separately generated face artwork.
The shared asynchronous preview helper is compatible with the newer Glance caller's awaited
API. After retirement, a separate HOST throwaway checkout ran the unchanged runtime-face,
face-review and Glance-review generators to normal exit 0; all 136 outputs matched the
reviewed checkout. Canonical exports were not regenerated by that verification.
The complete canonical paired `just test-phone-watch-sync` HOST gate
passed after fresh Reader Java/DEX and Flutter builds and a renewed 32-test Wear suite,
including bounded quiet handoff, process deaths, delivery/relaunch and retention checks.
Native fit and screenshot freshness have their separate bounded evidence above.

HOST only, from `apps/wear_android`, after the whole Runner run is DONE and all owned
processes/leases have retired:

```sh
ANDROID_SERIAL=<serial> ./gradlew --no-daemon connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.wardpulse.wear.ui.MiniRemainingArcPaintTest
```

Before this invocation or any other candidate upgrade, preserve a fresh old-installed-APK
native 4%-remaining failure witness bound to compiled Source/APK, scene, shape and time;
if unavailable, HOLD for reconciliation. Candidate GREEN and full unchanged
`just check-wear`, `just test-wear-device` on both shapes, `just check-docs` and applicable
finalization checks remain external duties, as do native scene review and safe restoration.

`test-wear-device` and `run-wear` require one active Wear AVD. Canonical AVD names and setup
commands live in
[`docs/ANDROID_TOOLCHAIN.md`](https://github.com/neuroborus/ward-pulse/blob/main/docs/ANDROID_TOOLCHAIN.md).
