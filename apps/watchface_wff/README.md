# WardPulse Watch Face

Declarative Watch Face Format v2 package for a glanceable WardPulse summary.

The face follows the locked concentric baseline in `docs/product/WATCH_RING_DESIGN.md`:
remaining arcs (up to three ring slots; melt clockwise from 12), large time hero, quiet
watermark, and sunk family strips (`%` / `% · credits` on the matching provider). Ring and
strip data come from Wear OS `RANGED_VALUE` complication providers. Missing rings stay empty
instead of inventing filler. Tapping the face or a WardPulse complication opens the Wear OS
app; ambient keeps muted arcs, large time, a quieter mark, and the strips dimmed rather than
switched off, so the credits and budget money they alone carry survive it.

## Packaging paths

This directory owns the canonical WFF 2 resources in `src/main/res/` and the independent
legacy package `app.wardpulse.watchface` (minimum API 34 / Wear OS 5). Its identity, settings
and separate installation path remain intact.

The [bundled Push module](../wear_android/watchface_push/README.md#resource-ownership) consumes
these same resources directly to build `app.wardpulse.watchfacepush.main`. It is a separate,
resource-only, signed APK dependency of the Wear app, with `hasCode=false` and minimum API 34.
There is one scene and one generator; do not copy or hand-edit generated XML or drawables.
Both packages retain complication and launch targets in the host `app.wardpulse`.

The corrected adaptive face uses legacy code 2 and Push default code 3 with Wear 4
and phone 0.1.0+3; every versionName stays 0.1.0. Package/signing identities are preserved.
This is packaging for in-place updates, not a product release cut. Actual retained-binding,
legacy/Push update, true-ambient and transition acceptance remains **Pending** under the
[adaptive revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-28--adaptive-bands-from-resolved-count).
The new face admits only its own response's exact 0/100, 0/200, 0/400, 0/800 envelopes;
MAX100 always means fixed legacy geometry, and malformed contracts draw no lower component.
`ringSlot` in `tools/render-watchface.mjs` keeps each main selector and strip beneath one
named full-canvas Group. Before emission in normal and `--check` modes,
`tools/check-watchface-structure.py` parses the actual XML to enforce one direct element
tree per Compare/Default and preserve main selector/strip containment. The baseline's three
main branches failed this check; corrected generation passes. Native causal effect remains
unproved; see the [adaptive incident and update qualification](../../docs/product/RELEASE_CHECKLIST.md#adaptive-integration-qualification-2026-10-28).

The Wear app minimum is API 33; the phone minimum is unchanged. The Wear app checks Push
support before using its manager. Supported Wear OS 6+ devices can install the bundled
face; WFF 2 devices without Push use separate installation and manual selection. API 33
can run the dashboard, but this face requires Wear OS 5 or later. No public listing URL
or release availability is established here.

## Commands

From the repository root:

```sh
just render-watchface
just validate-watchface
just check-watchface
just build-watchface
ANDROID_SERIAL="$WEAR_SERIAL" just run-watchface
```

`render-watchface` writes `res/raw/watchface.xml` and the ring-type drawables in
`res/drawable-nodpi/` from `tools/render-watchface.mjs` — edit the generator, never its output;
`check-watchface` fails on drift. `validate-watchface` uses the checksum-pinned official WFF
XML validator; it does not validate a Push APK or generate a Push token. `build-watchface`
produces debug APK and AAB artifacts under
`apps/watchface_wff/build/outputs/`. The run command installs the APK and selects
`app.wardpulse.watchface` on the target Wear device.

Ordinary Wear builds also build, separately sign and validate the bundled face, then embed
its matching APK/token through Gradle's variant graph. From `apps/wear_android/`, after
Owner signing setup:

```sh
./gradlew :app:assembleDebug
```

The positive `wardpulsePushVersionCode` input defaults to 3. Keep the same Push certificate
across versions and outside build outputs so `clean` cannot replace it. Debug and release
Push signing use separate ignored configuration and must differ from the host certificate.
See [signing inputs](../wear_android/watchface_push/README.md#signing-inputs) and
[Push validation ownership](../../docs/ANDROID_TOOLCHAIN.md#watch-face-push-builds).
Never substitute an APK or token manually. The utility's explicit **Update watch face**
action updates without activation. Require an observed manager update from installed Push 2
to candidate 3; a bundled installation cannot prove that operation. The earlier unexpected
Push advance has an unknown trigger and leaves the original compatibility gaps open in the
qualification above. See [watch setup](../../docs/product/user-guide/WATCH.md).

Local development acceptance recorded **2026-10-16** includes final legacy WFF2/XML
validation, generator drift, lint/debug APK/AAB builds, and actual API34/canonical API36
legacy live/editor-return-live. Separate Push APK validation/token binding and API36
N1-to-N2 customization/selection retention also passed; XML validity alone does not prove
those results. The [acceptance record](../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance)
retains the API34 replacement-time headless-renderer exception and N2 transient fallback,
and keeps production signing, Play delivery, API35 and hardware acceptance separate.
The dated utility baseline and approved manual-selection capture are integrated; existing
face geometry and screenshot bytes were unchanged by that setup-route work. Adaptive
geometry and its native acceptance are tracked separately above.

## Private N1 pair diagnostics

`wardpulseN1PairDiagnostics` defaults to `false` in both Gradle owners. Root may build
the Wear producer and legacy face with `-PwardpulseN1PairDiagnostics=true` on their
respective debug tasks. Any release task in an opted-in graph fails before execution;
release producer evidence is always disabled. Push packaging continues to consume canonical
resources and receives no diagnostic overlay.

`GenerateN1PairDiagnostics` in `build.gradle.kts` invokes `tools/render-watchface.mjs` with
`--n1-pair-diagnostics-output` to produce only
`build/generated/n1PairDiagnostics/debug/res/raw/watchface.xml`. It never rewrites canonical
XML or textures. Only the opted-in debug variant registers that generated resource source;
an ordinary build must ignore it even after an enabled build without cleaning.
The generator's normal `--check` path also inspects the in-memory diagnostic tree through
`check_diagnostics` in `tools/check-watchface-structure.py`, including branch containment and
recovery of the original drawing tree after removing diagnostic additions.

`N1PairDiagnostics` in the Wear `WatchSummaryComplications.kt` observes the actual returned
object after the single summary load and existing split selection. Its `WardPulseN1Pair`
log tag admits only schema9/mock, ordinal0: `N1_PAIR` is one Codex plan/Spark pair, both
used63; `N2_PLAN_PAIR` is exactly two ordered bands, an ordinary Codex plan followed by a
Cursor own/Other pair, all three used63. All admitted pools are OK and plan money fields
are null. Both cases share one ceiling of four records per process. Numeric fields are
bounded to 0..800; unexpected routing, types, titles and ramps use closed categories,
including `spark` and `cursor_cyan` for those actual single-color ramps. Unrelated shapes
are rejected before returned-field inspection. A logging failure cannot change the return.
See [logging rules](../../docs/product/SECURITY_MODEL.md#logging-rules).

Only slot106 receives consumer instrumentation. `V`, `m`, `M` show independently read bounded
VALUE/MIN/MAX (`?` means outside that readable range); `T0`/`T1`/`T2`/`Tempty`/`Tother` classify
TITLE without exposing its unexpected literal. `AN1`, `Aother`, `Areject` witness actual
admission branches; within N1, `Pfull`, `Ptiny`, `Pround`, `Pnone` witness actual paint/no-color
branches. Paint outside N1 remains unobserved. These readouts stay inside the existing clip
and below the original incident annulus; unreadable or unavailable readouts remain unknown.

Keep construction, Android wire/Parcel serialization, real service-return, consumer-field,
branch and original-frame evidence separate. The constructed expected 74/200/TITLE `0`/Spark
tuple in `AdaptiveRangedComplicationTest.genericEnvelopesRoundTripWithUnscaledHumanSemantics`
is neither a service observation nor renderer delivery. The separate N2 expected
VALUE148/MIN0/MAX400/TITLE `0`/undefined/Cursor-cyan tuple remains unobserved arithmetic.
Constructed regressions in `WatchComplicationTextTest` establish observer contracts, not
actual callback results, delivery or paint; unavailable stages remain Unknown. A branch
witness cannot prove stroke rasterization or reconstruct the original RED. If instrumentation
changes that RED, record the qualification without claiming a repair or cause.

Root alone performs applicable HOST builds, API tests, release and no-clean isolation checks
after Runner DONE, process retirement, any owning CLI exit and a fresh separate idle
observation. N1 consumer-overlay work also requires official diagnostic XML validation and
the unchanged hash-bound Square N1 case. The exact hash-bound N2 producer observation keeps
the normal face, instance and bindings unchanged, recording actual callback returns plus
first eligible and separately settled normal-face originals. Establish sanitized input and quiet
writers before exposing the consumer; keep frames private. Preserve installed identities,
signers, instance, bindings and data. Restore normal artifacts **before** private original data,
verify effective recovery and retire diagnostic controls/artifacts; installation alone proves
no active reload. Build/runtime/readability and unresolved RED acceptance remain pending HOST.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
