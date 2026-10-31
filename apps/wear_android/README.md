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

`WatchSummaryStoreTest.creditsAndBudgetFixturesBuildExactComplicationEnvelopes` decodes seven
canonical schema-9 mock fixtures through its private store, retaining clear/delete cleanup:
`watch_dashboard_summary_credits_only.json`, `watch_dashboard_summary_plan_credits.json`,
`watch_dashboard_summary_n1_full_below.json`, `watch_dashboard_summary_n1_full_above.json`,
`watch_dashboard_summary_n1_week_near_full.json`, `watch_dashboard_summary_n2_week_day.json`
and `watch_dashboard_summary_n2_month_month.json` under `fixtures/snapshots/`.
The cohort covers the real credits-only MAX100 row (`500`, Codex color, `credits` TITLE,
current description `500 100%`), per-family purchased credits (`37% · 320` despite aggregate
400), both Float neighbors of the N1 full44 cutoff, a near-full weekly MAX200 value that
rounds to `100%`, reversed week/day radial placement and independent month/month IDs and
Money at MAX400. Literal oracles cover decoded order and nullable fields, selected IDs,
TITLEs, family colors, unscaled text/descriptions and obsolete main/extra `NoData`.
This adds decoder/construction coverage only; execution, service delivery and WFF paint
remain **Pending**. Existing Android API/Parcel coverage retains its separate scope.

`WatchSummaryStoreTest.n1PairedFixturesKeepIndependentEndpointsAndCutoffs` adds seven
schema-9 singleton Codex/Spark fixtures: `watch_dashboard_summary_n1_pair_zero_full.json`,
`watch_dashboard_summary_n1_pair_tiny_near_full.json`,
`watch_dashboard_summary_n1_pair_below_above.json`,
`watch_dashboard_summary_n1_pair_above_below.json`,
`watch_dashboard_summary_n1_pair_near_full_tiny.json`,
`watch_dashboard_summary_n1_pair_full_zero.json` and
`watch_dashboard_summary_n1_pair_both_zero.json` under `fixtures/snapshots/`.
Independent oracles cover decoded pool identities and null Money, MAX200 envelopes,
Codex/Spark colors, literal `split:spark` zero suffixes, extra ordinal 0/TITLE `0`, and
obsolete main/ordinal-1 `NoData`. Each half brackets its own N1 22-unit cutoff; a positive
0.03125 remainder retains VALUE 0.0625 and the ordinary paired TITLE despite `0%` text,
while the near-full Float stays below MAX despite `100%` text. Exact zero/full endpoints,
unscaled labels/descriptions and private-store cleanup remain covered. These are
decoder/construction witnesses; service delivery and WFF paint remain **Pending**.
Existing ordinary44 zero/tiny/full and paired partial controls keep their separate scope.

`WatchSummaryStoreTest.n2CutoffFixturesKeepExactRadialAndPoolRouting` adds six schema-9
fixtures under `fixtures/snapshots/`: `watch_dashboard_summary_n2_inner_pair_below.json`,
`watch_dashboard_summary_n2_inner_pair_above.json`,
`watch_dashboard_summary_n2_inner_full_below.json`,
`watch_dashboard_summary_n2_inner_full_above.json`,
`watch_dashboard_summary_n2_outer_pair_below.json` and
`watch_dashboard_summary_n2_outer_pair_above.json`.
They bracket every N2 full32/inner16/extra16 cutoff with Float neighbors at both
outside indices while preserving tightest-first payload order. Literal oracles assert
decoded identities, usage and null Money, MAX400 values, main selection, Spark ordinal 0
at outside index 1 or 0, TITLEs, family colors and unscaled text/descriptions. The tiny
ordinary remainder stays positive despite `0%` text; true zero uses `zero`. Obsolete main
and ordinal-1 extra selections clear. Private-store cleanup remains unchanged. These are
decoder/construction witnesses only; execution, service delivery and WFF paint remain
**Pending**, with Android API/Parcel coverage retaining its separate scope.

`WatchSummaryStoreTest.n2EndpointFixturesKeepBothSplitOrdinalsAndClearObsoleteExtras` adds
six schema-9 fixtures under `fixtures/snapshots/`:
`watch_dashboard_summary_n2_pairs_zero_tiny.json`,
`watch_dashboard_summary_n2_pairs_tiny_zero.json`,
`watch_dashboard_summary_n2_full_zero_tiny.json`,
`watch_dashboard_summary_n2_full_tiny_near_full.json`,
`watch_dashboard_summary_n2_full_full.json` and `watch_dashboard_summary_n2_full_zero.json`.
Literal oracles cover decoded identities, tightest-first tie order, null Money and credits,
MAX400 values, TITLEs, family colors and unscaled text/descriptions. Both Codex/Spark and
Cursor Models/Other orientations retain their true-zero suffixes while positive 0.03125
remainders keep VALUE 0.125 despite `0%` text. Split ordinal 0 is Spark/TITLE `1`; ordinal 1
is Other Models/TITLE `0`. Each paired input is followed by an ordinary summary in the same
private store, clearing both extras as actual `NoData` without changing the band count.
Together with the month/month fixture, the ordinary32 inputs cover zero, tiny, near-full
and full at both radii; near-full stays below MAX despite `100%` text. Obsolete main
selection and clear/delete cleanup remain covered. Existing paired16 partial/full/near-full
controls retain their separate scope. These are decoder/construction witnesses only;
execution, service delivery and WFF paint remain **Pending**. Android API/Parcel coverage
retains its separate scope.

`WatchSummaryStoreTest.n3CutoffFixturesKeepExactRadialAndPoolRouting` decodes
four schema-9 fixtures under `fixtures/snapshots/`:
`watch_dashboard_summary_n3_middle_pair_below.json`,
`watch_dashboard_summary_n3_middle_pair_above.json`,
`watch_dashboard_summary_n3_inner_pair_below.json` and
`watch_dashboard_summary_n3_inner_pair_above.json`.
They bracket the N3 middle/inner 10-unit paired-half cutoffs and outer/middle 20-unit
ordinary cutoffs with Float neighbors of the published six-decimal boundaries. The existing
legacy/N3 rounded-boundary clamp qualification remains unchanged. Literal oracles cover
decoded tightest-first order, independent pool identities and usage, null Money and credits,
MAX800 envelopes, family colors and unscaled text/descriptions. The middle Spark is ordinal 0
with TITLE `1`, and ordinal 1 clears; the inner Spark is ordinal 0 with TITLE `2`, alongside
Cursor Other at ordinal 1/TITLE `0` with independent full/near-full values. A positive 0.03125
ordinary remainder keeps VALUE 0.25 and an empty TITLE despite `0%` text. Obsolete main
selection and private-store clear/delete cleanup remain covered. These are decoder/construction
witnesses only; execution, service delivery and WFF paint remain **Pending**. Existing Android
API/Parcel coverage retains its separate scope.

The same N3 test adds four more schema-9 fixtures under `fixtures/snapshots/`:
`watch_dashboard_summary_n3_inner_full_below.json`,
`watch_dashboard_summary_n3_inner_full_above.json`,
`watch_dashboard_summary_n3_outer_pair_below.json` and
`watch_dashboard_summary_n3_outer_pair_above.json`.
They bracket the remaining inner 20-unit full-band and outer 10-unit paired-half cutoffs
with Float neighbors of the published six-decimal boundaries, preserving the existing
rounded-boundary clamp qualification. Literal MAX800 oracles retain independent Codex/Spark
and Cursor Models/Other full/near-full values in the two-pair rows, with Spark at ordinal 0/
TITLE `1` and Other at ordinal 1/TITLE `0`. The lone outer Cursor pair uses ordinal 0/TITLE
`0`, and ordinal 1 clears as actual `NoData`; the ordinary tiny Codex value stays positive
beside true-zero Claude. Decoded identities, order, null Money and credits, family colors,
unscaled text/descriptions, obsolete main selections and private-store cleanup remain covered.
These are decoder/construction witnesses only; execution, service delivery and WFF paint
remain **Pending**. Legacy MAX100 fixed geometry retains its existing declaration/API coverage;
these adaptive fixtures provide no legacy-count evidence.

`WatchSummaryStoreTest.n3EndpointFixturesKeepExactValuesAndReplaceSameCountSelections` covers six
schema-9 fixtures under `fixtures/snapshots/`:
`watch_dashboard_summary_n3_pairs_zero_tiny.json`,
`watch_dashboard_summary_n3_pairs_tiny_zero.json`,
`watch_dashboard_summary_n3_outer_pair_zero_tiny.json`,
`watch_dashboard_summary_n3_outer_pair_tiny_zero.json`,
`watch_dashboard_summary_n3_full_tiny.json` and `watch_dashboard_summary_n3_zero_tracks.json`.
Literal oracles cover tightest-first tie order, decoded pool identities, null allowance Money
and credits, MAX800 values, TITLEs, family colors and unscaled text/descriptions. Zero/tiny
halves at all three radii retain their split identities and exact zero-side suffixes; positive
0.03125 remainders keep VALUE 0.25 despite `0%` text. Spark uses ordinal 0/TITLE `2` and Cursor
Other ordinal 1/TITLE `1` in the two-pair rows; the lone outer Cursor Other uses ordinal 0/
TITLE `0`, and ordinal 1 clears. Both-zero pairs keep `zero-both` suffixes beside the exhausted
OpenAI month budget, which retains TITLE `M`, USD 10000/10000 minor units and `$100.00/100`
text. Following that summary with three ordinary tiny bands in the same private store clears
both extras as actual `NoData`. The near-full ordinary Float stays below MAX despite `100%`
text. Obsolete main selection and clear/delete cleanup remain covered. These are
decoder/construction witnesses only; execution, service delivery and WFF paint remain
**Pending**. Existing Android API/Parcel coverage retains its separate scope.

The same N3 endpoint test adds six schema-9 fixtures under `fixtures/snapshots/`:
`watch_dashboard_summary_n3_pairs_near_full.json`,
`watch_dashboard_summary_n3_pairs_full_near.json`,
`watch_dashboard_summary_n3_full_near_full.json`, `watch_dashboard_summary_n3_full_full.json`,
`watch_dashboard_summary_n3_reorder_before.json` and `watch_dashboard_summary_n3_reorder_after.json`.
Literal oracles cover decoded identities, tightest-first tie order, null allowance Money and
credits, MAX800 values, TITLEs, family colors and unscaled text/descriptions. Both orientations
of Codex/Spark and Cursor Models/Other preserve independent full/near-full halves; ordinary
bands cover full and near-full at all three radii. The near-full Float remains
99.9000015258789 with VALUE 799.2000122070312, below MAX800 despite `100%` text; full is VALUE800.
The reorder pair is saved and decoded consecutively in the same private store without changing
the three-band count. All main slots change owners: outside-to-inside Claude/Cursor/Codex becomes
Cursor/Codex/Claude. Extra ordinal 0 changes from Spark/TITLE `2`/remaining70 to Cursor Other/
TITLE `0`/remaining95; ordinal 1 changes from Cursor Other/TITLE `1`/remaining80 to actual `NoData`.
The removed Spark identity, replacement order, obsolete selections and clear/delete cleanup
remain covered. These are decoder/construction witnesses only; execution, service delivery
and WFF paint remain **Pending**.

`AdaptiveRangedComplicationTest.creditsAndReorderedExtrasRoundTripWithExactWireContracts`
adds Android validation and Parcel roundtrips for the production credits-only construction
(VALUE/MAX100, TITLE `credits`, Codex color, TEXT `500`, description `500 100%`) and the
three distinct reordered extra envelopes: Spark/TITLE `2`/VALUE560, Cursor Other/TITLE `1`/
VALUE640 and Cursor Other/TITLE `0`/VALUE760, all extras at MAX800. Literal oracles retain
unscaled text/descriptions and pool colors, with every Parcel recycled in `finally`.
Existing envelope tests remain separate; this API coverage establishes neither service
delivery nor WFF paint, and its execution and native acceptance remain **Pending**.

Current packaging is phone 0.1.0+3/Wear 4/legacy 2/Push default 5, all versionNames 0.1.0. Only
the guarded Push default advances 3→5; preserve package identities, signers, positive property
validation and release-tool guards. Historical candidate 4 flags/instrumentation and the real
3→4 journal remain intact; this is not a release cut. The
[adaptive revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-28--adaptive-bands-from-resolved-count)
owns required HOST delivery/retained-binding/transition/true-ambient acceptance and deferred
public captures. Native implementation alone does not close that work.

The [current qualification](../../docs/product/RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30)
retains all six Push/Legacy compatibility cells, explicit Root-reviewed forward-only
reconciliation for unavailable history, the sole Native FINALIZE inventory and all nine HOST
duties after whole DONE/process retirement/CLI exit/fresh idle. Round Wear4/asset3/Push4 with
Legacy active was the historical typed-API/guard cohort. The recorded current host is
Wear4/asset5. Current operations must retain actual Push5, obtain separate admission and freshly
verify installed APKs/signers, owned manager slot and active state. The later full recipe
advanced Push 4→5 before tests; the failed preservation and missing ordinary UI 4→5 witness
remain gaps. No code 6, replay,
downgrade, reset or invented button success is authorized.
Later retained-Push selection/rendering is separate HOST work. Item12 stays open and both
extras queued; this allocation claims no check, device, public or release result.

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
Equal private and normal bytes are valid and do not establish publication provenance.
`WardPulseNavigationStateTest.productionRedeliveryKeepsOwnersAndLauncherNavigationWithoutReplayingConsumedFaceEntry`
extends the existing owner case with private normal-storage stand-ins: equal pre-existing
state is accepted, a valid newer producer value survives private saves/removal, and actual
backing-store aliasing is rejected. Live normal preferences are never seeded for these checks.
These assertions do not establish effective renderer delivery or restoration.

The rule encloses test teardown. Every owned Activity must be destroyed and its lifecycle,
ViewModel and test composition jobs and consent workers retired before the private preferences
are deleted and isolation is released. A timeout fails the case while retaining isolation
and private storage; another default Activity cannot fall back to live dependencies. An
unscoped default launch fails before production store construction. No lifecycle callback
is suppressed and no existing case becomes opt-in. The current default inventory is **47 tests**
across the original six classes: original40 plus seven necessary fixture/API tests, retaining
the distinct multi-owner durable-consent assertions.

**Recorded PASS and current acceptance are separate.** The later full recipe genuinely passed
47 tests, excluding manual cases, and advanced Push 4→5 before tests. Current installed Wear4/
asset5 APK `097c337f…` and retained Push5 APK `4ed262fa…` are distinct from the old host/asset3
and real SDK 3→4 journal. Preserve all historical originals/receipts. The failed preservation
and missing ordinary UI 4→5 witness remain separate gaps; no downgrade, reset, code6, replay
or retroactive UI witness is authorized. That PASS does not validate new test bytes or native
paint. Current native viewport, active artifact identity, geometry and broader item12 acceptance
remain Pending.

This runner requires a compatible target APK containing `MainActivityDependencies`; installing
only its test APK cannot provide a missing seam. After whole execution DONE, owned-process
retirement, owning CLI exit if used and fresh separate idle, HOST must reconcile the complete
direct/implicit provisioning footprint and candidate order before actual test-APK provenance/
install admission and default-suite execution on the correctly provisioned owning candidate.
The empty Push-module AGP runner skip is established; app-only is not a proved remedy. Do not
replace a target to manufacture read capability or use target installation as recovery.
Ordinary Source 5 builds require candidate flags absent. The historical stock route must not
load this application or launch `MainActivity`. Retain the
[historical qualification](../../docs/product/RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30) and see the
[toolchain ordering](../../docs/ANDROID_TOOLCHAIN.md#wear-instrumentation-provisioning-order).

## Guarded native Push integration

The following describes the historical candidate 4/Push 3→4 harness contract. Preserve its
instrumentation, flags and actual private journal; this is not authorization to replay it
against retained Push 5. Current delivery uses the separately guarded current-target path
below; the historical contract grants no current operation authority.

`ManualNativeIntegration` marks **48** additional cases: `NativePushGuardTest` has three
negative/cleanup cases, including candidate file/FD cleanup on either callback outcome;
the journal case also exercises System/controller/native discovery fixtures into one fake dispatch.
Those existing cases additionally reject incomplete/ambiguous installed-path enumeration,
unavailable archive/signing identity and changed files/paths, and check locator/ZIP/stream
cleanup and sanitized diagnostics through partial failures. Existing subcases cover strict System/
controller/facade/engine joins, incomplete inventories, transitions, configured-type meaning,
explicit empty choices and caller diagnostic isolation. A private shell-output fixture
also exercises the locator's actual `Runtime.exec(String)` launch contract, including success,
failure and multiple paths, without querying installed packages. They add no discovered test cases.
`NativePushUpdateTest` has individually selected `probeBaseline`,
`updateOwnedPush3To4` and `observeSettledUpdate` cases. The datasource classes below add thirteen
(six observation methods, four datasource guards and three SDK direct-data guards),
and the client classes add fourteen (three guarded native methods, ten synthetic guards and
one independent metadata observation). The typed-config classes add six (one observation and
five synthetic guards). The inventory classes add nine (two observations and seven synthetic guards).
`IsolatedWearRunner.onCreate` always
excludes that annotation, including explicitly selected manual classes. Source discovery is
47 default + 48 manual = 95 tests; packaged discovery/execution of these bytes remains a HOST
duty. The stock `androidx.test.runner.AndroidJUnitRunner` entry in the test
manifest follows the configured isolated runner, because AGP applies its runner name to the
first instrumentation element. Verify both entries in the packaged test manifest during HOST.
The stock entry never substitutes `IsolatedWearApplication`. Never invoke the stock
entry without an explicit class/method; it does not isolate the original default tests.

The update class uses Android, the baseline Push SDK 1.0.0/complications 1.2.1 APIs and test-local helpers. It
does not reference the production wrapper, isolation ABI or `MainActivity`. `NativePushDevice`
resolves the baseline SDK method before mutation, verifies the ordinary target Application,
canonical emulator/image/display, original host code 4/APK/signer, actual bundled asset 3
archive and installed Push 3. All manager observations use `targetContext`, retaining the
host's ownership. Independent HOST observations before test-APK-only provisioning bind the
original host/asset, APK/signers and selected package/runtime, never a newly installed target
or synthetic baseline. After the fresh full warm `just check-wear`, candidate/test-APK
provenance, test-only provisioning, unchanged host/asset recheck and all seven private Android
guards, exactly one read-only stock `probeBaseline` discovers the slot/instance/authoritative
configuration hashes before SDK dispatch. That probe itself exercises the changed observer;
require no additional live observer invocation. A first post-provisioning fingerprint does not
prove earlier full selection retention.

`NativePackage.read` resolves installed Push paths through the instrumentation's existing
UiAutomation using one fixed package-path command and a success-completion marker. The
explicit shell receives a single `-c` script argument under UiAutomation's whitespace
tokenization; argument separators expand inside that script. The output reader reads at most
4097 bytes, accepts at most 4096, and requires exactly one allowlisted base-APK path
plus the complete marker; absent, malformed, truncated or additional paths stay Pending.
This complete enumeration establishes no installed splits independently of archive metadata.
The shell locates only: the normal target UID streams the actual file's full hash, reads real
archive package/code/single-signer metadata and hashes `resources.arsc` from that APK. It then
rehashes and re-resolves the installed path. These observations do not claim atomicity.
The shared route also serves the unchanged datasource and client probes; post-update resource
verification uses its result without a second visibility-sensitive application-info lookup.
Expected hashes, bundled asset 3 and candidate 4 never supply missing installed evidence.
Unreadable files, denied access or null/incomplete archive/signing evidence remain Pending;
no manifest query, permission or SDK caller-context change is used. Locator descriptors,
binary streams and ZIPs close on success/failure, and private asset/candidate copies are cleaned.

`NativeDiagnostics` emits closed phase/category names, bounded contemporaneous observation
byte counts/SHA-256/completeness, inventory counts/completeness and semantic-match flags.
Caller `WallpaperManager` results are reported only as null/match/mismatch/error; none supplies
authority, bypasses proof or replaces the first actual failure. That failure survives cleanup.
No raw dumps, payloads, exception text/causes, tokens, opaque IDs or arbitrary guard strings
are emitted. Status-transport failure cannot prevent cleanup. The old generic rejection's
exact cause remains unproved. The unsupported retriever query was never reached; neither a
query failure nor a server rejection was measured. Installed archive/signing and SDK runtime
capability still require fresh HOST evidence.

`NativePushDevice.readRenderer` uses bounded read-only `am get-current-user`, `dumpsys wallpaper`,
`dumpsys wear_service` and active-runtime service observations through the existing UiAutomation
owner, with a 2 MiB bound per record. It observes the current user's System display/component
and matching live connection, then the native frame, active configuration, native frame and
System state again. All owned shell streams/descriptors close on success and failure. Caller-visible wallpaper identity and
the unsupported cross-package `ComplicationDataSourceInfoRetriever` route supply no proof.

The scoped `ComplicationsConfigController.activeConfigs` must join its favorite/resource to
one IDLE, non-fallback ANDROIDX active facade and its explicit current-engine/wallpaper-component
chain. The native service's user/display/component, sole registry/engine instance, resource
package, style and enabled slots must agree with matching semantic System/native frames around
configuration. Relative dump counters and delivered values are outside that comparison. These
bracketed observations do not establish atomicity or permanent freshness. Expected arguments
only compare against independently observed evidence.

`NativeSelections` requires declared size, actual row count, unique slot coverage and enabled
states to agree with all eight native slots. Missing, duplicate, conflicting, transitional,
pending-action or unresolved scoped records remain **Pending/HOLD before dispatch**. System
fallback/default or lock-only state, caches, databases, history and defaults cannot replace
missing active evidence. Only an observed `provider=null` is an empty choice. All five exact
lower bindings and all three upper choices feed the unchanged style/enabled/provider
fingerprint. Cached `dataSource` is delivery provenance only: changing selections with unchanged
cached delivery fails retention, while changing cached delivery alone leaves that fingerprint
unchanged. Configured type is carried as configuration meaning, independently of delivered,
NoData, supported or overridden types; it adds no cross-domain equality guard.

Favorite and native instance remain separate opaque identities; no `wfId` is constructed from
a favorite. Configuration row IDs supply neither slots, canonical IDs nor C3 requester IDs;
requester provenance still requires its separate proof. No new across-update favorite-ID
guarantee is claimed. Unsupported strict joins stay Pending/HOLD. The reader observes only the
active renderer: legacy-only evidence cannot verify the inactive Push configuration or
authorize target replacement. The harness creates, activates and reselects no instance.

**Adopted HOST scope, 2026-10-29.** The post-DONE scope permits **one** ordinary system-picker
selection of a pre-existing, configured, owned Push 3 instance on the verified canonical
**Round AVD**, after whole DONE/retirement/fresh idle. Record original Legacy state and the
deliberate changed baseline; preserve original host 4/asset 3 through the stock witness.
Follow the [limited procedure](../../docs/ANDROID_TOOLCHAIN.md#guarded-push-witness) and restore
exact original Legacy selection/settings while retaining intended Push 4. No instance creation,
SDK/app activation, new permission or binding/style edit is included. That one selection
established the historical Push 3/wf16 witness. Preserve the subsequent historical
Push4/Legacy-active baseline evidence and actual restoration receipts. Current operations
retain actual Push5 with freshly verified installed identities; this historical allocation
authorizes no new selection.
Original Legacy15 settings/choice restoration still needs independent verification; active
Legacy alone does not prove it. This HOST
boundary supplies no native acceptance or retrospective permission for a frozen run.

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

## Guarded normal datasource observations

For normal delivery, `NativeDatasourceTransitionTest` exposes three stock-runner manual cases: `probeDelivery`,
`observeDelivery` and `observeRestoration`. `NativeDatasourceGuardTest` has four private
admission/selection/mapping/cleanup cases, with no live preferences or manager mutation. These
seven cases remain excluded from the current 47 defaults. HOST compilation, guard execution,
provisioning and runtime observations follow whole execution DONE, all owned-process retirement,
owning CLI exit if used and separate fresh idle. Preserve historical old-host obscured probe
originals/receipts unchanged and retain actual Push5. Reconcile current provisioning as above;
this harness installs or activates nothing.

Both datasource and guarded client entry points reuse `NativeReadAdmission` for their exact
method/opt-in, canonical emulator/image/display and actual current caller UID/package/APK/signer.
Mapping/frame reads require current resource/runtime APK/signer, active instance, complete-eight
selections and intended targets. They require no historical update entry resolution, update
journal, old package cohort or quiet writers. The historical `NativePushUpdateTest` SDK 3→4
path retains its original arguments, guards, witnesses, journal and recovery meaning.

`readNativeDeliveryTargets` and `discoverDeliveryTargets` in
[NativeDatasourceState.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeDatasourceState.kt)
reuse the public `readNativeTypedConfigs` producer from
[NativeTypedConfigTest.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeTypedConfigTest.kt).
The actual target UID calls Wear SDK 35.1 `ComplicationsManager.getActiveComplicationConfigsAsync`;
availability, manager acquisition, callback outcomes and raw typed configs remain separate
private evidence. This API supplies **own-provider** metadata, not all-provider selections.
No client access, privilege, reflection, dependency or alternate producer is required.

The existing `readNativeSelections` grammar supplies the complete eight-slot
controller/favorite/facade/current-engine chain, including explicit null providers, configured
types and enabled states. Raw controller row IDs are retained separately and do not change
historical configuration fingerprints. Each typed system ID must match the unique actual
controller row for its returned slot, owned provider, configured type and resource package
with null WFF class. Caller UID/package/APK/signer, installed resource/runtime identities,
System connection and the full native selection scope bracket the typed read. Numerical
agreement, offsets, ordering, provider-only joins, scene IDs, cached data and default policy
cannot supply missing authority. Incomplete, duplicate, foreign, changed or unresolved
associations leave the route **Pending before publication**.

`NativeRenderer.configuration` in
[NativePushState.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativePushState.kt)
requires one current selected component for each Today, Week, Ring3, RingSplit and StripSplit
role, independent of native slot order. Its fingerprint still serializes the actual eight
per-slot selections and enabled states, including explicit nulls. A reordered controller
observation does not complete the fresh typed/controller/native SDK association above;
configured types establish neither delivered values nor NoData, and neither observation
establishes delivery or paint evidence.

Fresh `files/native_read/requester-*/receipt.json` files retain producer and bracket outcomes.
New resource reads identify resource-package and runtime-package suboperations separately;
prior ambiguous `beforeResource` evidence stays unresolved. An uninvoked client acquisition
is not an access result or evidence of a package-visibility cause. Both datasource and direct-data
consumers use this same mapping. All five lower services must be selected and enabled.
For an active owned Push resource, `readNativeDatasourcePushScope` reuses `readNativeOwnedPush`
before and after the typed read. It requires stable caller-owned inventory, the actual resource
version, the independently expected manager-slot hash and active status, and retains the exact
package/version/manager-slot/active/configuration scope. A Legacy-only read never acquires Push
inventory or requires Push ownership. Missing ownership for a Push target stays Pending without
add/update/activation. Private mapping receipts retain raw inventory operations alongside typed
producer outcomes. `NativeDeliveryMapping.scopeSha256` binds the caller, resource/runtime,
System, full-eight native and applicable Push scope to first-frame and restoration receipts;
it supplies evidence, never write authority, and leaves historical configuration fingerprints intact.

`NativeDatasourceProbe` in
[NativeDatasourceProbe.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeDatasourceProbe.kt)
requires explicit `deliveryProbeId` for both `probeDelivery` and `observeDelivery`. IDs match
`[a-z0-9][a-z0-9_-]{0,63}`. `probeDelivery` reserves `files/native_datasource/probes/<id>/`
once, capturing `first.png`, `first.json` and a final `receipt.json`. A failed/partial read
consumes that ID; there is no overwrite, automatic retry, preferred-probe scan or fallback.
The historical `files/native_datasource/probe/` is never read, migrated or rewritten by this
selector. Each new first read checks the full current provenance again after capture.

HOST independently inspects the selected private `probes/<id>/first.png` for a complete
unobscured frame, then supplies `expectedDeliveryProbeSha256` for that exact receipt and
`expectedReviewedFrameSha256` for that exact PNG, plus explicit review/precondition attestations.
Selection verifies both hashes, the native-record digest and current host/instance/configuration/
mapping/full-scope provenance. Incomplete, ambiguous sidecar, changed or cross-scope evidence
is rejected. The immutable receipt's `frameReview=Pending` stays unchanged: review is an
independent HOST duty. New read evidence supplies no publication authority. Before controlled
writes, HOST must independently establish quiet summary producers, an unpaired bridge with no
connected nodes and no in-flight `WatchSummaryListenerService`; record and later restore the
original HOST bridge configuration. The test rechecks its explicit HOST precondition and
listener-service state before publications and cleanup. It never edits the bridge, disables
a receiver, pauses a producer or changes settings itself. These
observations cannot prove the absence of every future write. Quiet-writer ownership is a HOST
precondition; concurrent phone/Data Layer publications remain legitimate.

`observeDelivery` selects one finite `normal`, `delayed`, `obsolete` or `recovery` scenario and
requires explicit `authorizedOperation=observeDelivery:<scenario>` for that exact invocation.
Read receipts, inventory and peer observations cannot satisfy this authorization or HOST
quiet-writer/bridge ownership. The reviewed first original must match the fresh full scope;
the case receipt retains its selected ID, exact probe receipt hash and original PNG hash.
Sanitized live-mode summaries pass through the real `WatchSummaryStore.saveEncoded`, unchanged
schema-9 decoding and normal services. A two-band summary has a main/extra pair; a single-band
summary removes obsolete mains/extras. The delayed case requests mains first and extras only
after its bounded observation; recovery returns the pair after removal. Every selected
`ComplicationDataSourceUpdateRequester.requestUpdate` uses discovered **system** IDs and
records each provider call's armed/returned state separately from accepted-summary hashes.
Every provider dispatch requires successful durable arming and a fresh typed mapping after
arming. Persistence failure prevents dispatch; uncertain calls are fenced against retry.
Withholding a request controls neither OS delivery time nor cross-slot atomicity. Selected runtime
accessibility-event availability is recorded separately within the unchanged five-second wait;
event absence alone does not invalidate independently acquired stage evidence. Event arrival
supplies no input-specific delivery or paint ACK; response provenance stays Pending. Effective
native data, NoData observations and original requested/bounded frames are separate private
evidence, never a callback ACK or a renderer
PASS. Requested frames precede the potentially slow selection lookup; native records and
images observe separate instants. No sleep, repeated gesture, timing retry or final-frame
substitute is used.

**2026-10-31 retained-extra repair (Source only; corrected-artifact native acceptance Pending):**
the WFF generator now emits extras before mains, allowing each main's opaque track to cover
overlapping retained paint. Admission and geometry are unchanged; valid extra with main
NoData remains visible. Analytical coverage retains the entire extra response while mains
change, including Codex37 + Cursor70/Other50 → Codex80, then separate extra NoData.
Native compositing/antialiasing and the historically redacted TITLE/selected branch remain
unproved. See the [owning implementation notes](../../docs/product/WATCH_RING_DESIGN.md#implementation-repair-2026-10-31--retained-extra-paint).

The consumed Square `normal`, `fixture-n1_pair_zero_full`, `fixture-n1_pair_near_full_tiny`
and `delayed` records and their exact recovery receipts are never reopened or rewritten.
A proposed **separate** observation requires Root's explicit admission of a genuinely different production WFF
XML, with a reviewed private `files/native_datasource/retained-extra-admission.json` record
and its exact `expectedRetainedExtraAdmissionSha256`. Source preparation grants neither
record provisioning nor device mutation. Missing baseline/candidate provenance blocks the
route. The [manual argument and record contract](../../docs/ANDROID_TOOLCHAIN.md#retained-extra-production-payload-observation)
binds reviewed generator source, generated XML, built APK payload, installed resource and
active renderer. APK/signature, test, probe, instance or configuration changes alone do not
qualify. No new product schema, format, slot, dependency or producer behavior is introduced.

`observeDelivery` selects `deliveryScenario=delayed` or, with the **2026-10-31 near-full
extension**, exactly `fixture-n1_pair_near_full_tiny`. The reviewed admission's scenario
must match. Exact authorization is `observeDelivery:<scenario>-payload-<production-XML-SHA256>`;
the delayed route keeps its original identifier and stages. The near-full route requires a
debug target and `expectedFixtureSha256=4aa6180f44dcb5c920a15f12ef5f5dd4167d87ab1e9ff7ee8b86bd2b8d97f4e8`.
It publishes the unchanged packaged `watch_dashboard_summary_n1_pair_near_full_tiny.json`
through the same summary lease/store and targeted services, with the ordinary single
`fixture` stage. Its consumed baseline receipt must identify exactly that asset/hash, exact
original-byte restoration and a separately recorded later recovery. No other fixture gains
production-payload admission. The directory `<scenario>-payload-<production-XML-SHA256>/`
is reserved once per scenario/payload, durably before any summary
publication or request, with the global `latest.json` armed first. Partial attempts fence
later work; an already reserved payload cannot be replayed, even after recovery or with
new probe/admission bytes. The reservation is outside the receipt-writing failure handler,
so rejection cannot overwrite the first attempt. Original scenario paths continue to
resolve unchanged. Prior-recovery checks accept the new receipt only with its payload
identity, exact reviewed receipt hash and separate later restoration. Normal-recovery
consumers may explicitly select a delayed payload case; fixture payloads never qualify as
normal controls. `observeRestoration` requires
the same admission and latest case, and leaves native/frame review Pending. The existing
newer-publication protection remains in force for reserved attempts. SDK/client normal-recovery
consumers also enforce exact prior recovery whenever a candidate is globally latest, so an
older normal receipt cannot bypass an unresolved candidate attempt.

Synthetic private coverage extends
`NativeDatasourceGuardTest.explicitProbeSelectionRetainsHistoryAndRejectsReusedOrChangedEvidence`
and `failedPublicationRestoresOnlyOwnedDataAndRetainsUnresolvedRecovery`; no methods or default
exclusions change. Execution of these tests remains a later HOST duty. This contract evolution
is neither admission nor acceptance. The exact corrected-artifact delayed and near-full witnesses remain
Pending until separately admitted and observed after whole DONE, owning CLI exit, owned-process
retirement and a fresh separate idle observation. Complete Source/HOST review, native artifact
joins, justified finite cases, exact recovery and restored ordinary Face/Glance verification
remain required. Unused fixtures/SDK/obsolete/recovery cases cannot substitute; all original
item12 and historical compatibility obligations stay open, with public acceptance afterward.

The same `observeDelivery` method also admits exactly **18** `fixture-*` scenarios from
`nativeDeliveryFixtureAssets` in `NativeDatasourceState.kt`, using **19 existing** packaged
assets. In this table each suffix means `watch_dashboard_summary_<suffix>.json` in
`fixtures/snapshots/`, packaged at the instrumentation context's asset root:

| Scenario suffixes (prefix each with `fixture-`) | Existing source oracle |
| --- | --- |
| `n1_pair_zero_full`, `n1_pair_full_zero`, `n1_pair_both_zero`, `n1_pair_tiny_near_full`, `n1_pair_near_full_tiny`, `n1_pair_below_above`, `n1_pair_above_below` | `WatchSummaryStoreTest.n1PairedFixturesKeepIndependentEndpointsAndCutoffs`: MAX200, reversed endpoints, zero tokens, tiny/near-full and both cutoff sides |
| `n2_pairs_zero_tiny`, `n2_pairs_tiny_zero` | `WatchSummaryStoreTest.n2EndpointFixturesKeepBothSplitOrdinalsAndClearObsoleteExtras`: MAX400, exact 0 versus 0.125 and both split ordinals |
| `n3_pairs_near_full`, `n3_pairs_full_near`, `n3_zero_tracks` | `WatchSummaryStoreTest.n3EndpointFixturesKeepExactValuesAndReplaceSameCountSelections`: exact envelopes, titles, colors and positions |
| `credits_only`, `plan_credits`, `n1_week_near_full`, `n2_week_day`, `n2_month_month` | `WatchSummaryStoreTest.creditsAndBudgetFixturesBuildExactComplicationEnvelopes`: credits-only 500, matching Codex strip 320 (aggregate 400), Week/Day order and Month radii |
| `n3_reorder` | One lease publishes `n3_reorder_before` then `n3_reorder_after`; the N3 endpoint oracle retains mains 720/240/80 → 600/360/40, extras 560@2 and 640@1 → 760@0, and obsolete second-extra NoData |

The original finite-catalog fixture route requires a debug build, exact
`authorizedOperation=observeDelivery:<deliveryScenario>` and an independently supplied
`expectedFixtureSha256`. The reorder additionally requires `expectedReorderAfterSha256`;
`readNativeDeliveryFixtures` verifies **both** original byte arrays before any case write or
lease. Arbitrary paths, other assets, malformed/mismatched hashes and missing authorization
are rejected before publication or requests. The original UTF-8 strings pass unchanged through
`NativeSummaryLease` to `WatchSummaryStore.saveEncoded`; mock mode, historical timestamps and
normal decoder behavior stay intact. These inputs establish no healthy public cohort.

Each fixture requests the same freshly joined intended provider groups through normal services.
Reorder records `reorder-before` and `reorder-after` independently within the same lease;
single inputs use stage `fixture`. The original route's private `files/native_datasource/<scenario>/receipt.json`
retains all selected asset names/hashes and initially Pending stages in `fixtureInputs`, separate
publication states/hashes in `publications`, and bounded request/event/effective-data records in
`events`. `observeNativeDeliveryStage` joins each stage's exact fixture/accepted-summary hashes,
current full scope and intended targets to the names and hashes of its actual
`<stage>-requested.{png,json}` and `<stage>-bounded.{png,json}` originals, alongside `before`
and restoration originals. Acquisition is recorded only after complete PNGs and native sidecars,
fresh scope/ownership checks and persistence succeed. Selected-event availability is independent:
a wait expiry alone permits the next fixture publication when actual stage evidence was acquired.
Missing, invalid or unseen stage evidence stays Pending/failure and stops the invocation;
request, capture, mapping, ownership and persistence failures (including timeout-shaped action
failures) still attempt independent targeted recovery. Recovery errors retain the primary failure.
Even an observed event or successfully acquired originals prove no service callback provenance,
effective delivery or paint. No later frame substitutes for an unseen reorder-before stage.

Catalog cases share the global single-use/latest-case and separate later-restoration review
fences with normal and SDK cases. `requireNativeNormalRecovery` still accepts only the four
reviewed normal controls and separately admitted delayed payload cases for SDK/client
admission. The near-full payload case also fences later mutations while globally latest,
but never qualifies as a normal control. A new probe ID never reopens a fixture case.
The existing four datasource guard methods add finite-catalog/path and exact authorization/hash
rejection, unchanged-byte publication, global fencing and newer-write-safe targeted recovery
using private preferences and injected requests. The existing cleanup guard also exercises the
shared stage path with absent/present events, missing/invalid originals, an unseen before-stage
despite later evidence, persistence failure and genuine request failures with independent recovery.
These synthetic originals establish no native paint or settled restoration. No test method or
default exclusion changes: source discovery remains expected at 47 default + 48 manual;
packaged discovery is a separate
HOST verification. Compilation, guards, default tests, delivery, paint, quiet custody and settled
restoration of these new paths remain unrun/Pending until their ordered HOST phase. Invocation
arguments are in [the manual invocation](../../docs/ANDROID_TOOLCHAIN.md#guarded-datasource-observations).

`NativeDatasourceGuardTest.failedPublicationRestoresOnlyOwnedDataAndRetainsUnresolvedRecovery`
also checks both actual `deliverySummary` outputs against the schema-9 property/type contract,
including explicit nullable root, full-ring and budget fields and the distinct four-property
ring half. The pair uses `allowance.cursor.cursor-plan-other`; normal complication selection
and AndroidX construction must emit `split:cursor-other`, retaining its recognized far marker
and the cyan outer arc. Decoder acceptance or static shared-fixture validation alone cannot
establish this inline-fixture coverage. These subcases add no separately discovered tests.

`NativeSummaryLease` durably retains the exact original preference string opaquely before
publication, plus owned/reconciliation values and receipts under app-private
`files/native_datasource/<scenario>/`. Its `.bin` files use one presence-marker byte followed
by the unmodified UTF-8 string. They and native records/frames must remain private. Recovery
runs on failure as well as success, unregisters its preference listener and makes queued
callbacks inert. It compares current data to this instrumentation's issued values before
restoring original bytes or original absence. `armPublication` persists before a fresh
full-scope mapping read off the main thread, then `publish` rechecks ownership on the main
thread before saving the exact armed bytes. A newer value is preserved, including a
producer write during persistence; observed interleaving or unreestablished quiet writers
retain recovery material and remain Pending. SharedPreferences
does not provide a cross-writer compare-and-set transaction: do not run this route with active
writers or claim concurrency isolation from its comparisons. No restoration blindly overwrites
a changed value. Original and recovery files remain until HOST reconciliation and native review.

Cleanup independently requests current normal data only for freshly validated intended
targets with `requestUpdate`, including after observation failure. It attempts each independent
provider group even when another fails, preserving newer publications. Missing/changed
mappings or failed durable arming leave recovery Pending without stale IDs, blanket requests
or retries. The latest-case journal prevents another scenario until the prior separate
restoration receipt and effective recovery receive explicit HOST review and a bound receipt
hash; each scenario directory remains single-use. These directories and `latest.json` remain
global under `native_datasource`, outside `probes/<id>`: changing probe IDs neither reopens
a scenario nor bypasses prior-recovery review. The immediate restoration frame is diagnostic.
HOST separately selects `observeRestoration` once after native settlement; it
records a later original and detects newer live data without restoring over it. Equality of
native dump text is diagnostic, especially with redacted values, and cannot prove semantic
data restoration or visual acceptance. HOST must reconcile newer publications, inspect actual
normal effective data/frames and verify retained bindings, upper choices, consent, settings,
time/font/ambient and bridge state. Unsupported mapping/provenance, unseen transitions and
unsafe restoration remain **Pending**. See
[the manual invocation](../../docs/ANDROID_TOOLCHAIN.md#guarded-datasource-observations).

The excluded `NativeDatasourceGuardTest.explicitProbeSelectionRetainsHistoryAndRejectsReusedOrChangedEvidence`
uses only private synthetic originals to cover retained history/global state, independent fresh
creation, invalid/duplicate selectors, partial/changed captures, exact hashes and provenance
rejection. It neither reviews a native frame nor establishes current delivery/recovery acceptance.

## Guarded SDK direct-data observations

`NativeDatasourceTransitionTest.probeDirectCapability`, `observeDirectData` and
`observeDirectRestoration` require one explicit stock-runner method and
`wardpulseNativeIntegration=sdk-direct-data`. All three remain `ManualNativeIntegration`;
neither ordinary discovery nor a normal-delivery invocation enables this route. See the
[exact arguments and ordering](../../docs/ANDROID_TOOLCHAIN.md#guarded-sdk-direct-data-observations).
[NativeSdkDirectData.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeSdkDirectData.kt)
uses the existing public Wear SDK dependency, ordinary `targetContext` manager acquisition
and API36 `WEAR_BAKLAVA_0`. API35.1 typed reads establish no update capability. No privileged
context, grant, query bypass, client binding or renderer/target replacement is attempted.

First create a NEW current-scope `probeDelivery` and independently review its unobscured
original. Each direct method retains the existing caller/resource/runtime/full-eight admission.
`probeDirectCapability` requires the selected probe's exact receipt and PNG hashes plus
`firstFrameReview=complete-unobscured`. It reserves
`files/native_datasource/probes/<id>/sdk-direct-capability/` once and records API availability,
manager acquisition and a fresh full-scope bracket in `receipt.json`. A failed attempt consumes
that capability directory. Acquisition records no update, delivery or paint result; HOST must
review its exact receipt hash before authorizing mutation. Historical originals stay unchanged.

Only four `directScenario` values are admitted. `nativeSdkDirectData` uses typed public setters
for complete deterministic ranged inputs: generic `RangedValueComplicationData.TYPE_UNDEFINED`,
an explicit noninterpolated single-color ramp, short text `37%` and content description
`Test percentage`, alongside the exact ranges and titles below. Mains use `RingFamily.CODEX`;
the valid RingSplit extra uses `RingFamily.CODEX_SPARK`. Emitted-object checks and
`NativeSdkDirectDataGuardTest.finitePublicBuildersRetainRangesTitlesAndSequentialPartialTargets`
verify field presence and exact values, preserving each negative's unrelated valid channels.
Main-only NoData construction remains independent of ranged inputs and a RingSplit target.
Targets require configured ranged-value types and freshly joined Today/RingSplit **system**
IDs, never guessed slot IDs. Construction supplies no observed delivery or paint acceptance.

| Scenario | Ordered SDK data |
| --- | --- |
| `unsupported-range` | Today ranged MIN=0, MAX=300, VALUE=111, empty TITLE |
| `malformed-title` | Today ranged MIN=0, MAX=400, VALUE=148, TITLE=`invalid` |
| `partial-no-data-main` | Today NoData only |
| `no-data-main-valid-extra` | Today NoData, then RingSplit MIN=0, MAX=400, VALUE=148, TITLE=`0` |

`observeDirectData` separately requires exact `authorizedOperation=observeDirectData:<scenario>`,
quiet writers, the reviewed first original and capability hash, and independently reviewed
current targeted normal-recovery support. `requireNativeNormalRecovery` is shared with the
client route, retaining its exact receipt hash, full-scope/mapping, successful cleanup, later
observation, original-byte reconciliation and current normal-data requirements. Read evidence
does not authorize updates. Public SDK construction rejection proves no renderer effect.
The fourth scenario is sequential per ID, supplies no pair atomicity and makes no claim that
a missing main suppresses a valid extra.

Case evidence lives in single-use `files/native_datasource/sdk-<scenario>/`: `receipt.json`,
opaque `summary.bin` reference bytes, `before`, per-ID `direct-<index>-bounded`, immediate
restoration and later restoration PNG/JSON originals. This route never writes preferences.
`latest.json` remains global and distinguishes SDK cases from normal/delayed/obsolete/recovery.
Changing probe IDs cannot reopen cases or bypass recovery review. A rejected construction
still consumes its case and requires exact HOST receipt review before another scenario.

Every possibly affected target is durably armed before the first SDK call. Each individual
`updateComplication` revalidates full mapping/provenance, quiet custody and current normal
producer data after arming. Construction, arming, dispatch return, bounded callback
processing/forwarding, effective native data and original-frame paint remain distinct.
Callback error/timeout leaves uncertain effect; late callbacks cannot rewrite terminal receipts.
There is no automatic retry. Per-ID bounded frames observe separate instants, not an atomic pair.

Failure-safe cleanup uses existing `requestNativeDelivery(..., recovery=true)` for EVERY armed
target, including an uncalled second target. Fresh mappings/current producer data are required
for each provider group; another independent group is still attempted after a failure.
Newer producer data is preserved. Requests, callback success and immediate cleanup frames do
not clear recovery: separately select `observeDirectRestoration` after actual settlement, then
independently review current normal effective data, the later original, newer publications and
retained native/bridge state. The global fence requires its exact reviewed receipt hash before
another case. Unresolved mapping, delivery, paint or recovery stays Pending.

`NativeSdkDirectDataGuardTest` adds three excluded private guards for API36/manual authorization
and capability provenance, finite public construction, and durable dispatch/uncertainty plus
independent recovery. Source inventory is **47 defaults + 48 manual = 95**; this is not packaged
discovery or execution evidence. Preserve the genuine historical 47-test PASS, actual Push5
and the separate failed-preservation/UI4→5-witness gap. Current native viewport, active artifact,
geometry and broader item12 acceptance remain Pending; no downgrade/reset/replay/code6 or
retroactive witness follows from these tests.

## Independent client metadata observation

`NativeClientMetadataTest.observeClientMetadata` is separately selected on the stock runner
with `wardpulseNativeIntegration=client-metadata`. It carries `ManualNativeIntegration` and
remains excluded from default discovery. See the
[invocation and current identity arguments](../../docs/ANDROID_TOOLCHAIN.md#independent-client-metadata-observation).
This current-operation read requires the actual caller UID/package/signer/current target APK,
canonical emulator/image/display, ordinary Application and current resource/runtime APKs and
existing native instance. It does not require a Push 3→4 journal, requester-ID mapping, quiet
bridge, candidate bundle or SDK update-method resolution. The historical admission and
one-shot update/settled-witness paths remain unchanged. Round Wear4/asset3/Push4 is historical
evidence; the recorded current host is Wear4/asset5. Current reads must preserve actual Push5
and freshly verify installed identities rather than infer them from Source/builds. Legacy-only
Square needs no invented Push history.

`NativeReadAdmission` checks the process UID against the target application's UID and the
actual packages for that UID, then verifies HOST-observed APK/signer/version expectations.
Its current `resourceIdentity` runtime read uses the fixed `INSTALLED_RUNTIME_PATH_COMMAND`
through the existing UiAutomation solely for `pm path com.google.wear.watchface.runtime`.
`readInstalledRuntimePath` reads at most 4097 bytes, accepts at most 4096 and requires EOF,
exactly one absolute APK path and the conditional completion marker. Malformed, additional,
split or incomplete enumeration is rejected. Under the ordinary target UID/context,
`readNativeRuntimePackage` streams the APK hash and uses `getPackageArchiveInfo` with
`GET_SIGNING_CERTIFICATES`. It requires actual archive/application package metadata, the exact
runtime package, a positive observed version, one current signer and no archive/application
splits. It rehashes the bytes and repeats the complete path discovery, rejects changes and
compares the observed APK/signer with CURRENT expectations. The parsed version remains in
runtime identity receipts and outer identity brackets. Arguments, paths, hashes and `sourceDir`
never fill absent metadata. These brackets detect changes without claiming atomicity.
No installed-package lookup, shell byte/metadata read, adopted identity, SDK context, manifest
query or permission change is added. `NativePackage.read`, Candidate and the complete historical
SDK3→4 route remain unchanged. UID byte readability and synthetic archive observations do not
prove target Java archive parsing; actual package/hash/signer/version and HOST acceptance
remain Pending on the preserved target.

`readNativeClientFace` brackets system/native scope around a configuration-dump observation;
configuration absence or an unresolved configuration producer is recorded without blocking
client metadata. The after-bracket repeats caller/resource/runtime identities. Raw configuration
hashes are diagnostic observations, not a semantic selection join or an atomic snapshot.

`withNativeClientAcquisition` reuses the public resource-only factory and existing-instance
lookup, including the exported/enabled service and caller-held declared-permission checks.
The resolved client 1.2.1 AAR and dependency-graph hashes are explicit HOST provenance inputs,
not Maven provenance established by instrumentation. Returned instance ID, actual client slot
keys, enabled states and supported types are persisted before any comparison. Client slots
are retained independently of native, generator and provider/system IDs; no numerical equality,
offset, ordering or default-provider policy supplies a join. Even a stable bracket and matching
opaque instance leave slot association `ambiguous/domain-unresolved` in this scope.

Private receipts use fresh `files/native_read/client-*/receipt.json` directories and the
`read-only-client-metadata` kind. Each operation records invocation, target, returned domain
and outcome: `not-invoked`, `unsupported`, `null/empty`, `denied/inaccessible`, `timeout`,
`ambiguous/domain-unresolved` or `successful-acquisition`. Empty results and partial acquisition
retain their own outcomes. Failures also retain a syntax-validated actual `failureType` of at
most 192 characters (otherwise `Unknown`) and a fixed `failureSubstage`: `runtime_discovery`,
`runtime_bytes`, `runtime_archive`, `runtime_identity`, or the operation/recording stages.
Original outcomes and failing substages survive recording/cleanup failures. No exception
messages, causes, stacks or sensitive payloads are emitted; the historical thrown class remains
Unknown. These receipts are rejected by the guarded override admission,
including when identity and cleanup match. No data, bitmap, screenshot, restoration, message,
activation or permission transport is invoked by this observation.

Both client routes share `files/native_client/acquisition/owner.lock` and `custody.json`.
Custody is armed before acquisition and all returned references and tracked bindings are closed
on exit, with failures recorded separately. A factory deadline bounds only acquisition;
synchronous remote calls must return before the owner retires. Releasing a binding cannot
prove release of an unreturned control/interactive reference. Unreturned references, failed
closes or unresolved custody prevent another acquisition until HOST reconciles the actual owner;
do not delete/reconstruct evidence or replay history to bypass that fence.

The current-read synthetic `NativeClientGuardTest` cases cover current admission separation,
independent client slot domains/read-receipt rejection, operation outcomes, partial/failed cleanup
and changed-face brackets. Three additional runtime cases cover independently supplied archive
observations despite unavailable installed lookup, missing/foreign metadata, invalid versions/
signers, splits, complete path enumeration, changed paths/bytes and resource closure. The
runtime locator also uses fixed shell-output fixtures for its actual String-tokenization and
conditional-marker contract, without installed-package queries or another discovered case. The
existing outcome case also checks bounded failure types and original substages through recording
and cleanup failures without private payloads. Existing parser fixtures remain parser tests,
not evidence of an OS producer. Compilation, guard execution, actual access/cleanup and runtime
acceptance remain
pending later HOST validation after whole Runner DONE, process retirement and fresh public idle.
No target installation is authorized to manufacture capability; a genuine target dependency
must remain visible for later admission. Malformed/delayed/missing-main native coverage,
restoration, full artifact/compatibility and healthy public acceptance remain pending; this read
does not close #12.

## Typed own-provider complication configs

`NativeTypedConfigTest.observeActiveComplicationConfigs` is independently selected with
`wardpulseNativeIntegration=typed-configs` on the stock runner. It uses `NativeReadAdmission`
for the actual provider-app process UID/package/current target APK/signer and canonical
emulator/image/display. It requires no historical Push journal, requester mapping, client
artifact arguments, quiet bridge or active-face join. See the
[typed-config invocation](../../docs/ANDROID_TOOLCHAIN.md#typed-own-provider-config-observation).

The public `Sdk.isApiVersionAtLeast(Sdk.VERSION_CODES.WEAR_VIC_1)` check precedes
`Sdk.getWearManager(context, ComplicationsManager::class.java)` and Wear SDK 35.1
`getActiveComplicationConfigsAsync`. Direct `useLibrary("wear-sdk")` wiring in
[app/build.gradle.kts](app/build.gradle.kts) supplies the existing platform compiler symbols;
the dependency's existing required `wear-sdk` manifest contract and all SDK/dependency versions
remain unchanged. Compiler symbols and a required library do not establish runtime availability
or access. Unsupported availability, null manager/results, empty configs, denial and callback
timeout remain distinct from uninvoked operations and successful metadata acquisition.

Fresh private `files/native_read/typed-*/receipt.json` receipts retain actual provider/system
`id`, `watchFaceSlotId`, provider component, resource `WatchFaceId` package/class and numeric
data type. WFF's null class is retained explicitly; its package is not an opaque instance ID.
Generator, native, flat-row, public client, typed and SDK Push manager-slot domains remain
separate. No offset, modulo, ordering, provider-only or default/stale-policy mapping is inferred.

Optional before/after system/native/resource/instance/configuration and installed APK evidence
uses the existing read brackets; caller identity is repeated after the read. Missing or changed
brackets retain raw configs. Even a stable bracket does not supply the missing WFF instance
identity or a slot mapping: `activeFaceAssociation` stays `ambiguous/domain-unresolved`.
These separate read-only receipts cannot satisfy override admission. No mutation, rendering,
restoration, message, activation or permission transport is connected to this route.

The callback wait is bounded to five seconds after the synchronous platform invocation returns;
it does not bound that invocation or prove platform callback retirement. Completion uses a
direct executor without an owned worker; only the waiting owner persists results. Timeout
closes the local result, so late/duplicate callbacks cannot rewrite the terminal receipt.
`NativeTypedConfigGuardTest` has five deterministic synthetic cases for admission, unavailable/
null/empty/denied outcomes, distinct ID domains and read-receipt rejection, timeout/late completion
and changed/missing brackets. They are callback/record tests, not an OS configuration producer.
All six typed cases carry `ManualNativeIntegration`; default discovery stays 47. Compilation,
actual guard execution, runtime access and later HOST/device acceptance remain pending under
the same whole-DONE/retirement/fresh-idle boundary above. This does not close #12 or waive its
malformed/delayed/missing-main native, restoration, artifact/compatibility or public acceptance gaps.

## Owned Push inventory and connected peers

`NativeInventoryObservationTest.observeOwnedPushInventory` and `observeConnectedPeers` are
individually selected on the stock runner with `wardpulseNativeIntegration=owned-push` and
`connected-peers`, respectively. Both reuse `NativeReadAdmission` for current caller UID/package/
APK/signer and supported emulator/image/display. Neither requires a version-3 baseline probe,
historical journal, candidate bundle, requester mapping, quiet bridge or active-face join. See
the [inventory invocation](../../docs/ANDROID_TOOLCHAIN.md#owned-push-inventory-and-connected-peers).

`readNativeOwnedPush` calls the existing `AndroidWatchFacePushClient.isSupported` and `list`.
Private `files/native_read/owned-push-*/receipt.json` receipts retain all returned caller-owned
package/version/opaque manager-slot rows and remaining capacity before validation. Valid rows
require positive versions, nonblank packages/slots, unique packages/slots and nonnegative capacity.
Only a returned owned `app.wardpulse.watchfacepush.main` package authorizes its read-only
`isActive` query; absent ownership leaves that operation uninvoked, without inventing history.
Active status is recorded separately from inventory. A second list must retain the same rows
and capacity, independent of order; changed/invalid returns remain private unresolved evidence.
Manager slots are not client slots, provider/system IDs, WFF resource IDs or native instances.

`readNativeConnectedPeers` reads `Wearable.getNodeClient(context).connectedNodes` directly.
Private `files/native_read/connected-peers-*/receipt.json` receipts retain actual remote node IDs,
display names and nearby flags, separately from GMS connection-category flags. No refresh
requester or message client is called. Null/empty peers do not establish quiet producers,
absence of queued/local writers, pairing health or successful phone delivery.

Both observations repeat caller/target identity afterward, keep per-operation invocation,
target/domain and outcome, and cannot authorize mutation. Push suspend reads have five-second
cooperative coroutine deadlines; the peer task wait is bounded to five seconds after synchronous
task acquisition returns. Neither bounds a synchronous platform call nor proves remote retirement.
Late task completion has no receipt writer. No client/control reference or bundle is acquired.
Credentials, summaries, selections, jobs, pairing/bridge, permissions and historical evidence
are preserved. Round Wear4/asset3/Push4 is historical evidence; the recorded current host is
Wear4/asset5. Current inventory reads must retain actual Push5 and freshly verify installed
identities independently of Source/builds. Legacy-only Square may truthfully return no owned
Push package.

The seven `NativeInventoryGuardTest` cases cover independent admission/read-receipt rejection,
raw domains and active status, absent ownership, unsupported/denied/timeout outcomes, invalid/
changed inventories and null/empty/failed peers, plus exact current datasource Push scope and
Legacy-only independence. The fake Push client rejects every bundle,
mutation and permission effect. All nine cases carry `ManualNativeIntegration`; the 47 defaults
retain original40 plus the seven fixture/API cases. Compilation, actual guard execution and
reviewed watch observations are later HOST duties after whole DONE, all owned-process retirement,
any owning-CLI exit and fresh
separate public idle. Fresh runtime identity/custody, reviewed test-only provisioning and cleanup/
recovery precede watch actions; a target dependency must be exposed without target replacement
to manufacture capability. No phone action is authorized. Malformed/delayed/missing-main native,
restoration, comprehensive artifact/compatibility and healthy public acceptance remain pending;
these observations establish neither universal PASS, physical-device acceptance nor #12 closure.

## Guarded complication client probe

`NativeComplicationOverrideTest` has three individually selected stock-runner cases:
`probeClient`, `observeOverride` and `observeRestoration`. `NativeClientGuardTest` retains its two
synthetic binding/object cases and adds the five read/custody cases above, without real service
binds or data updates, plus three synthetic runtime-reader cases. All carry
`ManualNativeIntegration` and remain excluded from the current default 47. The three native
methods use the current-target admission described above and
remain HOST-only after whole execution DONE, owned-process retirement and separate fresh public
idle, with separately reviewed compilation/provisioning. The guarded route never launches
an Activity or supplies the isolation Application. See
[client invocation and dependency proof](../../docs/ANDROID_TOOLCHAIN.md#guarded-complication-client-probe).

The [test dependency](app/build.gradle.kts) pins `androidx.wear.watchface:watchface-client:1.2.1`
only in `androidTestImplementation`. The saved source JAR is API research, not Gradle
resolution, checksum, installed access or capability evidence. HOST must verify the exact
resolved AAR and graph in ordinary warm, fresh empty task-owned cache and same-cache reuse
checks. The explicit artifact review/hash arguments record HOST's provenance; instrumentation
cannot establish Maven provenance from a loaded class. No cache seeding or shared-cache
modification is authorized.

`NativeComplicationOverrideTest` references `androidx.wear.watchface.style.WatchFaceLayer`,
the namespace in the pinned 1.2.1 API. The earlier AndroidTest Kotlin compilation failure is
separate from native access or override capability. Corrected compilation/full build checks
and runtime capability remain Pending until their ordered HOST checks run.

`withExistingNativeClient` in
[NativeClientProbe.kt](app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativeClientProbe.kt)
uses only the public resource-only factory and existing-instance lookup. Before a real bind,
it resolves the factory's actual intent and checks a unique enabled/exported runtime service
and any declared permission under the target UID. Null, denied, unresolved, incompatible or
unmapped capability stays **Pending**, without granting permission, creating an instance,
activating a face or changing style/UI/ambient state. Client instance and enabled-slot records
must match the native renderer and independent selected-provider/system-ID mappings. Client
default datasource policies do not prove effective selections or data.

`NativeClientBinding` tracks both bind overloads, including the executor overload used by
1.2.1, before Android is called. Returned interactive/control clients close in nested cleanup;
tracked connections release even when the suspend factory times out before returning a client.
The timeout bounds factory acquisition only; synchronous remote operations must return before
the owner can retire. An unreturned interactive acquisition is recorded as remote ownership
**Pending**: releasing a control binding does not prove release of an unreturned remote
reference. Failed close/unresolved ownership forbids another owner until HOST reconciliation.

The first probe captures one private original for HOST inspection before further cases.
Overrides require its exact receipt/frame hashes, retained installed/active identities, explicit
review, quiet-writer/unpaired-bridge preconditions and an independently reviewed normal
datasource restoration receipt with matching mappings and full scope. They also require explicit
`authorizedOperation=observeOverride:<mode>:<scenario>`; a read receipt or a successful inventory/
peer observation cannot authorize either active-data transport or supplied-data rendering.
No unproved recovery path permits an
override. Each mode/scenario has a fresh, single-use private directory under `files/native_client/`.
The private `latest.json` records acquisition ownership before binding. Another case requires
retired resources and, after any armed transport, a separate later restoration observation
with explicit HOST review bound to that exact receipt. An old normal-delivery review cannot
authorize another override while this route's recovery remains unresolved.

`nativeOverrideData` uses the actually mapped Today/RingSplit slots. `unsupported-range` is
a valid generic `TYPE_UNDEFINED` 0/300 envelope, VALUE111 (37%), unsupported by WardPulse's
WFF contract. `malformed-title` uses an admitted 0/400 envelope with invalid TITLE;
`nonfinite-value` and `out-of-range` attempt SDK objects which may be rejected before transport.
SDK normalization also stops the case before transport instead of silently changing its input.
`partial-no-data-main` updates just the main; `no-data-main-valid-extra` supplies NoData main
with a valid extra. These are bounded observations, not arbitrary wire injection or promised
override PASS. Object rejection, transport rejection/unavailability, application state and
demonstrated WFF suppression are separate outcomes. Missing transient/provenance evidence
stays Pending.

`active` calls `updateComplicationData` once and captures requested/bounded originals around
one finite runtime-event boundary, without a delivery ACK, timing retry or atomicity claim.
`supplied-bitmap` calls `renderWatchFaceToBitmap` once with a partial map and current style;
its output is labeled separately from native screenshots. It proves neither ordinary active
publication, transitions nor true ambient rendering. Every returned bitmap is recycled,
including write failures. Effective native records and frames observe separate instants.

Before either transport, an opaque private summary reference is persisted; this route never
writes summary storage. Failure-safe cleanup requests current normal production data with
targeted `requestUpdate` for each affected slot before closing clients, even after a transport
failure. Each provider group requires durable arming and freshly validated typed/controller
mappings; independent groups are attempted even if another fails. Failed persistence prevents
dispatch. Unresolved mapping/recovery stays Pending without stale IDs, blanket requests or retries.
It neither replays stale renderer data nor overwrites legitimate newer producers. Recovery files, raw
effective-data records and original frames stay private. A later separately selected
`observeRestoration` records current normal data after client retirement and compares the
current summary to cleanup's observed value. HOST must reconcile it, inspect effective
restored rendering and retained
bindings/upper choices/consent/settings/time/font/ambient/bridge, and retire the instrumentation's
single UiAutomation owner. Unsafe or unverified restoration remains **Pending**.

No native result is claimed by this implementation. All item12 HOST obligations, public
capture/browser review and Root's whole zero-findings pass remain Pending. A 3→4 result or
client bitmap cannot close UNKNOWN historical causality, old-Push1 compatibility gaps,
missing explicit 1→2/2→3 manager evidence or the utility-button gap. Current Source is phone 3/
Wear 4/legacy 2/Push default 5/common 0.1.0; candidate 4 remains solely the historical test input.

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
