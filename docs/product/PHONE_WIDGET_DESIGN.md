# Phone Widget Design

**Composition approved 2026-11-03; native acceptance pending.** The exact original board
SHA-256 is `19256430625ded119dfb05440c932c6ba8c23e20022a7ab2af3804485ee0a056`, with metadata
`fe4d6ff0a9648b1f407473e5d4676e47a2285bf1bc06ffda37c44b209b4a65a9`. Its historical
UNAPPROVED filename predates affirmative Owner approval. Preserve that board, metadata,
historical preview route and dated evidence. USD values, UTC dates and checkerboard are
illustrative; they prove neither live provider values nor native exterior alpha.
The earlier Nov1 approval (`72fb8957809cf9b6d367d10c71e0afd2c1d1e4d57aae36b95620740bef6fc65a`)
retains its historical scope. This revision adopts the Nov3 composition in the existing
private widget path; it adds no renderer, provider, transport or shared Watch contract.

## Goal and size/composition rules

Show up to six independent metrics inside a content-sized card centered in the unchanged
launcher allocation. The full-allocation root is transparent and remains the tap target.
An inner card holds the existing day/night background, four decorative bitmap layers and
quiet mono mark. Exterior padding and layer positions come from the same native layout
result; transparency neither reclaims launcher cells nor changes host-owned size options.

The card width is measured content plus side padding; height includes a shared header,
complete row block and bottom padding. The nominal header is 19dp for both fresh and stale
states. Native font metrics may increase clearance. STALE and mark share that header rather
than adding a second line above the rows. Six stale rows remain when they actually fit.
The mark stays anchored to the card with nominal 36×15 ink, top 2 and end margin 16.

| Element | Approved nominal style |
| --- | --- |
| Remaining percentage or self-contained Money primary | Noto Sans 30 Bold 700 |
| Money fallback only after released-width 30 cannot fit | 26 Bold 700 |
| Purchased remaining balance | 26 Bold 700 |
| Family / full pool | 18 Bold 700 / 16 Regular 400 |
| Budget spent / cap | 26 Bold 700 / 11 Regular 400 |
| Extra used/cap Quantity line / optional reset | 18 Bold 700 / 11 Regular 400 |
| STALE / complete empty or no-fit copy | 11 Bold / 12 Regular |
| Row / row gap / side and bottom padding | 44 / 8 / 16 |

**Budget detail typography — 2026-11-04 revision.** Native budget spent details and current
default review/picker exports share the purchased-balance 26 Bold 700 style. Budget
classification takes precedence over incidental Quantity fields. Cap stays 11 Regular 400;
Extra used/cap stays 18 Bold 700 with its optional reset at 11 Regular 400. Default art shows
`$12.34` / `Cap $10K` for the unchanged USD illustration, retaining full ISO amounts in
preview accessibility. The historical Nov1/Nov3 boards and both optional preview routes
remain unchanged, including the responsive route's budget-18 typography. Their dated
approval does not establish native acceptance of this correction.

Nominal full-grid allowances are accent 12, primary 84, label 108 and details 112 with two
6-unit gaps. They are not native refusal thresholds. Measure complete actual glyph ink,
advance and native FontMetrics. Resets sit below their own right balances, with the nominal
lower line at 29 and a 3-unit gap; the measured complete footprint determines row height.
Keep two-line family/pool identities, including Cursor / Models. Visual budget families
omit generated connection-kind text; catalogue IDs and accessible full identities retain it.

For each candidate complete-row count, exhaust 30 Bold layouts before the approved 26
Money fallback. A reduced budget primary is self-contained Money, including its currency
and sign. Release omitted detail and label widths; never retain an invisible column or
refuse at 84. Omit a genuinely crowded allowance reset before its balance, then whole
right details and label columns. Drop trailing rows only for actual height or bitmap-budget
pressure; never hide a width-unfit Money row that way. No 18 primary, ellipsis, clipping,
inferred currency, width-dependent rounding or system-font substitution is allowed.

## Metric rules and optional reset

Widget-local eligibility differs from Watch eligibility. A reported expense, including zero,
qualifies without a local cap. Defaults prefer plan windows, purchased meters, then known
expenses, up to six; unknown spend never fills defaults. Preserve existing IDs, migrations,
explicit empty selection and the usedPercent-descending/null-as-zero/stable-ID comparator.
Supported Anthropic/Cursor reporting periods with saved unknown spend resolve as unavailable
budget rows. Unsupported or missing saved choices remain removable without fabricated rows.
The shared Watch catalogue, positive compatible cap/percentage eligibility and F05 remain
unchanged. Claude/Codex windows stay expanded and widget slots have no watch band/pair limit.

| Reported budget state | Meaning |
| --- | --- |
| Spend, positive same-currency cap and usable percentage | Percent left plus actual spent/cap detail |
| Known spend, absent cap | Self-contained Money and No cap |
| Present zero, invalid or currency-mismatched cap | Known Money and Cap unavailable |
| Usable cap but no usable reported percentage | Known Money, actual cap and Percentage unavailable |
| Missing spend, even with a cap | Dash / Unavailable; no invented percent |

**Money tokens — 2026-11-04 revision.** Visible spent, cap and self-contained primary/fallback
amounts map exact `USD` to `$` and `EUR` to `€`. Every other reported code retains its
separating space, including `CAD` and `AUD`; a negative sign precedes the currency prefix.
Zero is unsigned. Absolute amounts below 1,000 major units keep exactly two decimal places,
such as `$0.50` and `$999.99`. Larger amounts use the largest suffix eligible from the original
absolute amount: `K`/`M`/`B`/`T` mean thousand/million/billion/trillion at
10³/10⁶/10⁹/10¹² major units. Round the coefficient to one decimal, nearest with ties away
from zero, using integer quotient/remainder; omit `.0`. Rounded `1000` below `T` promotes
once to `1` of the next suffix: `$999.9K` immediately below 999,950 major units becomes `$1M`
at that boundary. At `T`, retain the full rounded coefficient, including `1000T` and larger;
there is no further suffix or truncation. Apply the same magnitude rules to negatives.
Tokens depend only on value, never available width. This narrowly supersedes the former
no-compaction rule; all existing validation and exact integer minor-unit inputs remain.

Dashboard snapshot amounts keep their existing ISO code and cents formatting. Native widget
accessible spent, cap and Money-primary descriptions retain the full reported ISO code and
exact cents, including the signed integer boundary and larger valid private-cache integers.
Compact strings never determine cap compatibility, percentages or alerts. Only U+20AC is
added to the existing glyph gate, consuming the existing both-font `$`/`€` qualification;
other unsupported glyphs and controls remain rejected without system-font fallback.

Quantity fields keep reported value/unit strings. Claude Extra usage retains independent
used and applicable-cap amounts in one right-hand line; either known amount survives the
other's absence. Its reported valid percentage remains eligible with no amount cap.
Missing/invalid allowance percentages remain unavailable and omitted; zero and exhausted
percentages remain visible.

On plan rows, preserve existing finite purchased-credit balance eligibility and compact
formatting. These are credits left, distinct from Extra Credits used/cap and budget spend.
Do not repeat purchased balances on purchased-meter rows or budgets. Missing amounts are
never zero, Unlimited, assumed USD or reconstructed from percentages.

The flat private cache adds `kind`, `spent_minor`, `spent_currency`, `cap_minor`,
`cap_currency`, `extra_used_value`, `extra_used_unit`, `extra_cap_value` and `extra_cap_unit`
to each existing row slot. Numeric strings are exact; every write overwrites/clears each
optional field and clears removed slots. Missing kind preserves legacy percent/flat-label
decoding. Incomplete new budgets become unavailable instead of reusing a cached percentage.
No shared schema or snapshot field changes.

Only the selected allowance's actual reset is serialized in UTC. Display device-local
English `Reset DD MMM HH:mm`, with a zero-padded day; timezone redraw reformats that instant.
Budget and sibling resets, as-of values and rollover are never inferred. No ticker or new
freshness mechanism is added; retained-data STALE and publication/coalescing stay unchanged.

### Atomic cache publication — 2026-11-09 technical correction

`HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload` sends a complete map through
`PhoneWidgetPublicationChannel`, using home_widget 0.9.3's `HomeWidgetPreferences` and flat keys.
The store validates count, empty/STALE flags and all sixteen fields of all six slots, clearing
absent fields/removed slots with empty strings. It stages one editor outside a process-shared
monitor and commits once inside it. Retained-row STALE holds that monitor across snapshot,
eligibility and flag-only commit; initial/empty data stays unchanged. Neither path clears
unrelated keys or replays old rows. `WardPulseAppWidget.refresh` → `data.all` → `publication`
is unchanged. Same-isolate coalescing and guards remain before dispatch and redraw. Dispatched
effects may finish, without chronological ordering, cancellation or retraction. Abandoned
staging exposes no partial publication. Storage failure suppresses redraw; a failed disk
commit may expose complete new in-memory data, without rollback.

`PhoneWidgetPublicationTest` uses real isolated preferences and the actual consumer: fixed
old/A/B inputs expose old, complete B while A is staged, then complete A. The supplied
per-field-commit overlay must fail the same coherence assertion; compile/setup/timeout/cleanup
failures are not RED. `PhoneWidgetRoundTripTest` separately requires awaited Dart-origin
replies and consumer observations from MainActivity's implicit engine and a distinct
Activity-free auto-registered engine. Builds/runtime proofs remain HOST Pending. Source review
and the Java layout/decoding/navigation harness prove neither persistence nor channel reachability.

HOST uses a qualified phone AVD with both fixture packages absent. Preserve normal APK identity,
installed package/data, selections and launcher; verify fixture/test IDs, target/runner,
signer/version/hash and bundle/native identities before installation. From the phone directory:

```sh
ORG_GRADLE_PROJECT_wardpulseWidgetPublicationTest=true flutter build apk --debug --target=test_driver/phone_widget_publication.dart
```

From its Android directory:

```sh
./gradlew --no-daemon -PwardpulseWidgetPublicationTest=true -Ptarget=test_driver/phone_widget_publication.dart :app:assembleDebug :app:assembleDebugAndroidTest
adb -s "$PHONE_SERIAL" install -t ../build/app/outputs/apk/debug/app-debug.apk
adb -s "$PHONE_SERIAL" install -t ../build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
timeout --kill-after=5s 90s adb -s "$PHONE_SERIAL" shell am instrument -w -r -e class app.wardpulse.PhoneWidgetPublicationTest,app.wardpulse.PhoneWidgetRoundTripTest app.wardpulse.widgetpublicationtest.test/android.test.InstrumentationTestRunner
```

Do not launch before instrumentation. Pair the debug-only selector with the actual fixture
target, relative to the Flutter source root or equivalently qualified. Require actual tests
and teardown, not ADB exit alone. Roundtrip waits share one monotonic 60-second deadline plus
ten seconds for teardown; HOST timeout bounds blocking framework calls. On every outcome,
retire a remaining owned fixture process, verify retirement, then uninstall only owned
`app.wardpulse.widgetpublicationtest.test` and `app.wardpulse.widgetpublicationtest` packages.
Forced retirement cannot make incomplete teardown PASS. Rebuild `lib/main.dart` without the
selector; never copy back normal data. Full HOST gates remain separate. This fixture proves no
provider/scheduler behavior, normal-package acceptance or original-incident reproduction.
Historical evidence and visual acceptance below remain unchanged.

## Own-font rendering, states and accessibility

### Intrinsic geometry and size publication — 2026-11-06 revision

This technical revision preserves the approved Nov3 composition. It supersedes the
former two-variant implementation guard without increasing the global bitmap allowance.
The supported phone minimum remains API 24. `WardPulseAppWidget.hostSizes` retains finite,
positive, distinct API31+ advertised sizes after the existing sixteen-entry input guard;
the platform responsive-map limit is also sixteen. Ordinary three/four-size foldables
receive three/four actual advertised variants, rather than an independent-minima hybrid.
Null entries, duplicates and nonpositive entries do not become variants.

For supported older APIs, or a missing/null/empty usable advertised list, positive MIN/MAX
options are normalized per axis. Portrait uses minimum width/maximum height; landscape uses
maximum width/minimum height through the legacy `RemoteViews` orientation constructor.
Reversed bounds are normalized, a lone positive bound supplies both ends, and absent or
invalid dimensions use bounded 180dp width/110dp height defaults. Legacy estimates are
capped at 16384dp; planning pixels remain bounded at 16384. Identical orientations need
only one variant. Existing option-change and timezone refresh ownership is unchanged.

`ward_pulse_app_widget.xml` keeps the transparent, full-allocation root/tap target and
centers a `wrap_content` card whose bitmap layers also wrap content. In
`WardPulseAppWidget.buildViews`, each native bitmap plus its card-relative insets supplies
the intrinsic dimensions. Allocation-derived root padding is cleared. Bitmap, padding and
visibility actions are explicitly reapplied, including hidden/empty states. Painter failure
does not leave a painted empty card. Bundled fonts, native measurement, shared header,
whole-column fallbacks, complete rows and exact accessible values retain their existing owners.

`WardPulseAppWidget.publication` fits complete candidates before rendering, then sums
conservative stride-padded layer costs and a wordmark charge per variant. Shared wordmark
deduplication is not needed to justify the estimate. The publication allowance remains the
lower of 8MiB and the existing platform screen-pixel calculation; every bitmap remains
subject to the 4096-side guard. If the complete aggregate fits, no equal per-variant share
can remove content. Only an aggregate excess triggers refitting: inexpensive complete
plans retain their content, unused shares are redistributed, and remaining plans fit within
the remaining allowance before any content bitmap is created. Height/memory pressure may
still reduce complete trailing rows using the existing planner. More variants are a bounded
technical correction, not permission to change typography or omit fitting information.

Source evidence establishes a conditional former mechanism, not the physical incident's
cause: for planned height P, intrinsic card C and actual root height H, former root padding
and match-parent card measurement could produce C+(H-P). Equal planned/measured allocation
with the expected padding falsifies that mismatch for a case. Actual physical options,
selected variant, root/card/paint bounds and density remain Unknown. Historical illustrative
art, previous Pixel cases and failed dump parsers establish no physical cause.

The focused Android case and exact HOST command are documented in the
[phone component guide](../../apps/phone_flutter/README.md#android-widget-geometry-case-host-only).
It applies production RemoteViews/XML through an unattached `AppWidgetHostView`, independently
varies planning and measured allocations, and exercises reapplication, responsive selection,
legacy orientation fallbacks, complete fitting rows, states, exterior alpha and aggregate budgets.
Its SDK test facilities are test-only. Existing JVM plan/format/navigation tests remain useful
but do not prove Android application or host measurement.

At this revision, Android compilation/execution, matched runtime RED→GREEN, candidate native
geometry and post-DONE HOST checks remain **Pending**. Native reviews Android test source;
it does not run Gradle or substitute source inspection for runtime proof. Root must bind the
active artifact/widget/data/options/variant/density to original frames and measured root,
card and paint bounds, including an existing Pixel case, after Runner ownership releases.
Full-allocation cold/warm navigation, accessibility, themes, retained launcher fold/orientation
transitions and restoration still need that proof. Both physical devices remain STOP;
emulator evidence cannot close physical acceptance.

The public [Widget guide](user-guide/WIDGET.md) already describes this unchanged intrinsic
composition. Its ten current Widget image uses (selection, wide, labeled, primary-only and
short, in both themes) retain their existing PNG bytes and dated capture evidence. No new
capture or candidate image freshness is claimed. Root's fresh current-use/original-frame and
theme review remains Pending under the [screenshot index](../assets/README.md); replace only
images or instructions that actually need updating, preserving historical records.

### Preserved rendering contract

Every visible string uses the pinned bundled Noto Regular/Bold through the existing bounded
native painter, independently of system fontScale, family and force-bold. Preserve font
binaries, licenses and glyph checks, 4096 bitmap-side limits, the lower platform/8MiB byte
allowance and the bounded variants specified by the Nov6 revision. Review art and synthetic
JVM metrics do not prove native fit or system-setting independence.

Empty and no-fit states use the same intrinsic-card handling. Show complete `No metrics` or
`Resize widget` at 12 Regular when possible. Exceptionally tiny hosts retain accessibility
without clipped visible copy. Picker/phone subtitles distinguish `No metrics selected`,
`No default metrics available` and saved selections without current results. Supported
unknown budget rows retain Unavailable meaning, never a percent suffix.

The root accessibility summary describes only visible values, details and real resets,
preserves full metric identity when labels disappear, and distinguishes spent, remaining,
Extra used and cap quantities. Money descriptions retain full ISO/cents for the visible
primary and spent/cap details, omitting hidden details even when their values are known.
Decorative children stay excluded. The full root opens Dashboard through
the existing cold/warm readiness path; snapshot publication and coalescing are unchanged.

## Review art, documentation and historical evidence

`tools/render-phone-widget-designs.mjs` owns the default widget SVG/PNG exports, day/night
picker images, preview layout and only the generated preview description in strings_widget.
Regenerate through that owner; never hand-edit exports. Normal generation rewrites raster
exports; `--check` compares textual exports. Historical optional preview routes and their
original board/metadata stay unchanged. The current defaults use pinned bundled fonts,
short families, actual illustrative spent/cap detail, lower-right resets, intrinsic exterior
and a shared header.

Native acceptance stays **pending** until after whole Runner DONE, actual CLI/tool/observer
exits, all known-owned retirement and a separate fresh public idle/freelease. Root runs the
unchanged full phone/docs and applicable design checks, normal build/artifact/install and
unchanged-input JNI joins. Do not rebuild Rust for unchanged JNI owning inputs. Finite
native proof covers font settings, released-width 30/26/no-fit, actual row/reset/card/header
bounds, exterior alpha, states, selection, visible accessibility and full-root cold/warm taps.
Preserve newer legitimate data through restoration. Root's whole independent final Source
review remains required after the last correction. Native commits do not await HOST;
provider/live, physical, public-image and release gaps remain separate.

## Current review exports

These are illustrative nominal host frames, not device captures or provider/reset facts.

| SVG and matching PNG | Role |
| --- | --- |
| `widget-medium` / `widget-dark` | 360×344, six full rows including an illustrative capped expense |
| `widget-small` | 266×184, three rows with two-line labels |
| `widget-narrow` | 150×184, three primary-only rows |
| `widget-empty` | Complete bundled-12 No metrics fallback in an intrinsic card |
| `widget-stale` / `widget-stale-dark` | Shared STALE header and six complete rows |
| `widget-stale-narrow` | Shared header and three primary-only rows |
| `widget-stale-short` | Illustrative complete Resize widget fallback |

Picker values are static examples, not selected/current payload or publication evidence.

## Historical acceptance of the former renderer

The following is the dated former baseline and its 2026-10-11/13/24 observations. Its
system/SP fonts, content-hug geometry, row estimates, single-line Cursor Models exception,
export descriptions and acceptance claims are **superseded** by the 2026-11-01 revision
above. References to old export names describe their former contents. None is evidence
for the replacement renderer's native fit or acceptance.

### Former baseline and dated records

**Status: locked 2026-07-27** (revised **2026-07-28** — hug rows/columns, label-center /
credits-end, picker preview sample, day/night olive chrome; revised **2026-08-02** —
two-line label carrying the provider family; revised **2026-10-13** — stale badge clearance
and reliable Dashboard navigation; revised **2026-10-24** — compact numeric columns). Review art:
`apps/phone_flutter/design/` (`widget-small.svg` / `widget-medium.svg` / `widget-dark.svg`).

**Revision 2026-09-16 — Codex windows:** Codex and Spark remain per-window metrics on
the widget, with existing selections preserved. Their Watchface collapse/pairing does not
change widget behavior or geometry.

**Revision 2026-10-13 — stale clearance and widget navigation.** On the canonical phone
AVD `wardpulse_phone_play_api36`, launcher widget instance **2** showed genuine retained
failed-refresh data. `STALE` occupied **[93,562][188,601]**, intersecting the first
percentage at **[122,581][306,624]** and its accent. A warm widget tap from Settings also
returned to **Settings**, rather than Dashboard. These are observed defects; the fresh-only
2026-10-11 acceptance below did not cover either state.

The approved correction reserves space above the rows **only while stale**: the current
**11sp bold** badge line, including font padding, plus **2dp**. Runtime measures that line
with the current display/font metrics and uses the **same pixel inset** for row padding and
complete-row fitting. Fresh geometry and launcher-owned spans/options remain unchanged.
If resolved metrics exist but no complete row fits, show **`Resize widget`**; an empty or
unavailable payload still says **`No metrics`**. The watermark remains top-end. A widget tap
carries an explicit Dashboard action with a separate native/Dart readiness handshake, so
cold and warm delivery select Dashboard without adding a provider-refresh action. An explicit
widget tap first cancels active in-app forms and pushed routes with normal Cancel/back
semantics; ordinary app opens and watch-requested refresh preserve those routes.

**Device acceptance 2026-10-13.** The final Android x64 APK on this canonical phone kept
widget instance **2** in **[67,546][1013,1449]**, a 903px-high launcher frame. Genuine retained
failed-refresh data at normal font scale in light mode had a **39px** badge ending at
`y=601`; the first label began at `y=606`,
leaving **5px** clearance with a **44px** content inset. After a real app refresh at system
font scale **1.5** in dark mode, the badge measured **58px**, ending at `y=620`; the first
label began at `y=625`, again **5px** clear, with a **63px** inset. Both fresh and stale
placement were checked. These measurements establish badge clearance in this tall frame;
the fixed 12sp columns still ellipsize some labels and percentages at scale 1.5, as before.

An actual narrower frame **[67,546][519,1449]** removed label and credits columns while
retaining percentages. Its stale first percentage began at `y=606`, **5px** below the badge.
The original **four-column × three-row** placement was then restored to its exact bounds.
Warm taps from Settings and an open Budget dialog visibly opened Dashboard, canceling the
dialog. A settled background process was confirmed dead before the cold widget tap started
a different process; loading completed with three providers and data updated at **17:35:48**.
Host format/analyze and all **391** Flutter tests passed, including the navigation regressions;
the native widget harness passed **28** assertions. The existing 31dp body-row estimate
remains unchanged. Very short hosts, the `Resize widget` fallback on a launcher and text
scales above 1.5 remain separate device-fit checks; no hardware-device coverage is claimed.

**Revision 2026-10-24 — compact numeric columns.** The phone home widget displays a
remaining percentage as `N%` and an eligible purchased balance as its existing compact
number, without the visible words `left` or `credits` in those two columns. Accessible
descriptions retain remaining and purchased-credit meaning. Native runtime text remains
12sp; geometry, ordering, row/column fit, credit eligibility and known-zero/unknown rules
are unchanged. Previously saved descriptive strings render correctly without a new sync.
This revision does not change Dashboard, Wear or watch-face formatting, and does not
promise to resolve central metric-label truncation.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`.
Do **not** copy [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

### Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, multi-metric rows).
Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring slots.

### Metric rules

1. **One slot = one percent metric of one connection** — one connection's local budget for a
   period, a provider plan window, or a purchased meter (Extra usage, on-demand, credits %) when
   the provider reports a %. There is no summed Today / Week / Month slot: see
   `WATCH_RING_DESIGN.md` layer rule 1 for why a percentage across connections has no owner.
2. **Claude and Codex plan windows stay expanded** on the phone widget: Claude `5h`,
   `Weekly`, Opus/Sonnet weekly when present; Codex main and Spark primary/secondary
   windows when reported, including `Spark 5h` / `Spark Weekly`. Existing per-window
   selections survive unchanged. Watchface/Glance collapse Claude to one ring and Codex
   independently to one main-limit ring and one Spark ring before pairing.
3. **Cursor Models and Other Models** are separate selectable rows whenever the usage-summary
   reports both pool percents.
4. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette in `WATCH_RING_DESIGN.md`, where a Cursor plan's two pools carry their own
   colors since 2026-08-13. A budget row takes the family color of its connection; the neutral
   grey is a fallback for an unresolved family, not a product color.
5. **Purchased credits** — on **plan** rows, when that provider family reports finite purchased
   remaining credits, show columns: `N%` · label · compact balance (for example `59.5K`).
   Accessible descriptions retain the units. Same per-provider rule as Wear Glance / face
   strips — not a footer sum, not `creditsGlance`, never LLM `TOK`. Skip on purchased-meter rows (Extra
   usage / on-demand are the credit pool), budgets, and missing/unlimited balances.
6. **Omit** unavailable metrics (no percent). Exhausted plan/purchased meters (`usedPercent >= 100`)
   stay on the phone widget as **`0%`** so sibling pools remain visible. Watch/WFF likewise
   retain known selected exhausted metrics under their 2026-10-13 revision. The Widget tab
   states unavailability rather than hiding it: a metric with no
   percentage lists as unselectable under its own reason — *This allowance has no percentage to
   show*, seen on `Purchased credits` 2026-10-11 — so the rule is legible to whoever is choosing.
7. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

### Size caps (locked)

| Size | Slots shown | Notes |
|------|-------------|--------|
| Short | **1–2** | fewer metrics in Widget tab (~1–2 cells) |
| Mid | **3–5** | typical place size (`targetCellHeight≈3`) |
| Tall | **6** | prefs cap (`phoneWidgetSlotCount`) |

Prefs select up to **six** metrics; the olive card shows as many **complete** resolved
rows as fit the host cell, and as many **complete** columns as fit the width
(`wrap_content` hug). Trailing rows / right-hand columns that would clip are omitted —
never half-cut text. Horizontal drop order: **credits → label → `%`**. Vertical /
horizontal resize changes the launcher span; drag handles to the card to reclaim empty
cells. Newly placed widgets default to ~3 cells tall; **remove and re-add** if an old
tall span stays stale. Unused slots stay omitted, not filled.

Default (unset) selection prefers **plan windows** first (Claude + Cursor + Codex), then
purchased meters, then local budgets — so 5h / weekly / Cursor Models / Other Models are not
crowded out by Extra usage. A budget row only becomes selectable once its connection has a
limit for that period, so an unconfigured install defaults to plan windows.

### Composition (locked)

```text
┌─ olive card hugs complete rows + columns ──────┐
│  ▌ 22%          Claude       80           ⌇wm  │  ← tightest remaining first
│  ▌            Weekly plan                      │
│  ▌ 46%          Claude      320                │
│  ▌           5-hour session                    │
│  ▌ 71%       Cursor Models  2.1K               │
└────────────────────────────────────────────────┘
┌─ mid (credits dropped) ────────────────────────┐
│  ▌ 22%         Weekly                     ⌇wm  │
│  ▌ 46%           5h                            │
└────────────────────────────────────────────────┘
┌─ narrow (% only) ──┐
│  ▌ 22%        ⌇wm  │
│  ▌ 46%             │
└────────────────────┘
     (transparent cell beyond the card if the span is larger)
```

- Rows, not concentric arcs.
- Family accent bar (▌) on each metric row.
- **Columns** — remaining `%` · centered label · compact purchased balance (end-aligned).
  Only the numeric columns omit visible `left` / `credits`; the Widget tab stays descriptive.
  One widget accessibility description names each visible metric and its remaining percentage,
  plus purchased credits only when that column and balance are present; child cells do not
  speak again. Hidden rows contribute nothing. Width hide order:
  credits first, then label; missing credits still reserve the credits column when that
  column is shown (label stays centered).
- **Label is two lines** (revised **2026-08-02**) — family on top, pool below. The provider
  must be readable at the baseline text scale; larger scales can ellipsize the fixed-width
  columns, as measured at 1.5 in the 2026-10-13 acceptance above. Nothing else names it:
  colour alone cannot tell one `Weekly plan` from another. The column keeps its fixed
  width, so the cost is height, not width: rows are `ROW_CONTENT_DP` 31 instead of 17 and
  the card hugs taller. Every row reserves both lines (`android:lines="2"`), so a label
  that already carries its family — `Cursor Models` — leaves the second line empty rather
  than making rows uneven.
- **Day / night** — olive phone chrome (`#F2F4F1` / `#101412` via `values` /
  `values-night`), not provider fills. Soft 20dp card + hairline outline; runtime card
  **hugs** complete content so unused cell area is wallpaper. Widget-picker preview uses a
  dedicated sample layout (`ward_pulse_app_widget_preview`) that hugs the sample rows
  (no empty olive band under them) and follows the same day/night colors when the system
  theme is dark.
- **Resize** — `horizontal|vertical` with **no** tight `maxResizeHeight` (a span taller than
  the max makes Pixel drop vertical handles). Height / width decide how many **complete**
  rows / columns fit. Newly placed widgets use `targetCellHeight≈3`; **remove and re-add**
  after metric-count changes if the launcher keeps a stale tall span.
- **Watermark** — same faded mono as the watch face, ~36dp overlay top-end (does not
  reserve a header band). Fresh widgets have no dedicated header.
- Empty: short “No metrics” line (no filler rows).
- Too short for a complete resolved metric: “Resize widget”, with no clipped metric rows.
- Stale: compact uppercase “STALE” top-start when the last dashboard is stale. Reserve its
  measured padded line plus 2dp above content and subtract that same space when fitting rows;
  remove the inset when fresh.
- Tap opens the phone app (Dashboard).

**Verified on a device 2026-10-11 — the baseline holds.** Locked since 2026-07-27 and revised
three times, this composition had never been read off a launcher. It was, on the canonical phone
AVD `wardpulse_phone_play_api36` at `fad6bb9`, paired live with the round Wear AVD so the payload
was the one the watch was drawing. Nothing measured contradicted a rule above.

Five selected metrics, placed from the picker — whose entry declares **3 × 3** and whose preview
hugs its three sample rows with no empty olive band beneath them:

```text
40% left    Claude / 5-hour session     ← tightest remaining first
68% left    Cursor / Other Models
72% left    Claude / Weekly plan
92% left    Codex  / Weekly plan
100% left   Cursor Models               ← second label line empty, rows stay even
```

**That order held under a live change.** Later the same session a Claude window crossed its own
threshold unprompted, with nothing staged and the phone untouched, and the placed widget
followed by itself: the top row became `13% left · Claude / 5-hour session` and the list
re-sorted to `13 / 67 / 68 / 92 / 100`. No reinstall, no re-placement, no visit to the Widget
tab. Tightest first is a rule the surface keeps as the numbers move, not an arrangement that
happened to be true at the moment it was first read.

**Hug and drop order**, taken from the view hierarchy rather than from a screenshot:

| Span | Launcher cell | Olive card | Credits column |
|------|---------------|------------|----------------|
| as placed | 699 × 903 px | 544 × 489 px | dropped |
| widened | 946 × 903 px | 791 × 489 px | **shown** |

The card hugged 544 px inside a 699 px cell and omitted credits; widening the span to 946 px
brought them back as `62.5K credits`, end-aligned on the Codex `Weekly plan` row, with the four
rows carrying none still reserving the column and keeping their labels centred. Compact is metric
rule 5 and agrees with the face strip and the Glance row — the Dashboard spells the same balance
`62,479.3 credits` (`PHONE_DASHBOARD_DESIGN.md`, Balances), because compaction belongs to a
glance and that screen is not one.

**Chrome sampled from the live card:**

| Theme | Sampled | Declared |
|-------|---------|----------|
| light | `#F2F4F1` | `ward_pulse_widget_surface` in `values/colors_widget.xml` |
| night | `#101412` | the same name in `values-night` |

Exact both times. Switching the system theme swapped surface, text, accents and watermark
together and left the composition alone.

Also confirmed: accent bars in the product palette (Claude orange, Cursor Other Models teal,
Cursor Models periwinkle, Codex green); the watermark top-end with no header band reserved; a tap
opening `app.wardpulse/.MainActivity`; and the empty state hugging one `No metrics` line with no
filler rows, its watermark overlapping that line exactly as `widget-empty.svg` draws it.

**Not reached: the `STALE` overlay.** The payload on the device was fresh, so nothing was observed
of it and nothing here claims otherwise. One AVD, one build, one launcher.

### Non-goals

```text
copying concentric watch-face arcs onto the launcher
interactive controls inside the widget
iOS widgets
burying Widget config under Settings
collapsing Claude plan windows on the phone widget (Watchface only)
```

### Review art

Canonical review generator: `tools/render-phone-widget-designs.mjs` — it reads the accent and
chrome colours straight from `res/values{,-night}/colors_widget.xml`, so the boards cannot drift
from the app without the resource moving too.

```sh
node tools/render-phone-widget-designs.mjs
```

| File | Role |
|------|------|
| `widget-medium.svg` | light mid preview (credits + watermark) |
| `widget-dark.svg` | dark mid preview (same composition) |
| `widget-small.svg` | short (2 rows); default place size ≈ 2×2 |
| `widget-empty.svg` | empty selection |
| `widget-stale.svg` / `widget-stale-dark.svg` | stale-only badge clearance in day/night chrome |
| `widget-stale-narrow.svg` | stale badge with only the complete percentage column |
| `widget-stale-short.svg` | known metrics cannot fit a complete row; `Resize widget` |
