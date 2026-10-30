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

The guarded integration allocation uses legacy code 2 and Push default code 5 with Wear 4
and phone 0.1.0+3; every versionName stays 0.1.0. Package/signing identities are preserved.
This is packaging for in-place updates, not a product release cut. Actual retained-binding,
legacy/Push update, true-ambient and transition acceptance remains **Pending** under the
[adaptive revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-28--adaptive-bands-from-resolved-count).
The new face admits only its own response's exact 0/100, 0/200, 0/400, 0/800 envelopes;
MAX100 always means fixed legacy geometry, and malformed contracts draw no lower component.
The [N1-width revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-30--n1-width-44)
selects explicit full 44 / half 22 for N1: centre radius 180, pair 191/169, continuous span 202..158.
N2 stays 32/16, N3 and legacy stay 20/10. N1 D/7D/M textures are baked at the new actual radius
with measured 11/7/9 repeats per sweep, fixed nominal 15.756 caps and alpha 115/63. The owning
revision records bounded raster fitting at 450/360/384; independent active/ambient visual
review and native clipping, aperture, readability and retained-transition acceptance remain
Pending. Old 68/34 receipts do not accept these new bytes; no version or delivery changes
were made by that width revision. The current allocation changes only Push's default 3→5;
historical candidate 4 flags/instrumentation and the real 3→4 journal remain intact.
The [current qualification](../../docs/product/RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30)
records all six compatibility cells and Root-reviewed forward-only reconciliation for
unavailable history; retained 4/final 5 cannot recreate those cells. It also retains the sole
Native FINALIZE inventory and all nine post-whole-DONE HOST duties. Target provisioning,
device tests, live phone update/sync and UI Update remain held for the separate capability/
guard scope against preserved Round Wear 4/asset 3/Push 4. Item12 remains open and both extras
queued; no new check, device, public or release acceptance is claimed.

`ringSlot` in `tools/render-watchface.mjs` keeps each main selector and strip beneath one
named full-canvas Group. Before emission in normal and `--check` modes,
`tools/check-watchface-structure.py` parses the actual XML to enforce one direct element
tree per Compare/Default and preserve main selector/strip containment. The baseline's three
main branches failed this check; corrected generation passes. Native causal effect remains
unproved; see the [adaptive incident and update qualification](../../docs/product/RELEASE_CHECKLIST.md#adaptive-integration-qualification-2026-10-28).

`outerHalfSlot` in `tools/render-watchface.mjs` emits fixed sibling Groups directly inside
each extra's RANGED_VALUE complication. Every feasible layout/position in slots 106/109
retains its named full, tiny, round and zero Groups in that order. Each starts at alpha 0;
an XML-escaped ternary Transform sets alpha to 255 or 0 from that response's MIN/MAX/VALUE/TITLE.
The range guard and exact TITLE index admit exactly one mutually exclusive state: exact
full, positive partial at/below the existing tiny cutoff, positive partial above it, or zero.
Each positive Group owns track then colored drawing; admitted zero owns only its track,
and rejected input paints nothing. Private `bandTrack` and
`bandPaint` helpers reuse the same drawings while preserving ordinary/inner `bandArcs`
emission, geometry, clipping, live colors, cutoffs and ambient/MUTE behavior.

`check_band_paints` and `check_extra_decisions` in `tools/check-watchface-structure.py`
retain main/inner first-true Condition checks and evaluate every emitted extra alpha
Transform. Extras require exactly one active Group for admitted input and none for rejected
input, with independent inspection of the corresponding drawing content.
Independent literal design dimensions and evaluated arc endpoints/visible sweeps cover
ordinary and inner bands as well as extras, including N1 diameters 360/338/382 and
strokes 44/22/22. Admission and geometry expectations cover both ordinals, every feasible and
impossible position, 74/200, zero, representable tiny values, neighboring cutoff Floats,
near/full boundaries, malformed/non-finite fields and exact TITLE rejection. Generator
assertions retain published Legacy/N3 rounded cutoffs and analytical full-path/clip checks.
N2-to-N3 checks require old 16-unit half Groups to hide and new 10-unit half Groups to appear.
These checks establish declaration semantics, not retained-renderer behavior or native repair.

The previous `5c871ac` candidate flattened only `bandArcs`; the normal prefix remained RED,
with its actual VALUE/TITLE/paint branch unknown. A separate diagnostic case on that Source
showed `V74/m0/M200/T0/A1/PN` without the expected Spark arc. The subsequent `c36bc1c`
combined-decision candidate passed the exact N2-plan-pair → original/MUTE → N1ordinary →
N1pair prefix on one retained normal engine. That is scoped N1 paint success; normal
VALUE/TITLE/selected branch remain unknown. The known bottom system overlay limits track visibility.

On that same retained normal engine, two N2-two-pairs → N3-two-pairs cases retained wrong
pair geometry. In the first, later correct geometry followed ambient/clock controls and
does not establish natural settlement. The second repeated wrong geometry in its first frame
and nine follow-ups over 77.65 seconds from first to last, including a natural clock advance;
this is bounded repeated RED, not a continuous or infinite-lifetime claim. Normal consumer
VALUE/TITLE/selected branch remain unknown. In the second case, the first frame's repeated
effectiveRanges15 tuples are not one authoritative slot15 record; the separate slot14
manager range was 0..800. At the 360×360 viewport, N3's intended 10 design units scale to
about 8 native units; radial
samples are neither unique raster pixels nor exact subpixel stroke measurements.

A separate fresh diagnostic engine with shorter history did not reproduce the count
defect. Its first N2 frame was a blocking notification, not acceptance; N2 was qualified
after snoozing that notification without advancing data. Its N3 first/later frames already
had correct geometry. Only `T2` and `AO/A0` were image-readable; full VALUE/MIN/MAX remain
unknown. AO denotes any non-N1 admitted layout, not exact count/position/paint identity.
This case cannot erase either normal RED or supply the missing normal fields or a cause.

The fixed-Group candidate tests whether source-driven appearance updates hide obsolete
geometry and reveal the new halves without replacing conditional drawing trees. Retained
subtree activation remains a mechanism hypothesis. Condition's documented first-true
behavior remains valid; nested Conditions and locally repeated expression names are permitted.

Normal-face acceptance remains **Pending**. After Runner ownership ends, Root must bind
the actual candidate producer/face artifacts with producer diagnostics disabled, install
the normal face before guest boot, and run the exact N2-plan-pair → original/MUTE →
N1ordinary → N1pair prefix. Then replay original/MUTE → INTERACTIVE N2-two-pairs → N3-two-pairs
on that same retained engine with unchanged hash-bound inputs. Inspect both halves' family,
radius and width in matched first and separately settled whole originals at actual viewport
scale, observing a bounded natural minute before controls. Stop RED for evidence and safe
recovery; do not substitute a fresh scene, retry or reset. Diagnostic cases remain separately
qualified. Full HOST validation, isolation, compatibility and recovery obligations remain
open, along with item #12, adaptive integration and forward-only delivery receipts.
That renderer candidate authorized no version bump; the later guarded allocation above is separate.

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

The positive `wardpulsePushVersionCode` input defaults to 5. Keep the same Push certificate
across versions and outside build outputs so `clean` cannot replace it. Debug and release
Push signing use separate ignored configuration and must differ from the host certificate.
See [signing inputs](../wear_android/watchface_push/README.md#signing-inputs) and
[Push validation ownership](../../docs/ANDROID_TOOLCHAIN.md#watch-face-push-builds).
Never substitute an APK or token manually. The utility's explicit **Update watch face**
action updates without activation. Before a later explicit 4→5 update, freshly prove installed
Push 4/hash/signer, its owned manager slot, eight retained choices and quiet-writer custody.
Keep Legacy active; verify returned same-slot identity and separate settled retention.
Unexpected advancement stops this witness: no code 6, replay, downgrade, reset or invented
button success. A bundled installation proves no explicit update. Later retained-Push
selection/rendering is separate HOST work. Preserve the earlier unknown-trigger advancement
and unobserved manager-update gaps. See [watch setup](../../docs/product/user-guide/WATCH.md).

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
recovery of the candidate's complete normal tree after removing diagnostic additions.

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

Only slot106 receives consumer instrumentation. Its six cells use the following closed
readouts, with two-character category tokens:

| Cell | Readout |
| --- | --- |
| Top left | `V` followed by bounded VALUE, or `V?` |
| Top middle | `m` followed by bounded MIN, or `m?` |
| Top right | `M` followed by bounded MAX, or `M?` |
| Bottom left | `T0` / `T1` / `T2` for those exact TITLE indices; `TE` for empty; `T?` for any other literal |
| Bottom middle | `A1` for actual N1 admission; `AO` for another admitted layout; `AX` for rejected admission |
| Bottom right | Within N1, `PF` for full, `PT` for tiny, `PR` for round partial, `PN` for no remaining color; rejected admission also shows `PN` |

Static category and fallback tokens use compact CDATA inside `Font`, without renderable
formatting whitespace. The structure checker compares the untrimmed literal content and
rejects nested content or extra fonts in those cells. Numeric `Template` cells are unchanged.

VALUE/MIN/MAX remain independent of admission and bounded to 0..800; their `?` fallback
does not disclose an out-of-range value. TITLE never exposes an unexpected literal. Paint
in another admitted layout remains unobserved, leaving that cell unavailable. Admission
witnesses stay inside each actual alpha-gated drawing Group; N1's PF/PT/PR share the Group
that owns their colored drawing, and admitted N1 zero shows PN. Rejected admission retains
AX/PN in its own initially hidden Group, with an alpha Transform complementary to the
complete admission set. The checker exercises that complement across the same emitted-input
cases. Consumer fields remain outside those gates.
Diagnostic Group names remain stable and unique across decisions; stripping additions
recovers this candidate's complete normal tree. The 10-unit
bold text uses two rows of 34×12 boxes within the existing r139..171.25 logical footprint
guard, inside the clip and below the original incident annulus. Neither source font size
nor an enlarged preview establishes readability. Read all six cells in the original 360px
frame and its attributable crop during the exact prefix's final N1pair stage; unreadable or
unavailable cells remain Unknown. Shorter tokens do not diagnose the earlier label-rendering
limit or the original RED. Prior N1 readability evidence remains scoped to its observed
artifact; this candidate preserves that layout. N2/N3 readability remains limited as above.

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
observation. Consumer-readout acceptance requires official validation of both actual XML
variants and artifact-identity and isolation checks before deployment. Keep the normal
producer at corresponding candidate Source/build parity with diagnostics disabled; corrected
embedded Push resources may change its APK identity. Install the diagnostic consumer before
guest boot. Run only the accepted hash-bound N2 → original → N1ordinary → N1pair prefix, assessing
all six cells during its final N1pair stage. Preserve first eligible and separately settled
original 360px frames and attributable crops; no pilot, extra matrix, post-RED installation or
retry-until-green. Preserve the original RED and qualify the instrumented case separately,
whether RED persists or fails to reproduce. Establish sanitized input and quiet writers before
exposing the consumer; keep frames private. Preserve installed identities, signers, engine,
instance, bindings and data. Restore normal artifacts **before** private original data,
verify effective recovery and retire diagnostic controls/artifacts; installation alone proves
no active reload. Build/runtime/readability and unresolved RED acceptance remain pending HOST.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
