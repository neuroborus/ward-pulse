# Watch Ring Design

**Baseline locked 2026-07-25**; melt / strip-accent revision **2026-07-27**; ring-cap /
purchased-meter revision **2026-07-27** (max three plan/budget rings; Extra usage and other
purchased meters are not rings); band-width revision **2026-08-02** (see Ring geometry);
per-connection budget revision **2026-08-08** (budget rings belong to one connection and take
its family color; the summed Today / Week / Month rings are retired); budget-strip revision
**2026-08-09** (a budget strip reads `$12.34/100` instead of a percent); ring-type revision
**2026-08-11** (a budget ring repeats its period around its own band as cut-out type);
split-band revision **2026-08-13** (one Cursor plan's two pools may share a single band, and
Cursor's own models take a colour of their own); full-ring revision **2026-08-17** (a band with
nothing spent closes instead of carrying a seam); two-split-slot revision **2026-09-16**
(far markers move into strip slots; slots 106/109 carry the two outer halves); near-exhaustion
revision **2026-10-01** (a positive remainder below the two-cap cutoff stays visible);
clock-colon revision **2026-10-01** (the device-font one-pixel imbalance is accepted without
splitting the time); near-exhaustion correction **2026-10-06** (straight ends keep that
remainder proportional); upper-cell revision **2026-10-09** (three user-owned complication
cells above the clock; the legend strips fold into their own ring slots and the stack anchors
to the bottom row; `BoundingArc` is measured as the cause of the half-nominal band; the default
temperature and UV reading is the face's own scene chrome from the built-in `WEATHER.*` source
and costs no slot); melt-length correction **2026-10-09** (each band declares the 20 units it
paints instead of 40 under a clip, and the melt grows to the remainder it always meant);
cell-layout correction **2026-10-09** (the three cells leave the straight row for an arc
concentric with the face, shrink to 42 units, and a cell showing nothing takes a graded rim so
that empty reads as empty); occupied-cell revision **2026-10-10** (a cell showing anything
wears a hairline, so a ring means occupied and a recess means free); ambient-legend revision
**2026-10-10** (the legend strips dim at alpha 90 instead of switching off, so ambient keeps
the credits and the budget money that live nowhere else on the face); preview-ownership
revision **2026-10-10** (the picker image and the face review previews this document cites
are generated from their boards instead of carried by hand, so no preview keeps a face the
product has left behind); cell-ring correction **2026-10-11** (the hairline is inscribed in the
well, radius 20.0 to 21.0, not inset a quarter of a unit as four places said; the geometry is
unchanged and only its description moved); preview-coverage revision **2026-10-11** (every
review board has a preview, derived from the board list rather than kept beside it, so the
three baseline boards that had none are no longer unwitnessed); preview-surface correction
**2026-10-11** (that the picker displays the declared asset was inferred from the metadata,
never seen; the one direct measurement shows it rendering the face live, so the ownership
rule is restated as resting on the asset being shipped, not on which surface displays it);
watermark revision **2026-10-11** (the shipped portrait carries the quiet mark
the face draws, and the brand copy of that picture is retired); cell-editing correction
**2026-10-11** (the three cells were unreachable on the watch because
`watch_face_info.xml` never declared `Editable`, which defaults to false and withholds the
system's Edit button; with it declared, the editor was read opening on the three cells and
nothing else, and the `SHORT_TEXT` Battery provider was seen drawing text in a cell;
`RANGED_VALUE` rendering with data remains unverified); weather-reading revision **2026-10-12** (the two weather cells carry their
marks — `51°` and `UV 7` — where they had templated the bare expression since the cells
shipped; the temperature takes the degree sign and no scale, because the value already
arrives in the unit the wearer's device chose); temperature-scale revision **2026-10-13**
(the owner chose an explicit scale, `51°F` or `18°C`, taken from the device's weather unit;
the complete reading is centred, replacing the degree-only numeric correction); cell-border
revision **2026-10-13** (the occupied-cell border widens inward to 1.5 units and dissolves
towards the nearest band); cell-position / radial-direction revision **2026-10-13** (the
three complete cells move three units lower and the fade follows the true shortest radial
path to the band, derived from each cell's integer centre); selected-zero revision
**2026-10-13** (known exhausted selected metrics retain their grey tracks and legend rows,
with only exhausted `0%` tokens in the existing pale error red; paired pools retain both
identities); readability revision **2026-10-25** (104×22 legend wells with finite 15/14/12
fonts; initially 48-unit upper cells with 16/14/12 readings); outward-preserving refinement
**2026-10-25** (50-unit cells with 17/14/12 readings; retain all outward fades and add only
the lateral bottom treatment); combined composition revision **2026-10-25** (raise clock
and watermark; 120×26 legend with 18/16/14 labels); exact-full construction revision
**2026-10-26** (remove the remaining end inset from the full-only path; native acceptance pending);
centred composition revision **2026-10-27** (historical logo-above-clock layout; 132×26 legend
with 20/18/16 labels); upward-digit revision **2026-10-27** (larger whole clocks retaining
the 08:08 reference bottoms, 52-unit cells and 64/54-square logos; bounded native evidence below);
adaptive-band revision **2026-10-28** (resolved counts select 68/32/20-unit bands;
generic ranged envelopes replace the raw percentage interface; native acceptance Pending);
N1-width revision **2026-10-30** (explicit 44/32/20-unit bands; N1 halves are 22;
new-radius raster fits below; native acceptance Pending); retained-extra compositing repair
**2026-10-31** (extras precede main tracks; unsplit N1 restores the local backdrop;
new-artifact native acceptance Pending); temperature-choice revision **2026-11-01**
(one face-local Auto/Celsius/Fahrenheit editor
choice for built-in weather only, default Auto; current-candidate native acceptance Pending);
active-clock translation **2026-11-01** (Owner-approved 10-unit rise of the whole active clock;
ambient unchanged in that revision; new-runtime native/public acceptance Pending);
ambient-clock alignment **2026-11-03** (one global 86 Thin candidate at the active clock's
reference placement; optical/native/public acceptance Pending);
short-positive endpoint revision **2026-11-01** (compressed elliptical caps in a local
WFF2 mask; source/review construction only, native acceptance Pending)
— locked visual target for
Wear OS and Watch Face Format until the next explicit design revision.
Implementation and review art must follow this document; do not reintroduce side-by-side ring
wireframes, large remaining-% heroes, or bordered strip cards.

The operative effective layout follows the
[whole-composition revision](#revision-2026-11-02--whole-composition-scale-and-paired-source-allowance).
Positive paired MAIN coverage follows the
[bounded contour correction](#revision-2026-11-02--bounded-paired-main-coverage).
Earlier geometry below remains reference geometry beneath its common carrier, or dated
historical evidence for the bytes measured then. The reference clocks follow the
[ambient-clock alignment](#revision-2026-11-03--ambient-clock-alignment), retaining the
[approved active-clock translation](#revision-2026-11-01--approved-active-clock-translation), the
[2026-10-27 non-clock composition contracts](#revision-2026-10-27--upward-digits-and-fixed-reference-bottoms) and the
[outward-preserving cell contract](#revision-2026-10-25--preserved-outward-fade-and-50-unit-cells).
Band widths follow the [N1-width revision](#revision-2026-10-30--n1-width-44), retaining the
[adaptive admission contract](#revision-2026-10-28--adaptive-bands-from-resolved-count).
Partial endpoints follow the [short-positive revision](#revision-2026-11-01--short-positive-rounded-endpoints);
its construction supersedes the historical straight-end/ROUND drawing switch, retaining its admission gates.
The earlier bottom-only/uniform-centre candidate below is superseded, not accepted intent.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-watch-ring-designs.mjs`  
Canonical face generator: `tools/render-watchface.mjs` — it writes the shipped `watchface.xml`
and the ring-type drawables beside it.  
Canonical preview: `apps/wear_android/design/preview-3-plan-credits.png` (and sibling variants).

## Revision 2026-11-03 — ambient-clock alignment

Use one global ambient candidate with the active clock's reference size and placement,
removing the ambient-only enlargement and downward displacement. Active remains exact.
Both clocks stay beneath the existing single **225/202** scale about **(225,225)** on the
unchanged **450×450** canvas.

| Clock | Runtime `TimeText` | Review SVG |
| --- | --- | --- |
| Active, unchanged | **x=0, y=166, width=450, height=90**, **86 Bold**, `CENTER` | Font **86**, weight **700**, baseline **240.78125**, rendered **240.8** |
| Ambient | **x=0, y=166, width=450, height=90**, **86 Thin**, `CENTER` | Font **86**, weight **100**, baseline **240.78125**, rendered **240.8** |

`CLOCK` in `tools/render-watchface.mjs` owns the runtime profile; `CLOCK` in
`tools/render-watch-ring-designs.mjs` owns the illustrative host baseline.
`check_composition_scale` in `tools/check-watchface-structure.py` guards both emitted
profiles, including their weights, whole centered `hh:mm`, device-synchronized family/hour
format, original color and inverse AMBIENT alpha swaps. Natural glyph advances and colon
spacing remain device-defined: no per-time or per-count offsets, split or stretched glyphs,
font replacement or new alpha. Equal boxes and host baselines do not establish optical alignment.

This supersedes the ambient **175/90/96 Thin** profile and **254.296875** review baseline
retained by the 2026-11-01 active-only translation. The 2026-10-27 fixed-bottom calibration,
ink bounds and gap/fit measurements remain historical evidence for their original artifacts;
they do not measure this candidate. All cells, original logo pixels/boxes/alpha, legends,
taps, transport and A1 seam/cap/mask/zero/full/palette/data/slot contracts remain unchanged.
Generate canonical runtime resources before review SVG/mirror/PNG exports; preserve active
rendered content and unrelated resources, excluding metadata-only churn. Clock-only previews
retain their isolated local outputs and existing offset semantics.

**Optical, native and public acceptance: Pending.** After whole Runner DONE, owning CLI exit,
scoped retirement and fresh separate idle, Root owns the five HOST gates and separately
admitted device work. Join Legacy Source/resource/build/installed/active identities and
effective inputs; retain matched whole-clock and whole-face INTERACTIVE and renderer-proven
AMBIENT originals for bounded wide/narrow and 12/24-hour cases. Measure visible height,
position, centering and clearances with actual raster limits, without a universal tolerance.
MUTE/Doze does not prove AMBIENT; original MUTE remains a valid restoration target. Prove
restoration of touched clock/timezone/format/effective DND and derived surfaces, preserve
newer Live and incident evidence, and retain physical STOP and protected Square/Main/Test/Push.
Open A1/native/public acceptance is not closed by this candidate or its review art.

## Revision 2026-11-02 — bounded paired MAIN coverage

The Round384/API36 INTERACTIVE original for Source `a3f5a3a` retained dark uneven
Claude/Fable and Cursor own/other shared contours after the whole-composition enlargement
and partial SOURCE allowance. That finding remains OPEN; it does not identify a renderer
or antialiasing cause. The Owner-admitted correction is a bounded positive MAIN overdraw,
not another scale or a native acceptance claim.

For nominal paired-main diameter `d` and thickness `t`, `PAIRED_MAIN_COVERAGE` in
`tools/render-watchface.mjs` gives every positive full/tiny/round foreground diameter
`d + 1` and thickness `t + 1`. Its inner edge stays `(d - t)/2`; its outer edge becomes
`(d + t)/2 + 1`. Tracks and branch predicates retain nominal dimensions and published
cutoffs. Partial SOURCE uses `d + 1` / `t + 3`, retaining the existing one-unit allowance
beyond each new MASK edge. Extra-half SOURCE, MASK, full paint and track construction
remain unchanged. Zero still paints only its nominal track.

| Layout, outside first | Nominal MAIN radial intervals | Positive MAIN coverage |
| --- | --- | --- |
| N1 | 158–180 | 158–181 |
| N2 | 170–186; 134–150 | 170–187; 134–151 |
| Legacy / N3 | 182–192; 158–168; 134–144 | 182–193; 158–169; 134–145 |

Only the positive MAIN pool owns this overlap, including beside a zero or temporarily
absent extra; it creates no peer foreground or label. It stays within the band's nominal
union. Outer202/effective225, border0, aperture, inter-band gaps, clips and the existing
single225/202 composition scale remain unchanged. One reference unit becomes approximately
1.11386 canvas units or0.9505 physical pixels on Round384.

For partial sweep `S = 359.9 * value/max`, recompute `c = capDegrees(d + 1, t + 1)`,
`a = min(c, S/4)` and tangential radius `(t + 1)/2 * tan(a)/tan(c)` with angles converted
to radians. The core and both endpoint ellipses share those dimensions; there is no floor.
An integer Ellipse base `x` precedes its existing live `x` Transform, preserving legal WFF2
base attributes without rounding the effective endpoint. Full stays one un-inset ROUND
path from0 to359.9. The existing proportional-error bounds also apply to these changed
profiles; the independent emitted guards evaluate their actual core/cap dimensions and
retain nominal gate-boundary tests.

Extras still precede MAIN in the runtime scene. The review mirror now draws extra before
MAIN and mirrors only this bounded positive coverage, retaining measured N3 geometry,
the historical360-degree illustration and thinner/gray ambient art. Nominal envelopes
and permitted foreground coverage are distinct; neither a source annulus nor an illustration
proves native continuity. Each foreground retains active255/ambient140 exactly once.
Two translucent foregrounds overlap in the new strip: actual renderer-proven AMBIENT
partial/full and genuine full/full frames must reject a bright, dark or mixed-color fringe.

`fixtures/snapshots/watch_dashboard_summary_n3_pairs_full_full.json` is historical schema9
Mock support: exhausted ordinary Codex first, then full Claude/Fable and Cursor own/other.
All four paired used percentages are0. Payload split ordinal0 maps to slot106/outside1;
ordinal1 maps to slot109/outside0, both with value800/MAX800. This is distinct from ordinary
full/full and paired100/99.9 controls. Task-owned static XML preserves the selected bounded
R/F/Z/N2/N1/M inputs and transition endpoints, their historical timestamps and exact decoded
JSON identities, plus this new case; it is not current Live or native proof.

**Native effectiveness and complete fit: Pending.** Preserve the failed original and its
strict `red < min(innerRed, outerRed) - 12` diagnostic (more than12 below both reds), without
an inclusive recount or numeric PASS threshold. Retain the unowned Live54→52 history and
newer data; no identical-input A/B claim is established. Whole Runner completion, CLI exit,
retirement and separate idle precede HOST gates, fresh Round artifact/Reader qualification,
bounded whole-frame INTERACTIVE/AMBIENT controls and guarded restoration. Physical STOP,
protected Square and all existing semantic/admission/fit/isolation safeguards remain.

## Revision 2026-11-02 — whole-composition scale and paired SOURCE allowance

The Owner selected the entire accepted radius-202 composition enlarged to radius **225**
about **(225,225)** on the unchanged **450×450** canvas. Apply **225/202** once to all
positions, time/glyphs, cells/rims, logo, legend/wells/padding/accents, arcs/strokes/gaps/caps,
backdrop, masks/clips and period imagery. There is no residual inset or separate clock rise.
Reference literals, families/weights, original logo pixels/alpha/fade, palette, labels, units,
device-synchronized whole time/hour format and data meaning remain unchanged.

`COMPOSITION_SCALE` and `SCALE_ATTRIBUTES` in `tools/render-watchface.mjs` put documented
`scaleX`/`scaleY` and normalized `0.5` pivots on each full-face ring/extra slot, `DigitalClock`,
the watermark Group and the named `compositionChrome` Group. Scene has no scale attribute;
all eight slots remain direct Scene children. Each customizable slot now has integer
rectangle (0,0,450,450); its content Group and BoundingBox retain the original integer
52-square cell position. Thus chrome, populated content, clipping, editor and tap bounds
share the same transformation rather than scaling paint around a small slot's local center.
Nested coordinates, fonts, image boxes, strokes and masks are not multiplied again.

| Quantity | Reference | Effective geometry |
| --- | --- | --- |
| Outer radius / canvas border | 202 / 23 | 225 / 0 |
| Full band widths N1 / N2 / N3 | 44 / 32 / 20 | reference × 225/202 |
| Half widths and inter-band gaps | 22, 16, 10 / 4 | reference × 225/202 |
| Position coordinate q | original integer or legal float | 225 + (q − 225) × 225/202 |
| Cell / legend well / active logo size | 52 / 132×26 / 64 | reference × 225/202 |

WFF floating-point attributes and renderer rasterization do not promise exact decimal
pixel placement. A full-face slot's transformed rectangle exceeds the physical canvas;
the final viewport still clips at 450. The extra-slot reference clip remains radii 139..207
and scales with its slot; its margin is not a visible outside reserve. Native editor/tap
dispatch, clip behavior and complete clock/cell/legend/logo fit remain acceptance work.

The earlier `PAIRED_SOURCE_ALLOWANCE` candidate selected a bounded seam hypothesis: paired inner and extra
**partial** colored SOURCE strokes gain **one reference unit on each radial side**. Their
centerline, nominal white MASK core, elliptical caps, percentage calculations and cutoffs
stay unchanged. Ordinary partials, full paths, tracks and zero gates retain their paint.
The approximately one-native-pixel Round allowance tests repeated SOURCE/MASK edge attenuation;
it adds no unconditional bridge or visible-envelope extension and establishes no AA cause.
That SOURCE-only candidate did not eliminate the observed shared contour. The bounded MAIN
correction above supersedes its unchanged-MASK foreground construction for positive MAIN only.
The shared contour must still prove continuous in actual paired full/full and partial/full
controls, including ambient; an unresolved seam is a finding, not accepted improvement.

All **18** period textures are regenerated from their reference SVG geometry using the
existing named-file rasterizer and original Noto Sans Bold, repeat counts, breaks and opacity.
Density targets **ceil(referenceDiameter × 225/202)** samples: reference 404/356/332/308
becomes 450/397/370/344 pixels. PNG dimensions are asserted on generation and drift inspection.
Multiply the integer numerator before division so binary scale rounding cannot turn the
exact 404→450 case into a spurious 451-pixel raster.
WFF image boxes keep reference dimensions under the scaled slot, so sampling is not a second
geometric enlargement. Original watermark input pixels remain untouched.

Ordinary review boards, mirrors and the fixed historical illustration use one whole SVG
composition transform. The measured active N3 model retains width **20.205**, gap **3.78**
and centerline **191.88**, distinct from runtime nominal **20/4/192**. Its effective outer
edge is approximately **224.9805**, not an assertion of identical runtime geometry. Historical
thinner/gray ambient art remains illustrative. The portrait reads the watermark's effective
box from canonical XML, rounds each raster edge once, and derives width/height from those edges;
the active overlay is (189,131,72,72), with reference and nominal float bounds retained in metadata.

`--viewport-preview-output` now consumes that same completed composition without a 216-radius
override or another scale. It retains historical Claude/Fable 88/100, Cursor 100/64 and Codex
0% · 49.7K as explicitly historical illustrative data, not current Live. Its exclusive local
PNG/SVG/metadata output retains input/output hashes and canonical-write isolation. The separate
clock-only preview remains unapproved experimentation; its requested upward offset means final
450-unit displacement after the common scale, and only its clock coordinate may differ.

**Native and public acceptance: Pending.** Emitted guards check legal carriers, integer base
rectangles, common pivots, exactly-once geometry, bounds, texture sampling and SOURCE allowance
behind their owning masks, while retaining admission, zero/full/cap, ordering and backdrop guards.
Official WFF2 and pinned Push semantic validation, whole joined Round INTERACTIVE and renderer-proven
AMBIENT originals, bounded fit/count/pair controls and guarded restoration follow whole Runner
DONE, CLI exit, scoped retirement and fresh separate idle. Preserve then-current Live/order,
newer legitimate publications, physical STOP and protected Square. Historical native receipts
and clean review art do not accept these bytes; there is no additional Owner layout approval gate.

## Revision 2026-11-01 — short-positive rounded endpoints

The selected construction changes only positive partial endpoints in `bandPaint` in
`tools/render-watchface.mjs`. Both existing tiny and round gates retain their names,
predicates and published cutoff literals but draw the same silhouette. For requested
sweep `S` in degrees, radius `R`, half-thickness `h`, and the historical rounded
`c = capDegrees(diameter, thickness)`, use `a = min(c, S/4)`. The full-width BUTT core
runs from `359.9 - S + a` to `359.9 - a`, retaining at least half the positive sweep.
Two filled ellipses centered on those endpoints have radial radius `h` and tangential
radius `b = h*tan(a)/tan(c)`, with trigonometric arguments converted to radians.
There is no minimum sweep, percentage or cap radius. At `S >= 4c`, `b = h`: the core
and circular caps reproduce the existing ideal ordinary/near-full ROUND silhouette.
Exact full retains its single un-inset ROUND path; true zero retains only its track.

One named local WFF2 composition uses the fixed, un-inset live-ColorRamp annulus as
SOURCE and one opaque MASK group containing the core and both rotated ellipse drawings.
Only the composed foreground applies active alpha255 / ambient140. The mask never
reaches tracks, legends, adjacent bands or the separate unsplit-N1 backdrop restoration.
Every added group has a stable name. No blendMode or newer format is introduced.

The actual ideal angular half-extent is `phi = atan(b/sqrt(R²-h²))`, not `a` in general.
With all angles in radians, let `K = h/(sqrt(R²-h²)*tan(c))`; then `phi = atan(K*tan(a))` and
`|phi-a| <= |K-1|*tan(a)` because atan is 1-Lipschitz. Thus the angular footprint
`S - 2a + 2phi` differs from the requested sweep by at most `2|K-1|*tan(a)`.
Across the admitted Legacy/N1/N2/N3 geometries this bound is below **0.04136°** and
below **0.151% of the requested positive sweep**; these are error bounds, not paint
floors. The error shrinks with the sweep. At saturation it retains the existing
rounded-cap calibration error rather than asserting an exact angular footprint.
Since `0 < b <= h < R`, every ellipse fits inside its radius-h endpoint disc and
therefore inside the unchanged radial annulus `R-h .. R+h`.

`assertNearExhaustedArcs` and `tools/check-watchface-structure.py` inspect finite zero,
tiny, published-cutoff and saturation neighbours, ordinary, near-full and exact-full
cases, including both outer ordinals. Their interpretation follows the mask union;
the full SOURCE annulus is not counted as unmasked foreground. Existing admission,
ownership, retained-extra and count-change regressions remain. The review generator's
`ringArc` mirrors the core/ellipse mask while retaining its measured radii, ambient
palette and historical 360-degree review circumference. Generated art is not native proof.

The historical N1 below/above RED still has an absent expected Spark head with
191/191 projected interior pixels reading track; the reverse control has a visible
rounded head. Float-narrowed endpoints collapsed in both controls, so this revision
does not establish a consumer, callback, evaluator or precision cause. Those original
cases remain consumed evidence. Fresh synthetic operational XML is prepared outside
committed fixtures for independent review before the controlled-summary debug-AVD procedure.
Repository fixture validation does not imply that ignored XML was scanned or rendered.

Native acceptance remains **Pending** after this source/review change: whole-run
completion and retirement precede HOST official WFF2 and pinned Push semantic/resource
validation, artifact/active-instance joins, finite positive/cutoff/true-zero native-scale
observations, ambient/overlap review and guarded ordinary restoration. Preserve newer
live delivery, Round Legacy and protected Square state. Unavailable consumer fields and
callback/evaluator precision remain Unknown; no Push/Square/physical/public or performance
acceptance is inferred. Three bands, two split ordinals, eight slots, pair/Fable identity,
all admission/data rules, full closure, tracks and the raised clock/cells/logo/legend
retain their owning contracts.

## Revision 2026-11-01 — approved Fable palette

The owner approved replacing exact Fable `#FF8A00` with `#FF603D`, a warm red with an
orange tint, across the face/marker, Glance, Dashboard and widget. Ordinary Claude
remains `#E8915A`. The current Fable rules below use the replacement accent; matching,
pair identity, zero/unknown/error styling, alpha, caps, pivots, geometry, raised clock,
typography, data and selection rules remain unchanged.

New-palette native/current-Legacy and public proof remain **Pending** for the separate
post-execution HOST handoff. Historical observations and bounded prior acceptance
retain their dated scope; generated review art does not establish painted native color.

## Revision 2026-11-01 — included Fable weekly metric

The selected Claude/Fable design adds one exact metric accent: `claude-seven-day-fable`
and ring `allowance.claude.claude-seven-day-fable` use **`#FF603D`**. Ordinary Claude,
legacy Opus/Sonnet and Anthropic budgets keep **`#E8915A`**. Provider/status chrome
retains its existing theme roles.
This is a selected palette rule; no native color or fit measurement is claimed here.

For the recognized pair, ordinary `allowance.claude.plan` is inside/left and Fable is
outside/right. Rank the whole band by its tighter half without exchanging identities.
The outer token is exactly `fable`: `split:fable` and its `:zero-inner`, `:zero-outer`
and `:zero-both` forms join the closed vocabulary. Both markers remain, including at
known zero; the strip remains two percentages without credits. Unknown is not zero.
An unavailable half retains the existing known-survivor fallback.

The existing three bands, two split ordinals, eight slots, service identities, accepted
clock/logo/cells, geometry, typography, caps, textures, fades and alpha rules are unchanged.
The phone catalogue now exposes **Claude plan** and **Claude · Fable** separately, retaining
the winning ordinary window and Fable weekly subtitles. Native/current-Legacy and public acceptance remain **Pending** until
the whole execution and HOST handoff. Historical records below retain their dated scope.
`round-plan-fable.svg` and `round-plan-fable-zero.svg` are generated synthetic review art,
not captured provider consumption or native acceptance.

**Selection revision 2026-11-01.** Enforce both three bands and two completed pairs before
publication using the existing schema-9 split shape and slot ownership. Defaults greedily
admit available candidates in catalogue order; completing a third pair is excluded with its
split-capacity reason even when three bands would fit. Ordinary semantic ID migration and
deduplication do not admit or trim explicit selections. Null still requests defaults; an
explicit empty choice still publishes no rings; valid saved choices retain their order and IDs.

An invalid saved combination stays visible in **Correct ring choices**, with distinct band
and split reasons. Reject invalid additions without saving them. Selected unavailable or
missing metrics remain removable, including while another removal is still required.
Validate the full saved choice before filtering unavailable data or encoding a payload.
Keep the last published watch summary until correction, while provider polling, local
Dashboard and six-row independent widget updates continue. Capacity is a selection constraint,
never an allowance's unavailability status. Native correction/delivery and public captures
remain Pending for the post-execution HOST handoff.

## Implementation repair 2026-10-31 — retained extra paint

Square's delayed Codex37 + Cursor70/Other50 → main-only Codex80 observation showed old
Other teal overlapping the new main band until extra NoData removed it. The original
frames, redacted TITLE/value/text, historical Pending labels and exact recovery receipts
remain immutable. They establish neither the selected historical branch nor a cache or
framework fault.

`face` in `tools/render-watchface.mjs` emits slots 106/109 before main slots 101/102/105.
Each admitted main draws its existing opaque track over overlapping retained extra paint,
then its current family arc. The source-derived old N2 outer half spans radii 186–202;
the full N1 band spans 158–202 and contains it in ideal geometry. That first scene-order
repair removed the large old teal half, but coincident outer edges did not fully occlude
its raster fringe.

**Native f5 finding, 2026-10-31:** matched same-clock main-only and extra-cleared originals
had identical main core, yet **1031 outer-edge pixels differed**, with maximum channel
difference **57**. At native pixel (173,18), RGB (56,93,85) became (30,36,33). The strong-teal
classifier returned zero, which tests neither all mixed antialiased color nor acceptance.
This is one bounded retained-extra color contribution, not a renderer-cache diagnosis,
numeric/TITLE/selected-branch acknowledgment or a requirement for arbitrary frame equality.
The consumed f5 attempt and its separate later normal recovery remain historical evidence;
they do not accept new Source or artifact bytes.

**Outer-edge correction (Source only):** `n1BackdropRestore` in
`tools/render-watchface.mjs` precedes the track, family arc and period texture only inside
the admitted unsplit N1 branch, including zero. Its stable named full-canvas
`ring1N1BackdropRestore` Group contains the existing `lift` ellipse and identical opaque
radial gradient as SOURCE, followed by a white Arc MASK: centre 225/225, diameter 387,
thickness 27, ROUND caps, sweep 0–359.9. WFF2's parent-local SOURCE/MASK composition restores
the actual backdrop through radii **180–207**, rather than painting a wider foreground
track. The inner mask edge lies inside the opaque N1 track; 207 reuses the existing extra
clip boundary. Restoring the backdrop beneath the intended outer contour is expected to
remove the obsolete-extra contribution. This bounded coverage choice needs matched native
proof; it establishes no universal AA margin or threshold.

The 450 canvas, centre, outer anchor 202, full/half widths 44/22, 32/16, 20/10 and four-unit
inter-band gaps remain fixed. Compatible split branches contain no restoration, and an
absent or rejected main paints nothing, preserving its valid extra. MAX100/200/400/800,
Float scaling, ordinal/family placement, endpoints, known-zero tracks, credits, periods,
ambient treatment, complete selected content, eight slots, taps and producer behavior are
unchanged. No sibling accessor, shared count, transaction or paint ACK is introduced. Other
independently delivered mixed counts still require native review.

`check_retained_extra_paint` in `tools/check-watchface-structure.py` evaluates actual
emitted predicates, tracks, arc geometry and scene order, distinguishing backdrop
restoration from foreground paint. `check_backdrop_restore` independently checks the
matching lift geometry/gradient, local mask scope, order before foreground, coverage across
radius 202 including the ROUND seam, and confinement to admitted unsplit N1. Missing and
insufficient restoration must fail the coverage contract. The owner model keeps every
extra field unchanged while updating only the mains, then removes the extra separately.
The former scene order must still expose Other paint; zero/tiny/partial/near-full/full,
compatible splits, both ordinals, legacy envelopes, malformed inputs and main NoData
retain distinct assertions. This analytical declaration model is not native compositing,
clipping or antialiasing evidence.

The [guarded observation extension](../../apps/wear_android/README.md#guarded-normal-datasource-observations)
requires separate Root admission of an actually changed production XML payload with
complete baseline/candidate provenance. Consumed Square `normal`,
`fixture-n1_pair_zero_full` and `delayed` cases remain consumed. Its separately recorded,
payload-bound delayed attempt cannot be enabled by test/APK/signature/probe/instance/config
churn alone. It preserves global latest-attempt and exact recovery fencing, including
partial attempts, and uses the existing newer-data-safe lease and separate later restoration.
Missing provenance blocks observation; this source change supplies no real admission record.

**New-artifact delayed acceptance remains Pending.** After whole execution DONE,
owning CLI exit, owned-process retirement and a fresh separate idle observation, Root
still owns full Source review and all original HOST gates: complete Wear/watch-face/docs
checks, official WFF2 and Push semantic validation, affected tests, source/generated/built/
installed/active joins, the matched retained-extra/extra-cleared delayed witness, justified
finite cases and exact separate later recovery.
Inspect original frames and effective data independently of requests/events, then verify
restored ordinary Face/Glance viewing. Unused fixtures, SDK, obsolete or recovery cases do
not replace unseen delayed evidence. Public acceptance follows native acceptance; item12
and its original compatibility gaps remain open.

## Implementation candidate 2026-10-31 — near-full main paint

On the installed Square cohort, Root and an independent reviewer found the large green
Codex main/inner arc absent in both original requested and bounded frames for the existing
singleton Codex/Spark pair: Codex used **0.1**, Spark used **99.96875**. The legend rounded
to **100/0**. Native VALUE is redacted, MAX is unknown and TITLE is not projected; requests,
events, types and labels acknowledge neither the selected consumer branch nor its exact
fields. This is a newly observed paint failure, not a proved regression from an earlier
product revision or a proved framework/cache fault. Historical originals, reports and
Pending labels remain unchanged; exact-color counts assign no subpixel trace to a provider.

`bandArcs` in `tools/render-watchface.mjs` replaces only its ordered foreground Condition
with three stable named full/tiny/round Groups, each initially transparent and driven by a
mutually exclusive 255-or-zero alpha Transform. At that candidate, main admission, layout
and split selectors remained in place; the later stable-main-geometry candidate below
changes only layout/split selection. The track stays outside the paint gates; `bandPaint`
retains its drawings, live response ColorRamp, proportional endpoints, caps and ambient
treatment. This adopts the existing outer-half paint structure, removing conditional subtree
switching from main/inner paint selection. The intended 99.9% remainder selects the large ordinary partial;
effective native values, the historical selected branch and renderer cause remain unknown.
This is a supported candidate whose native effect still needs acceptance.

`assertLegacyCutoffs` and `assertNearExhaustedArcs` in `tools/render-watchface.mjs`, and
`check_band_paints` in `tools/check-watchface-structure.py`, inspect emitted alpha decisions
without first-true selection masking an overlap. They retain endpoint, exact-full/zero,
ordinary-partial and derived-cutoff assertions across all admitted geometries. The existing
`check_retained_extra_paint` scene model adds the incident producer's projected wire Floats
**199.8000030517578 / 200** for Codex and **0.0625 / 200** for Spark, independent family
ownership and tiny/zero/full outer variants. Suppressed round and overlapping full gate
counterexamples must fail. These are declaration contracts, not native paint evidence.

WFF2, canvas450/centre225, full/half widths44/22,32/16,20/10, contours, gaps, clip envelopes,
MAX100/200/400/800 and Float scaling are unchanged. Keep all complete labels, zero/credit/
budget semantics, family/pool identity, eight slots, services, bindings, taps, central
composition and interactive/ambient/MUTE distinctions. Extras still precede mains;
`n1BackdropRestore` remains confined to admitted unsplit N1, preserving valid split extras
and valid-extra/main-NoData behavior. No shared count, sibling accessor, ACK or diagnostics
is added. That repair left review art and fixture bytes/timestamps unchanged.

**Native repair acceptance remains Pending.** The current incident fixture is consumed;
this candidate supplies no replay eligibility or device admission. A bounded extension of
the existing genuine-production-payload observation route for that unchanged fixture belongs
to the later planned commit, preserving consumed history, complete provenance, payload-bound
single use, global latest fencing, arm-before-write and exact separate later recovery with
newer-write protection. After whole execution DONE, actual owning CLI exit, scoped process
retirement and a fresh separate idle observation, Root still owns complete relevant HOST
checks, official WFF2 and strict Push semantic validation, affected tests, source/generated/
built/installed/active joins and a separately reviewed legitimate native witness. Inspect
every original and effective-data limits, the large green main and independent tiny outer,
exact restoration and later ordinary Face/Glance recovery. Retained-extra, compatibility,
delivery, endpoint/cutoff, shape/mode and public-cohort duties remain open; public acceptance
follows native acceptance. This candidate does not close item12.

## Implementation candidate 2026-10-31 — stable main geometry

The normal phone Watchface UI removed only Codex from Claude, Cursor own/other and Codex,
changing N3 to N2 on the Round watch. The sixteen-frame native burst reached settled N2 with
a whole blue outer band and no visible teal arc; a separate INTERACTIVE frame about 2.5 minutes later retained
the defect. The strip showed 100/64 and its far teal marker. The current producer projection
is Cursor 100%/Other 64.1% remaining with Claude 34%. Native scalar/range/TITLE fields and
selected-branch acknowledgment remain unavailable or redacted. The visible omission is
persistent bounded evidence, not a proved cache, expression-name or occlusion cause; nested
Conditions remain valid WFF Source.

`mainBand` and `ringSlot` in `tools/render-watchface.mjs` replace only nested layout/split
selection with fixed sibling geometry Groups under the existing main admission tree.
Each feasible layout keeps its named paired/ordinary forms, initially at alpha zero with
mutually exclusive response-local range/TITLE alpha Transforms. Credits-only input keeps
its existing strip without activating geometry. `bandArcs` foreground gates and drawings,
period textures and `n1BackdropRestore` remain inside their corresponding forms unchanged.
This extends the existing stable-alpha approach to geometry; it is a repair candidate whose
native effect still needs acceptance.

`check_main_decisions` in `tools/check-watchface-structure.py` evaluates every emitted
geometry gate independently, including closed paired zero spellings, ordinary periods,
feasible positions, endpoints and rejected/credits-only input. `check_count_change_pair`
models the source-projected Cursor100/Other64.1 responses before and after N3→N2. Obsolete
geometry must become inactive; N2 main radii **170–186** and extra **186–202** remain adjacent
16-unit halves. An ordinary full N2 remains the whole 32-unit band. Counterexamples that
activate ordinary geometry over the pair or suppress its exact-full main must fail.
Existing endpoint, retained-extra, admission and normal/diagnostic gates remain intact.
These are declaration checks, not retained-scene simulation or native repair evidence.

The 450-unit canvas, centre 225/225, full/half widths 44/22, 32/16, 20/10, contours, gaps, colors,
identities, complete labels, periods, credits, ambient treatment, eight slots/services/ordinals
and MAX100/200/400/800 remain fixed. Extras still precede mains; unsplit N1 alone restores its
backdrop. Main and extra responses remain independent, including valid-extra/main-NoData.
No common count, atomic delivery, field-cache guarantee, observer, schema, fixture, version
or provider/phone/transport change is introduced. Historical evidence and Pending labels
keep their measured scope; TinyTail/cutoff RED remains the owner's absolute-last item.

**Native repair acceptance remains Pending.** After whole execution DONE, owning CLI exit
where used, all run-owned processes retired and fresh quiescent ownership, Root owns full
affected HOST Wear/watch-face checks, official WFF2 and pinned Push semantic/resource checks,
and the matched current normal N3→N2 before/after witness. Bind source/generated/built/
installed/active bytes, current instance, effective eight choices, mode, viewport and actual
frame inputs. Inspect complete first-transition and separately settled originals for both
halves and legend, then necessary normal recovery. Preserve the current incident until
deliberate Root custody, retain newer publications and restore admitted state through normal
UI without reset, rebinding or scene recreation. Redacted fields stay Unknown. Retain the
passing session 51293's 47-test paired-gate evidence without an unjustified rerun and require
Root's full independent zero-findings pass; remaining item12 duties are not closed here.

## Revision 2026-10-30 — N1 width 44

The owner approved explicit full/half widths **44/22, 32/16, 20/10**. This replaces only
the earlier 68/34 N1 dimensions and its texture fits. Keep the unchanged 450 canvas,
centre 225/225 and outer anchor 202. `LAYOUTS` and `bandGeometry` in
`tools/render-watchface.mjs` own these dimensions; the analytical and rendering routes in
`tools/render-watch-ring-designs.mjs` use the same explicit widths, preserving the historical
N3 review-art model.

| Layout | Full / half | Full centrelines, outside first | Outer / inner pair centrelines | Inner end / aperture bound |
| --- | --- | --- | --- | --- |
| N1, MAX200 | 44 / 22 | 180 | 191 / 169 | 158 / 157.8 |
| N2, MAX400 | 32 / 16 | 186, 150 | 194 / 178; 158 / 142 | 134 / 133.8 |
| N3, MAX800 | 20 / 10 | 192, 168, 144 | 197 / 187; 173 / 163; 149 / 139 | 134 / 133.8 |

N1 continuously spans 202..158. Its pair halves meet at 180 with no gap. N2/N3 retain
four-unit inter-band gaps; MAX100 retains fixed legacy positions and is never count proof.
`assertNearExhaustedArcs` keeps per-layout belt ends and the existing 0.2-unit aperture
allowance, strict containment within the shared 414/68 round extra-slot clip and the
0.01-unit ideal full-closure tolerance. These are analytical bounds, not native AA readings.

`BAND_LAYOUTS`, `check_band_envelopes`, `check_band_paints`, `check_paint_endpoints` and
`check_extra_decisions` in `tools/check-watchface-structure.py` independently inspect the
actual emitted full/inner/extra arcs: N1 diameters 360/338/382, strokes 44/22/22, radial
edges, gapless halves, paint ownership and clip envelopes. Emitted predicates and transforms
are evaluated at zero, proportional positive-tiny values, neighboring wire Floats on both
sides of each cutoff, ordinary partials, near-full and exact-full. Endpoints and visible
sweep are checked, including the single 0..359.9 ROUND full path. Legacy/N3 retain their
published six-decimal cutoffs and historical clamp at a rounded-down boundary; that
rounding allowance does not apply to the new widths. Both extra ordinals, impossible
positions, malformed/non-finite inputs and exact TITLE admission remain covered.

**Measured raster fit, 2026-10-30; independent visual/native acceptance Pending.** N1 type
was rebaked at actual radius 180, not resized from an older band. Keep Noto Sans Bold,
nominal cap 15.756, derived font size 22.1, alpha 115/63, four diagonal 10° breaks and
the existing ambient treatment. Pairs have no period texture. Isolated-token angular ink
envelopes at radius 180 measured D **4.608128°**, 7D **8.824800°**, M **5.990607°**.
Enumerating every positive count through `floor(80° / span)` gave upper bounds **17/9/13**.
The largest counts meeting the conservative raster criteria at all three scales were
**D 11 / 7D 7 / M 9 per sweep**; both `ADAPTIVE_REPEATS` tables carry these counts.

Measurement used the existing named-SVG ImageMagick route at density 96, with each 404px
texture in its actual (23,23) box on a transparent 450px canvas. Pillow Lanczos downscales
model 360/384 viewports; this is a documented resampling model, not native renderer proof.
All nonzero-alpha pixel corners bound each token's angular/radial ink, including faint
filter fringes. Measure the PNG envelope before mode alpha 115/63; this conservatively
bounds both modes' ink support, without measuring their contrast. Require positive
separation, all four breaks at least 10°, radial
clearance and minimum ink-to-ink arc spacing at radius 180 no tighter than the unchanged
outer-N3 texture measured by the same method at radius 192 (D 15 / 7D 9 / M 12).

| Period | Minimum gap px, 450 / 360 / 384 | Minimum diagonal break degrees, 450 / 360 / 384 | Minimum radial clearance px, 450 / 360 / 384 |
| --- | --- | --- | --- |
| D, 11 | 7.321 / 1.219 / 1.586 | 12.224 / 10.749 / 10.868 | 12.749 / 7.795 / 8.627 |
| 7D, 7 | 6.837 / 1.365 / 1.744 | 12.146 / 10.789 / 10.989 | 12.377 / 7.597 / 8.245 |
| M, 9 | 7.905 / 1.809 / 2.498 | 12.578 / 10.963 / 11.367 | 12.553 / 8.026 / 8.627 |

The outer-N3 gap references at 450/360/384 were D **1.991/-1.313/-1.279px**,
7D **0.828/-1.232/-1.254px**, M **2.308/-1.192/-1.218px**. Negative values mean these
conservative corner envelopes overlap after downsampling; they are not native legibility
claims. N1 must additionally retain a strictly positive gap. Every larger bounded count
was rejected: D 12..17, 7D 8..9 and M 10..13 fail separation and/or diagonal-break clearance
at a smaller scale. At 450 the selected radial ink envelopes were D **170.883..189.251**,
7D **170.848..189.623**, M **170.836..189.447**; the nominal cap stays fixed even though
these conservative raster bounds include antialiasing. The chosen counts establish measured
spacing and fit under this model, not readability PASS or native cap-height acceptance.

At the 2026-10-30 refit, canonical XML and the three N1 textures were regenerated before the
affected N1 boards, previews and WFF mirrors. N2/N3/legacy textures, unaffected art and Primary
portrait bytes remained fixed for that refit; current active art follows the
[approved translation](#revision-2026-11-01--approved-active-clock-translation).
Drift checks cover XML/SVG, not raster fit. Inspect D/7D/M active/ambient
originals independently at viewport scale; central clearance, clipping, first and separately
settled native geometry and retained-engine transitions remain **Pending**. Preserve the
completed Alpha selection repair, all eight slots, 52-unit cells, logo/clock/wells/labels/
fades, zero/tiny/full and ambient/MUTE semantics.

The earlier 68/34 dimensions and receipts below remain historical; old-geometry evidence
does not accept the new 44/22 bytes or establish a renderer cause. Item 12 integration,
compatibility, forward-only delivery, phone retention/sync and coherent public-capture
obligations in the adaptive revision remain open. This change allocates no version and
does not authorize Push delivery. Required independent review, FINALIZE and later HOST
acceptance retain their existing ownership; no new owner approval gate is introduced.

## Revision 2026-10-28 — adaptive bands from resolved count

Historical 68/34 geometry and texture-fit receipt: the
[2026-10-30 revision](#revision-2026-10-30--n1-width-44) supersedes only N1 width and fit.
The admission, selection and open integration obligations here remain operative.

This revision supersedes fixed width for accepted adaptive responses. Count validated,
resolved band entries once each: an ordinary plan, an independent budget, a supported pair
or a known zero occupies one band. Preserve tightest-first payload order, `RingSurfaceOrder`,
pool identities and both split ordinals. Missing, negative or non-finite values never become
zero or a count. N0 draws no usage band and may retain the legacy credits-only row. N>3 or
more than two splits is invalid. Availability changes can legitimately change the count;
the payload does not distinguish every temporary omission from deselection.

On the unchanged 450 canvas, width is `(68 - 4 * (N - 1)) / N`. Outside index j has
outer edge `202 - j * (width + 4)`, full centreline `edge - width/2`, and outer/inner pair
centrelines `edge - width/4` / `edge - 3*width/4`. There is no gap inside a pair.

| Resolved bands | Full / half width | Full centrelines, outside first | Outer / inner pair centrelines |
| --- | --- | --- | --- |
| 1 | 68 / 34 | 168 | 185 / 151 |
| 2 | 32 / 16 | 186, 150 | 194 / 178; 158 / 142 |
| 3 | 20 / 10 | 192, 168, 144 | 197 / 187; 173 / 163; 149 / 139 |

The nominal belt remains 202..134, with gap 4 and actual aperture at least 133.8 required.
`bandGeometry`, `assertNearExhaustedArcs` and `assertFullRing` in `tools/render-watchface.mjs`
cover every actual radius/stroke: cap compensation, proportional tiny remainders on both
sides of the two-cap cutoff, zero tracks, near-full and exact-full closure. The full path
retains one 0..359.9 ROUND arc without either cap inset. These are declaration/analytical
checks, not measurements of actual aperture, clipping or native antialiasing.

The deliberate raw-range interface revision keeps generic `TYPE_UNDEFINED`. The producer
derives the semantic Float percentage, TEXT, description and zero tokens before multiplying
VALUE and MAX by a binary factor. Scaled units never enter a percentage formatter or clamp.

| Exact MIN / MAX | Meaning | Geometry |
| --- | --- | --- |
| 0 / 100 | Legacy percentage, any actual count | Fixed 20 / half 10 at legacy positions; never N3 evidence |
| 0 / 200 | Factor 2, N1 | Full 68 / half 34 |
| 0 / 400 | Factor 4, N2 | Full 32 / half 16 |
| 0 / 800 | Factor 8, N3 | Full 20 / half 10 |

Only finite admitted envelopes and finite bounded VALUE are accepted. Adaptive main j must
be less than N. Extras require exact TITLE `0`/`1`/`2` and feasible ordinal: ordinal 1 requires
j<N-1; the legacy envelope retains static positions without asserting an actual count.
Unsupported TITLE/range/value/position paints nothing: no arc, track, texture, well or label.
Invalid producer selections and obsolete services return actual `NoData`. Credits and
uncounted previews retain MAX100; credits never establish a usage band. Main TITLE keeps
the existing empty/zero, period and closed split/zero vocabulary; no count suffix is added.

Each main `isValid` Compare in slots 101/102/105 holds one stable named full-canvas Group
(`ring1_main` / `ring2_main` / `ring3_main`), containing fixed paired/ordinary layout Groups
then its strip under the stable-main-geometry candidate above. `ringSlot` in
`tools/render-watchface.mjs` preserves their admission, order,
geometry, clipping and ambient behavior. The awaited Python-standard-library regression
in `tools/check-watchface-structure.py` parses actual XML before emission in generation and
`--check`, enforcing one direct element tree per Compare/Default and main geometry/strip
containment. The earlier wrapper repair rejected the baseline's three malformed branches;
that structural evidence does not establish corrected native rendering.

Each response derives count, selection, pools, semantic fields and scaling from one accepted
summary load. A valid delivered extra survives an absent delivered main without inventing
main paint or a row. A resolved singleton with split=null remains an ordinary full band
with `NoData` extra. Decode each response independently: there is no common-N selector,
generation tag, atomic transaction, renderer ACK or grace-period promise. Old/new counts
can overlap during independent delivery; harmful ambiguity or persistent wrong output is
a finding, not accepted behavior.

N3 geometry, nine existing texture pixels and all N3 review art remain fixed. New textures
are baked at actual N1/N2 radii, not resized N3 images. Keep nominal cap 15.756, Noto Sans
Bold, alpha 115/63, four diagonal breaks and existing ambient treatment. Repeats per sweep
outside first are N1 D 13 / 7D 8 / M 10 and N2 D 15/11, 7D 9/6, M 12/9. Eighteen texture PNGs now
cover all six full-band geometries. New-radius refits require independent design review;
N3 is not retuned. `adaptiveVariants` in `tools/render-watch-ring-designs.mjs` adds one/two
band pair boards and all new-radius period fits in active/ambient; the existing N3 art's
measured model is preserved, including its historical thinner ambient strokes.

Keep all eight scene slots: lower 101/102/105/106/109, all six updater services including
Status, and upper 201/202/203 with existing types, DAY_OF_WEEK/EMPTY/EMPTY defaults and wearer
choices. Canonical IDs do not establish runtime IDs. That adaptive revision retained the
52-unit cells, logo, clock/type/reference bottoms, 132×26 wells, labels and fades; the later
[active translation](#revision-2026-11-01--approved-active-clock-translation) supersedes only active clock placement.

Old app/new face stays fixed legacy width for any count. New app/old face preserves
VALUE/MAX ratios, semantic strings and the existing pair contract, but third-party raw
readers and OEM speech/renderers may interpret generic scaled units differently; universal
compatibility is unsupported. The older slot 109 marker incompatibility in
[Split band](#split-band-revised-2026-09-16) remains: stable service names do not repair it.

**Integration acceptance: known Pending.** Generator output and review art are authored,
not native acceptance. Current packaging is phone 0.1.0+3, Wear 4, legacy 2, Push default 5,
all versionNames 0.1.0 with identities/signers retained. Only the guarded default advances
3→5; historical candidate 4 flags/instrumentation and the real 3→4 journal remain intact.
This is not a release cut. The
[current qualification](RELEASE_CHECKLIST.md#guarded-integration-allocation-2026-10-30)
retains the sole Native FINALIZE inventory, all nine deferred HOST duties and all six cells:
Push old-old/new-old/new-new and Legacy old-old/old-new/new-new. Unavailable historical cells
require explicit Root-reviewed forward-only reconciliation; retained 4/final 5 cannot recreate
them. HOST still owns full builds/official validation/API wire tests, both delivery channels
and retained lower bindings/upper choices. The original Push path
required old-old, Wear 2→4 retaining Push 1, then explicit **Update watch face** Push 1→2.
Installing Wear 4 was instead followed by Push 2 before an explicit update; the trigger
remains unknown. New-Wear4/old-Push1 and explicit 1→2 remain unobserved gaps. The earlier
correction allocated 2→3 without an observed explicit manager update. Preserve those gaps;
the current guarded path is a later normal UI 4→5 Update, not replay of the old harness.
Freshly prove installed Push 4/hash/signer, owned manager slot, eight choices and quiet-writer
custody while Legacy stays active; verify returned same-slot identity and separate settled
retention. Unexpected advancement stops that witness: no code 6, replay, downgrade, reset or
invented button success. Later retained-Push selection/rendering is separate HOST work.
Bundled installation proves neither explicit update nor activation. The
[incident qualification](RELEASE_CHECKLIST.md#adaptive-integration-qualification-2026-10-28)
preserves the original N2 missing-main-paint evidence, its unknown exact native cause and
forward-only compatibility obligations. Legacy still requires old-old, face 1→2 retaining
Wear 2, then Wear 2→4. Verify actual installed codes/signers first; conflicts need reviewed
correction, never downgrade/reinstall/reset. Later verify phone 1→3 on its existing
emulator with retained data/settings/credentials. Physical phone work is forbidden and
physical 466 remains deferred.

Preserve the actual installed Push 1 receipt separately from the calibration APK used for
preadaptive N3 continuity. They have different XML bytes. Ratio-consumer eligibility is
not XML/pixel/runtime equivalence and supplies no new slot 109 compatibility promise.

Target provisioning/device tests/live phone update/sync/UI Update stay held for the separately
admitted typed-API/guard scope against preserved Round Wear 4/asset 3/Push 4. Item12 remains
open and both extras queued. These valid fixtures do not cover malformed/delayed/missing
delivery, absent-summary or preview blockers. Newly evidenced essential renderer scope issues
require a concrete reviewed finding; no historical no-renderer-change premise is adopted.

After whole execution DONE, owned-process retirement, owning CLI exit if used and fresh
separate public/OS idle, HOST must bind
source/canonical/built/installed/active identities, interactive and true-ambient geometry,
caps/aperture/clipping/textures/N3 continuity on the smallest round and nonround targets,
and original transient plus settled frames for N3↔N1/N2, pair appearance/removal,
same-count reorder and delayed/interrupted recovery through normal updates. Unseen cases
remain Pending; final frames, sleeps or retries do not substitute. Delegated documentation/
design ownership in this same integration must refresh healthy public captures, their index
and browser uses only after native acceptance, then restore guarded data/bindings/settings/
time/font/ambient/pairing and obtain Root's whole zero-findings review. Native completion
alone does not close this acceptance.

## Revision 2026-10-25 — larger face legend and cells

This initial iteration applies the 2026-10-24 design in the existing **450×450** language.
Its 104×22 legend and 48-unit cells are superseded by the combined revision below.
Dated measurements cover only their own builds.

| Element | Initial target, in design units |
| --- | --- |
| Equal legend wells | **104×22**, x=173, corner radius 6; tops **271 / 294 / 317**, bottom 339 |
| Shorter stacks | Two rows at 294/317; one ring or credits-only at 317; tightest row first |
| Legend label | Centred **92-unit** region at inset 6; one size for the complete mixed-run label |
| Label font | **15** through 10 characters, **14** at 11, **12** at 12 or more |
| Upper cells 201/202/203 | **48×48** at **(149,112) / (201,98) / (253,112)** |
| Cell text | Centred **42×22** box at **(3,13)**; ordinary font **16** |
| Third-party cell text | Font **14** at 5–6 characters, **12** at 7 or more |
| Weather font | UV≥10: **14**; temperature<0 or ≥100: **14**, except ≤−100: **12** |
| Monochrome icons | **24×24**, centred at integer inset **12**; same tint and source |
| Occupied border | Path diameter **46.5**, stroke **1.5**, radii **22.5–24.0** |

All font branches use literal sizes and WFF2 `Condition` expressions. They do not use
autosizing or font minimums from later format versions. Character count is a conservative
rule for the bounded numeric/compact grammar, not a glyph-width measurement. Each label's
mixed runs share the chosen size and one centre/baseline; only true exhausted percentage
tokens change colour. Full numbers, currency, denominator, credits and separators remain.
The existing single-line ellipsis remains for out-of-envelope strings. For example
`$92233.7T/92233.7T` is wider than 92 units even at host font 10: this revision does not claim
universal money/credits fit or shrink such readings indefinitely. The phone carries the
complete reading. Arbitrary third-party strings and unusually verbose weather formatting
have the same explicit limitation; values and device-provided units are never rewritten.

**Initial border candidate, superseded by the clarification below.** Its axis was
`u=(cellCentre−faceCentre)/distance`. From `C−23.25u` to `C+23.25u`,
every occupied border keeps its outward alphas **170 / 145 / 90 / 35 / 10** at positions
**0.5 / 0.625 / 0.75 / 0.875 / 1**. Only the left/right cells mirror these onto the inward
half: positions **0 / 0.125 / 0.25 / 0.375 / 0.5** carry **10 / 35 / 90 / 145 / 170**.
The raised central cell keeps **170 throughout its inward half**, with no inward fade.
RGB, peak alpha and the ambient **140/255** multiplier remain unchanged. Only the occupied
border fades; wells, readings and icons do not. Empty cells keep their graded recess without
an occupied border. Legend rows retain whole-row alpha **255 active / 90 ambient**.

Calculated clearance to the unchanged **133.8-unit aperture** is approximately **8.50** at
the worst legend corner (173,339), **6.72** at the lateral cell edges and **6.80** at the
central edge. Adjacent wells retain **5.85** units; lateral wells end exactly at the clock
box's y=160 boundary. The watermark's historically recorded ink ends at y=268, three units
above the first well. These are design calculations and older ink observations, not new
native measurements. Clock, watermark, ring count/radii/widths/joins/caps/textures/melt,
TITLE vocabulary, payload/source/order/zero semantics, defaults, units, five lower services,
three upper slots, eight-slot budget, navigation and both packaging paths are unchanged.

**Exports generated; acceptance pending.** On 2026-10-25, writable Runner polishing ran
both ordinary owning generators successfully after replacing synchronous subprocess calls
with awaited asynchronous execution of the same tools. It produced canonical XML, the shipped
picker PNG, all 26 face boards/previews and 23 WFF mirrors from their existing maps. The full
runtime path also rasterized all nine texture PNGs with unchanged inputs and identical bytes.
The earlier failed attempts remain historical failures, not generation evidence for this set.
Official WFF2 validation, full native builds and design/docs gates remain separate HOST
acceptance conditions; Native workspace checks belong to the Runner FINALIZE gate.

Inspect every board/preview, then actual native ink in active/ambient on round, small
nonround and physical **466×466** targets: one/two/three bands, ordinary and paired/mixed/all
known zero, tiny positive, no bands/credits-only; empty/default-weather/user-overridden
cells, day, C/F/unsupported unit, negative/three-digit temperatures, UV10+, unavailable
weather, SHORT_TEXT, RANGED_VALUE-as-text and monochrome icons. The complete-label corpus
includes `100% · 64%`, `82% · 59.5K`, `100% · 100%`, `100% · 999.9T`, `$999.99/999`,
`$999.99/999.9T`, `$999.9T/999.9T`, signed day/week/month budgets and a separately recorded
extreme overflow. Check markers, ordering, mixed-run centring/baseline, actual ink/clearance
and the separate outward and added lateral-bottom treatments below. A host-font fit or board
is not physical readability proof.
After fit approval, refresh public face imagery and the screenshot index; Overview/README
cohorts need one healthy shared state and actual themes. Public captures and later integration
remain pending. Seam, temperature-source, adaptive-band and navigation fixes stay excluded.

## Revision 2026-10-25 — bottom-only cell borders and artifact review

**Historical rejected interpretation, superseded by the operative revision below.** Root
misread the requested added bottom treatment as replacing the existing outward fade.
That candidate made the left/right borders fade only toward 6 o'clock and the central
border uniform everywhere, keeping the then-current 48-unit geometry and typography.

That candidate used the vertical axis from `C−(0,23.25)` to `C+(0,23.25)` on each lateral
border. Its top half retained alpha **170**; its bottom ramp was **170 / 145 / 90 / 35 / 10**
at positions **0.5 / 0.625 / 0.75 / 0.875 / 1**. The central occupied border was uniformly
**170**. RGB and the ambient **140/255** multiplier were preserved, but the existing outward
fade was removed against the Owner's intent. Wells, text, icons and usage bands were unchanged.

**Historical c96 execution and workmanship record, 2026-10-25.** The owning Runner run
finished DONE, exited with code 0 and was separately retired. The new 384×384 round native
interactive frame and Sun-cell zoom show a continuous rim without the two reported flecks,
and the selected Cursor halves remain together on their correct band. Independent forward
review found no issue in that interactive case, but did not establish the Owner's lighting
intent. A native ambient PNG was also obtained with
power observed as Dozing, then the watch was awakened; that frame was visually inspected.
`just check-wear`, `just check-watchface` (including official WFF2 validation),
`just check-designs` and `just validate-fixtures` passed after the correction.

Preserve the original fleck incident without asserting an unproved cause. These frames do
not complete the variant/fit matrix above. Both new release packages are installed on the
physical watch with their existing signers, but physical native verification remains Pending.
The seven-frame public candidate still requires a fresh coherent capture session; the
existing face image is not approved by its earlier populated-cell review. These results
do not accept the outward-preserving refinement below.

## Revision 2026-10-25 — preserved outward fade and 50-unit cells

**Historical 50-unit geometry; lighting contract retained.** The first
50-unit proposal held the clock, watermark and legend fixed. The Owner then authorized
their combined refinement; those earlier fixed-layout restrictions no longer apply.

The Owner clarified that the original darkening **toward the large usage arcs must remain**
on all three occupied rims. The requested change adds a strictly vertical **6 o'clock**
fade only on the two lateral rims. **No added bottom fade on the centre** does not mean
removing its existing outward fade. This supersedes the mistaken bottom-only candidate.

That iteration grew downward/inward while keeping its top edges and lateral outer edges:

| Element | Historical target, in 450×450 design units |
| --- | --- |
| Upper cells 201/202/203 | **50×50** at **(149,112) / (200,98) / (251,112)** |
| Cell centres | **(174,137) / (225,123) / (276,137)** |
| Complete text box | **44×24**, centred at **(3,13)**; ordinary font **17** |
| Existing finite fallbacks | **14** for 5–6 characters/long weather; **12** for 7+ or extreme weather; thresholds unchanged |
| Monochrome icon | Unchanged **24×24**, centred at inset **13** |
| Occupied border | Path **48.5**, stroke **1.5**, radii **23.5–25.0** |

For each occupied rim, derive `u=(C−F)/distance`, with actual cell centre C and face centre
F=(225,225). Preserve the original outward gradient from `C−24.25u` to `C+24.25u`: alpha
**170** through the inward half, then **170 / 145 / 90 / 35 / 10** at normalized positions
**0.5 / 0.625 / 0.75 / 0.875 / 1**. Its arc-facing direction remains radial, not vertical.

Only lateral rims add a vertical bottom mask from `C−(0,24.25)` to `C+(0,24.25)`.
Its multiplier is **1 throughout the upper half**, then **1 / 145÷170 / 90÷170 / 35÷170 /
10÷170** at the same positions. The visual contract is the normalized product:
**result alpha = outward alpha × bottom multiplier**. The centre uses outward alpha alone.
This preserves the original upper lighting exactly and never brightens either faded region.
Keep RGB and apply the **140/255 ambient multiplier once** to the composed rim.

Use a small isolated group containing ONLY each affected border's source and alpha mask;
do not mask its well, text, icon, sibling cell or scene. WFF supports parent-group-scoped
`renderMode="MASK"` from version 1; general `blendMode` starts at version 3 and is excluded
from this WFF2 target. A complication can contain a Group. These constraints permit the
two small border masks without new assets, dependencies or complication slots; the actual
generated form still requires official WFF2 validation and native rendering checks.
[Official mask guidance](https://developer.android.com/training/wearables/wff/effects),
[Complication reference](https://developer.android.com/reference/wear-os/wff/complication/complication).

At these anchors the adjacent well gap is **2.8867**; the aperture gaps are **7.0896** at
the sides and **6.8000** centrally. Tops remain y=112/98/112 and outside edges x=149/301.
The lowest wells end at y=162. In the interim y160 clock layout, they overlapped two units
of the clock's empty text-box bounds, not its measured ink. The then-measured active clock
ink began at **179.30** on the 384 AVD and **179.61** on the 466 physical frame, leaving
interim projected vertical gaps **17.30 / 17.61**. The combined y152 shift below supersedes
these clock inputs; they do not establish new native time-string or scale acceptance.
At those same anchors, 52-unit cells would overlap by about **0.077**; the current upward
revision uses different centres and retains a positive gap. The current path half-diameter
is **25.25**, replacing **24.25** in both gradient axes above without changing their stops.

Host Noto Sans Bold corpus measurements for the proposed sizes include `Sun`32×13,
`Wed`37×14, `18°C`38×14 and `48°F`36×14 at 17; `-10°C`36×11, `100°F`38×11 and `UV 11`39×10
at 14; and `-100°C`38×10 at 12. They fit 44×24 as host design inputs, not Android ink proof.
The interim proposal retained the 104×22 legend and clock/watermark positions; their
operative replacements follow below. Bands, payload semantics, defaults, units, RGB,
navigation and normalized empty-cell treatments remain unchanged.

The combined record below retains its dated native acceptance; the 2026-10-27 revision owns
the current composition. Keep the full corpus/variant matrix and complete contour checks,
including the original Sun fleck case;
restoring a radial stroke alone is not proof against recurrence. No causal diagnosis is
asserted. All three outward/upper treatments and the separate lower fades require actual
native comparison, not just a mathematical or generated-board result.

## Revision 2026-10-25 — combined face readability

**Historical layout and evidence.** The 2026-10-27 revision below supersedes this clock,
watermark and legend geometry. These measurements and native results cover only their
original artifacts; they do not accept the new composition.

The Owner authorized lifting the clock and watermark to give the legend more readable
space. Retain the 50-unit cells, font 17/14/12 and outward-plus-lateral-bottom product-mask
contract above. This supersedes only the interim clock/watermark/legend restrictions.

| Element | Historical combined target, in 450×450 design units |
| --- | --- |
| Active clock | TimeText **y=152**, height 90; unchanged 70 Bold, format and alignment |
| Ambient clock | TimeText **y=152**, height 90; unchanged 81 Thin and mode switch |
| Watermark centre | **(225,247)**; both images lifted 13, with source PNG unchanged |
| Active watermark | **66×66 at (192,214)**, alpha 95 |
| Ambient watermark | **54×54 at (198,220)**, alpha 70 |
| Legend wells | **120×26 at x=165**, radius 6; rows **259 / 286 / 313**, pitch 27, bottom 339 |
| Whole mixed-run label | **108×26 at inset 6**; **18** at ≤10 characters, **16** at 11, **14** at 12+ |
| Family/paired markers | Left accent: unchanged declared 3×14 Arc/stroke 3, visible ink about 4.5×17 as its SVG rectangle represents; far marker: unchanged 3×14. Both recentered in the 26-unit row; colors/semantics preserved |

Both clock variants move upward 8 without resizing their type. The legend grows into the
freed region while keeping its lowest bottom 339 and contiguous bottom anchoring: two rows
use 286/313; a single ring or credits-only uses 313. Preserve complete mixed-run centring,
true-zero coloring, values and existing ellipsis policy. Legend alpha remains 255 active/
90 ambient; existing colors, slot budget, defaults, units and usage arcs do not change.

The conservative rectangle corner (165,339) clears the unchanged 133.8 aperture by
**4.9745 units**. Host Noto Sans Bold corpus measurements at 18/16/14 reach at most
**102×13**, within 108×26; arbitrary overflow is not claimed to fit. A 112-wide alternative
would provide only 100 text units and miss that bounded long-budget corpus.

The actual 192×192 watermark PNG has nonzero-alpha bounds (4,46)–(186,120), right/bottom
exclusive. At the new positions its mapped active ink spans **y=229.8125–255.25** and
ambient ink **232.9375–253.75**, leaving **3.75 / 5.25** units before the first well.
These bounds use actual source alpha, not the image's padded square; native sampling still
requires verification. Opacity, size, bottom dissolve and tap action are unchanged.

Clock-only native ROIs at neutral minRGB 30, excluding bands and watermark, give projected
clock-to-mark gaps after the lifts of **6.953** on 384 active, **6.563** on 384 ambient and
**6.053** on 466 active. Projected nearest 50-rim/clock-ink gaps, including pixel-footprint
margin, are **8.603 / 8.525 / 10.320** respectively. These are existing glyphs translated
into the candidate geometry, not a new-render pass or proof for every time string/scale.
The broader earlier ambient ROI included band pixels and is not clock evidence.

**Bounded acceptance, 2026-10-25.** The actual combined-layout and shared-Group-name repair
runs completed and were separately retired. That layout's legacy WFF2 and strict Push validation
and builds passed through `just check-watchface` and `just check-wear`. Canonical XML SHA-256
is `47e1149d819a91e0e6b4b8d9b5bde864dd03006578ddd55c2efb77a67f582a86`.
It is bound to the actual legacy resource package `app.wardpulse.watchface`, Round instance
`wfId-15` and physical instance `wfId-21`. Round 384 original frames passed independent
review with actual renderer `AMBIENT`, visibility and Dozing confirmed, followed by
`INTERACTIVE`/Awake after wake. Physical 466 active Face and Glance were verified with secure unlock
and actual AC power/FULL 100%. Physical diagnostic data is separate from the healthy public
cohort recaptured at 13:36:53–13:36:58 UTC; see the [screenshot index](../assets/README.md#shared-state-capture-refresh-2026-10-25).
Independent review of the API 34 ten-fixture, twenty-frame set covered mapping, legend fit,
zero/one/two/three bands, paired zero values, long credits and budgets, using the clean
settled case-06 supplement. Cases 02–10 retain actual `AMBIENT` mode evidence. Case 01's
original thin-clock frame retains only a mode boolean; its actual-mode supplement held
before any fixture write because peer isolation was unconfirmed. Data and radios were restored.
Square 360 was observed only in `MUTE` with NoData upper cells; populated defaults and true
`AMBIENT` remain unproved, with original DND and stored summary restored. These bounded
cases do not establish every variant or physical AOD. Public browser placement passed the
screenshot index's recorded review. Earlier c96 checks remain historical.

**Selected-zero revision 2026-10-13 — exhaustion stays visible.** The owner's screenshots
`Screenshot_20261013_113638.png` and `Screenshot_20261013_113830.png` showed the phone's
Claude **5-hour session at 0% left** and **Weekly plan at 23% left**, while the face's Claude
strip read **23%** and Glance named **`Claude · Weekly`**. The former non-exhausted preference
hid the exhausted window. The owner explicitly superseded that rule: select the tightest
known window including zero, keep its empty grey track and `0%` legend on both watch surfaces.
The revision also keeps a configured pair when one or both known pools reach zero. These
screenshots establish the reported discrepancy; the revised runtime was subsequently
checked with injected watch data and a genuine phone-to-watch refresh, as recorded below.
Equal known Claude percentages keep the existing `5h` → `Weekly` → `Opus weekly` →
`Sonnet weekly` priority; an unknown window cannot displace a known zero.

**Injected-device verification 2026-10-13.** On `wardpulse_wear_round_api36_1`,
`emulator-5554`, **384×384**, the captured Claude data (`5h used=100`, `Weekly used=77`)
selected **`Claude · 5h` / `0%`** on Glance and an empty inner grey track with red `0%` on WFF;
the inner-band region contained no orange arc pixels. Cursor inner-zero, outer-zero and
both-zero cases retained tracks, family markers and only the actual zero percentage tokens
red. Two pairs kept both split ordinals and family identities. Three selected exhausted
bands retained **four pool tracks**, three legend rows and their ambient dimmed treatment.
An exhausted budget retained its `7D` texture and white `$100.00/100`; Glance's existing zero
percentage token was red. At `used=99.96`, WFF showed ordinary white `0%` with no red ink;
this does not establish visibility of a subpixel positive arc. The installed XML matched
the source byte for byte and all **10** canonical Wear device tests passed. The captured
Claude zero case was rechecked after installing the final Wear APK. These broader variant
checks used injected watch data; they do not establish notround or hardware zero behaviour.

**Live phone-to-watch verification 2026-10-13.** An intermediate Android x64 phone APK
built from the frozen zero-policy runtime refreshed the real Dashboard at **12:38:04**:
Claude **5h 0% / Weekly 23%** and Codex **94%**. The Wear store changed from the earlier
`12:34:44` summary's `Weekly used=77` to schema **9**,
`generatedAt=2026-10-13T10:38:04.000Z`, Claude **`label=5h`, `usedPercent=100`**.
The phone logged `Watch summary queued` at `12:38:05.235`; Wear logged receipt at
`12:38:01.879`. The device clocks differ by approximately 3.36 seconds, so those wall-clock
times do not establish transit latency. `live-zero-face.png` and `live-zero-glance.png`
showed the matching grey Claude track / red `0%` and Codex `94%`, with no injected
preferences between the live sync and the captures. This passes live zero-policy acceptance
on the canonical round AVD. Final persistent-cache APK and cold-worker verification remain
separate and pending; this pass does not establish those behaviours.

**Revision 2026-09-16 — Codex/Spark pair:** Codex plan windows collapse per limit,
then the main limit and Spark may share one band. The main limit is inside/left;
Spark is outside/right in `#186020`. Geometry and typography are unchanged. Both
pairs and far markers, Glance clipping and visual fit were initially **deferred until live-data
verification**; that revision recorded no new device measurements. Injected-load checks on
**2026-10-01** verified Glance paired-row fit and clipping on round and notround screens
(`WEAR_GLANCE_DESIGN.md`), and Phase 18 acceptance on **2026-10-04** covered fixed half order,
lone-pool recovery and the one-row pair (`DEVELOPMENT_PLAN.md`). The far marker's remaining
equivalence check was completed on **2026-10-12** — see *Marker equivalence confirmed* under
Split band. These checks do not establish a live Codex/Spark payload; that live-data condition
remains unverified.

## Revision 2026-11-01 — approved active-clock translation

**Active contract retained; historical ambient profile superseded 2026-11-03** by the
[ambient-clock alignment](#revision-2026-11-03--ambient-clock-alignment). Ambient statements
and measurements in this dated revision describe its original bytes.

The Owner-approved **450×450, 10:08 active portrait** translates the whole active clock
**10.0 design units upward**. Runtime keeps real device-synchronized time; 10:08 is review
data. Preserve **86 Bold**, `height=90`, complete `hh:mm`, horizontal alignment, natural
glyph/colon spacing and hour-format behavior. No other element moves or changes appearance.

| Clock | 2026-11-01 runtime `TimeText` | Review SVG baseline |
| --- | --- | --- |
| Active | **x=0, y=166, width=450, height=90**, **86 Bold**, `CENTER` | **240.78125**, rendered **240.8** |
| Ambient, unchanged | **x=0, y=175, width=450, height=90**, **96 Thin**, `CENTER` | **254.296875**, rendered **254.3** |

The active SVG baseline moves from **250.78125** (rounded **250.8**) to **240.78125**
(rounded **240.8**). These are host text coordinates, not measured native glyph centres or
ink bounds. This translation supersedes the old active 08:08 fixed-bottom/equal-gap target;
the dated measurements below remain history for their original bytes. Other strings and row
counts retain natural variation, with no per-time or per-count offsets. Ambient placement,
mode switching and alpha remain unchanged; the active approval supplies no ambient rise.

Retain all logo, cell, legend, band, data and delivery contracts recorded below, including
original logo pixels/alpha, outward rims, lateral-only lower treatment, caps and paint gates.
Generate canonical WFF before ordinary face art; active boards, mirrors, PNGs and the shipped
logo-composited portrait share this translation. Ambient content remains unchanged.

**New-runtime native/public acceptance: Pending.** The approved host portrait and generator
drift do not establish native agreement. Matched native 10:08 active, existing wide/narrow
clock cases and actual-AMBIENT regression on supported Round/Square targets remain unobserved
for this revision. Existing public captures retain their dated provenance; any image presented
as this runtime requires a fresh native capture and owning index review.

## Revision 2026-10-27 — upward digits and fixed reference bottoms

**Historical clock placements, superseded 2026-11-01 / 2026-11-03.** This revision records its
original target and native evidence. Non-clock contracts remain unchanged; active follows the
[approved translation](#revision-2026-11-01--approved-active-clock-translation), and ambient follows the
[ambient-clock alignment](#revision-2026-11-03--ambient-clock-alignment).

The Owner-approved composition keeps the **450×450** canvas and centre **(225,225)**.
The reading order is **cells → logo → clock → legend**. Enlarge whole digits upward,
retaining the measured **08:08** visible bottoms. Balance the logo→time and time→legend
visible gaps in the **reference with three full rows only**. Keep device-defined whole `hh:mm`,
hour format, colon and natural glyph advances; no per-time offsets, split or stretched
digits, font replacement, central lower fade, gloss, palette or brightness changes.

| Element | 2026-10-27 target, in 450×450 design units |
| --- | --- |
| Active clock | **86 Bold**; integer `TimeText` **x=0, y=176, width=450, height=90**, `CENTER` |
| Ambient clock | **96 Thin**; integer `TimeText` **x=0, y=175, width=450, height=90**, `CENTER` |
| Upper cells 201/202/203 | **52×52** at **(147,109) / (199,95) / (251,109)**; centres **(173,135) / (225,121) / (277,135)** |
| Cell text and icon | **46×24 at (3,14)**, preferred **18**, existing **14/12** fallbacks; **24×24** icon at inset **14**, all centred at (26,26) |
| Occupied border | Path diameter **50.5**, stroke **1.5**, radii **24.5–26.0**; outward dissolve on all three, additional lower mask only laterally |
| Active logo | Original square PNG, **64×64 at (193,141)**, centre **(225,173)**, alpha **95** |
| Ambient logo | Same PNG, **54×54 at (198,146)**, same centre, alpha **70** |
| Equal legend wells | **132×26 at x=159**, radius **6**, tops **259 / 286 / 313**, pitch **27**, bottom **339** |
| Complete mixed-run label | **120×26**, inset **6**, centred at x=225; **20** through 10 characters, **18** at 11, **16** at 12+ |
| Row/markers | Whole-row alpha **255 active / 90 ambient**; unchanged marker geometry, family and token meaning; far marker follows the wider well |

The two `CLOCK` entries were the settings calibrated on the canonical Round 384 target,
retaining the 08:08 reference bottoms measured below. This is bounded native evidence,
not fixed optical bounds for every time string or device. Preferred cell font **18** is new relative to
font **17**; keep the **12** branch ahead of **14** and the existing weather/custom-length
predicates, data, defaults and units.

**Native calibration record, 2026-10-27.** The previous upward candidate's XML SHA-256 was
`54f6b76e349fba5c79c974dc70a1e17c96cfb6fda89adbafb6c266f072d35f17`, bound to active legacy
`app.wardpulse.watchface`, `wfId-15`. At 384×384, its clean **86 Bold/y175** 08:08 frame
(`f003321a…`) had exclusive ink bounds **[102,160,282,213]**, one native pixel above the
reference bottom 214. Its renderer-proven **97 Thin/y175 AMBIENT** frame (`9c0e4b00…`) had
bounds **[99,156,286,217]**, retaining bottom 217 with height 61. Using the source logo's alpha
boundary and first-row top 259, their respective above/below gaps in 450 units were
**6.5/9.390625 active** and **3.0625/4.703125 ambient**. These are calibration observations
for those bytes, not acceptance of the corrected bytes. The first-wake `2b2c27b2…` frame
visibly mixed Thin/Bold despite INTERACTIVE metadata and is **rejected** as Bold evidence.

**Corrected Round calibration, 2026-10-27.** That revision's XML SHA-256
`1685b2b3bb9e309fee38aee278a40ed8471c9e34bb7d3b7200eb3005f9f9c6dc` was bound to the
installed active legacy `app.wardpulse.watchface`, `wfId-15`. Settled 08:08 **86 Bold/y176**
had exclusive native bounds **[102,161,282,214]**, height **53**; renderer-proven AMBIENT
**96 Thin/y175** had **[99,157,285,217]**, height **60**. Both retained reference bottoms
**214/217**. Using the source logo alpha boundary and three-row top 259, above/below gaps
were **7.671875/8.21875 active** and **4.234375/4.703125 ambient** in 450 units. These observed
reference results establish upward enlargement with retained lower edges. They are not
measured composited-logo bounds, exact gap equality, a universal tolerance or an
all-string/all-row-count claim.

**Historical centred calibration, 2026-10-27.** At the initial nominal y182, matched Round 384
originals at **09:11 / 08:08 / 11:11**, each in INTERACTIVE and renderer-proven AMBIENT,
all had vertical glyph centre **193 native pixels = 226.171875 design units**,
against the then-target **192 native pixels = 225 design units**. The inherited candidate
therefore moved both 70 Bold/81 Thin clocks to y181, retaining `height=90` and `TIME_LIFT=0`
in review art. Its XML SHA-256 was
`6397e96db9e16596d802becbe262833b57ff2142ce4e03dc99f737e14271400c`.
That historical model used 50-unit cells, active 62-square at (194,142), ambient 52-square at (199,147),
and the same 132×26 legend. It does not accept the enlarged clocks or logos.
The earlier 13-second night-method diagnostic is not AMBIENT acceptance.

The historical Source6397 build's native 384-pixel **08:08** bottoms were **214 active /217 ambient**, hence
**250.78125 /254.296875** in 450 units. With the new logo ink bottoms **181 /179.75**
and the first three-row legend at **259**, the targets are:

| Mode | Equal visible gap | Desired clock ink top / height |
| --- | --- | --- |
| Active | **8.21875** | **189.21875 /61.5625** |
| Ambient | **4.703125** | **184.453125 /69.84375** |

The initial linear 86/97 estimates put the tops at **188.87277 /184.12905**. Estimated residuals
below **0.35 units** are neither actual font metrics, a pass nor a tolerance. The review generator
for that revision used per-mode `CLOCK` baselines to model the reference lower edges with
enlarged type, replacing
`TIME_LIFT=0`; SVG host glyph bounds are illustrative and do not establish native agreement.
Other strings retain natural ink, bottom and optical variation. Never retune by row count.

The [official PartImage reference](https://developer.android.com/reference/wear-os/wff/group/part/image/part-image)
declares integer x/y/width/height. The even 64/54-unit squares preserve their integer
centre directly, without rounding, a transform or an asset workaround. Legitimate floating
gradient/transform properties remain unchanged. Both logo boxes preserve the square source,
its original alpha pixels and bottom dissolve; no darkening, extra fade, blur or mask is added.
The runtime and phone-widget copies retain SHA-256
`599a722e2c08bb5d952e87ceb0ea02c228c77554e0dc3572e7eeb992b96d1cef`.

From the unchanged **192×192** source alpha bounds **x[4,186), y[46,120)**:

| Mapped nonzero-alpha ink | x interval | y interval |
| --- | --- | --- |
| Active, half-open bounds | **[194.333333…,255)** | **[156.333333…,181)** |
| Ambient, half-open bounds | **[199.125,250.3125)** | **[158.9375,179.75)** |

Preserve the source-padding asymmetry. Conservative central/left/right logo-to-well gaps
are **9.333333 /4.169889 /4.644920 active** and **11.9375 /9.433311 /9.850057 ambient**.
Transparent image/text box overlap does not imply ink overlap. The 52-well neighbour gap
is **1.851648**; 54-unit wells at these centres would overlap **0.148352**. Central/side
well aperture margins are **3.8 /3.857708**. Estimated 08:08 clock rectangles clear the
aperture by **21.3012 active /17.6139 ambient**; these are screening calculations only.
The bottom legend corner **(159,339)** is **131.7270** from the disk centre, leaving
**2.0730** inside the unchanged **133.8** clear aperture. These are affine/clearance calculations,
not native measurements.

Keep contiguous bottom anchoring: three rows at **259/286/313**, two at **286/313**, one
at **313**. Credits-only retains its thin framing track and row313; no-plan/no-credit draws
no row. Shorter stacks have larger gaps; the equal-gap intent does not extend to every
band count or string. Tightest-first ordering, paired identities, zero/unavailable survivor handling,
mixed numeric colouring, signed money/currency/denominators and all existing cell defaults
and overrides stay unchanged. Keep ring geometry, textures, palette, eight slots, stable
Group names, closed TITLE vocabulary, services, bindings, payload/schema/version, units and
navigation. Adaptive-width item 12 remains separate; no autosizing, dependency or new harness.

The existing bounded fit corpus remains complete: `100% · 64%`, `82% · 59.5K`,
`100% · 100%`, `100% · 999.9T`, `$999.99/999`, `$999.99/999.9T`, `$999.9T/999.9T`,
`$-12.34/100`, `0% · 0%` and `0% · 0`. Its host-font guard and the existing cell/semantic
guards run during owning generation. Explicit extreme/arbitrary strings retain ellipsis;
host-font fit does not prove Android mixed-run fit.

Generate canonical WFF XML/nine textures with `node tools/render-watchface.mjs` **before**
`node tools/render-watch-ring-designs.mjs`: the portrait reads the generated active PartImage.
The existing maps own **26 boards, 26 PNGs and 23 WFF mirrors**, plus the shipped picker
portrait. Ordinary boards remain mark-free; only the active portrait overlays the logo.
XML `--check` omits PNGs and design `--check` skips rendering, so preserve actual generation
provenance and inspect PNGs; unchanged texture inputs require unchanged content/hashes.

**Bounded native evidence, 2026-10-27.** After whole Runner completion, owning CLI exit and
fresh retirement, the Runner-produced candidate passed required checkout and full HOST
checks (`just check-watchface`, `just check-wear`, `just check-docs`), including strict Push's
successful-validation record and single-token guard. Legacy and Push APKs contained the
canonical XML and eleven matching images; native rendering below is for the active legacy face.
Root reviewed the corrected Round 384 08:08 anchors and all six **09:11/11:11/10:08**
INTERACTIVE/true-AMBIENT originals. Ten Mock fit cases (**20 originals**) plus two supplements
(**four originals**) covered count/pair/zero/partial/unavailable cases, credits-only 500 and
complete **20/18/16** money labels with **D/7D/M**. The restored Live supplemental frame was
also reviewed, with filled defaults. Square 360 completed twelve synthetic cases
(**24 originals**) and a restored MUTE frame, scoped to clock/legend/cell-well fit. It retained
cleared upper wells and a system low-battery indicator outside that scope; no populated-default,
bottom-ring-contour or public-cleanliness claim follows. Original summaries/settings were
restored; a fresh separate Square observation confirmed asynchronous notification restoration.
All seven healthy anonymous Live public originals and proportional exports were captured and
Root-reviewed with filled defaults and matching actual phone themes. Scoped publication review
passed for this [shared-state cohort](../assets/README.md#shared-state-capture-refresh-2026-10-27);
the screenshot index owns its capture-state and publication record.
These observations do not establish active Push rendering, every clock string or row-count
gap, physical/custom or extreme-weather behavior, signed-money native fit, or live Codex/Spark
selection. Temporary-time frames with unfilled weather wells are not showcase proof.
Keep source → generated resources → built/installed APK → active instance/effective-input
binding and before/after mode evidence. Reject mixed wake frames even under INTERACTIVE metadata;
MUTE/Doze, padded boxes and host fonts do not replace actual variant/ink proof. Any further
finding returns to Runner for correction, independent review, gates and native reobservation.
No old ±2-unit bound, per-time offset, clock helper or further Owner approval is introduced.
Restore temporary case/time inputs and automatic-time/offset settings, retain Europe/Paris,
leave Owner-phone/physical clocks untouched and reverify derived surfaces. Unobserved scope
remains Pending; older artifacts establish only their dated results.

## Goal

Glanceable **remaining** capacity for up to **three** user-selected percent metrics, with
remaining purchased **credits** on each strip for that provider family when reported (same
per-provider source as Glance). Purchased meters (Claude Extra usage, Cursor on-demand, Codex
credits) are **not** ring candidates — they stay on the phone dashboard and may appear as
alerts only when the user configures thresholds for those meters on **Providers**.
Not “always show every provider,” and never invent `Unknown` filler. Strip secondary values are
credits — never LLM `TOK` / token counts. The one strip that carries something else is a split
pair's, whose second value is the other pool's percent (see Split band).

## Layer rules

1. **One ring = one metric of one connection** — a provider plan/allowance window with a %, or
   one connection's local budget % for one period. There is no ring for a sum across
   connections: spend is reported by whichever connections report it, while a limit exists only
   where the user set one, so a summed percentage divides one set by another. Aggregate **money**
   is still true and stays on the phone dashboard cards — it is the aggregate *percentage* that
   has no owner and no meaning.
   Claude subscription plan windows are an exception at **selection** time: the phone exposes one
   Claude plan slot and resolves it to the tightest **known** remaining window, including zero
   (window name lives on Glance,
   not on face strips).
   The two Cursor pools or the main Codex and Spark limits may share one band at
   **drawing** time, split lengthwise (see Split band). Each pair stays one slot.
2. **Arc = remaining** — the colored sweep is `(100 - usedPercent)`. As the limit is consumed, the
   arc shrinks (do not grow a separate “used” fill). Melt is **clockwise from 12**: usage opens a
   gap at 12 o’clock and advances like a clock hand; remaining stays anchored ending at 12.
3. **Center / inner = tightest remaining** — among selected metrics with a known percentage,
   sort by plan remaining ascending (equivalently highest `usedPercent` first). When plan
   percents tie, secondary sort uses estimated remaining **request-equivalents** from that
   provider’s purchased credits (`credits /` internal credits-per-request constants — sort only,
   never shown as requests). Strips still show credits only. Payload index 0 is the critical
   limit: the innermost band that renders, and the topmost strip row that renders. Outer rings
   are looser. The strip stack anchors to its bottom row, so with fewer than three rings the
   tightest strip is the topmost **occupied** row rather than the top of the well area (see
   Upper cells, rule 3).
4. **Keep selected exhaustion; omit unknown or unavailable.** A known `usedPercent >= 100`
   means **0% remaining**, not missing data. Keep the selected band and its legend row, with
   the existing grey track `#2E3632` and **no coloured remaining arc**. The exhausted `0%`
   token takes **`#FFB4AB`**, the existing phone dark theme's error role, computed on the host
   from its Material color utilities configuration on 2026-10-13. This is a token choice,
   not a device pixel measurement. Only that percentage token is red: titles, separators,
   credits (including `0 credits`) and family accents retain their own colours. Local budget
   strips keep `$spent/limit`; a zero remainder keeps the track without adding a percentage
   or changing the strip width. Missing/null, non-finite or negative usage percentages remain
   unavailable and are omitted,
   never fabricated as zero. A **positive** remainder that rounds to a `0%` label still has
   a positive arc and ordinary label colour; exhaustion is decided from the value, not text.
   No alert, refresh state or threshold is inferred from this colour treatment.
5. **Max three** — phone **Watchface** tab chooses slots (`watchRingSlotCount = 3`); payload carries
   only the resolved surface order after omitting unavailable metrics and sorting; known zero
   still consumes its selected slot. Plan/budget percent metrics only. A split
   pair counts as **one** against the cap on both sides: it draws one band, and the Watchface tab
   charges either configured pair one slot: two pairs and one ordinary ring fit three slots.
6. **A budget ring is offered where spend is reported, and enabled once a limit is set** — the
   slot exists for a (connection, period) pair that reports spend, which is what makes a
   ceiling meaningful; subscription plans report none and carry allowance windows instead, and
   a connection that reports only monthly spend offers only a monthly budget. Providers never
   report the ceiling itself, so until the user sets one the slot stays visible but disabled,
   and the reason names where to set it (**Providers**, its own budget entry — not the alert
   dialog).

## Typography

**Noto Sans Bold** (SIL Open Font License 1.1 — free for any use, no field-of-use restrictions).
Bold/700 for active time and strip labels; Thin/100 for ambient time. Vertically center strip
glyphs using font metrics (not a guessed baseline fraction).

Runtime Wear/WFF may map to the closest platform sans until a bundled Noto Sans asset is wired.

## Provider / metric colors

Primary stroke / accent color is by **family**, not by status alone. Status (warn / error / auth)
may modulate toward theme tertiary/error when needed.

| Family | Stroke | Notes |
|--------|--------|--------|
| OpenAI / Codex | `#65D78A` | Green |
| Codex · Spark | `#186020` | Dark green — the Spark limit on the Codex plan |
| Anthropic / Claude | `#E8915A` | Orange (Anthropic presentation) |
| Claude · Fable | `#FF603D` | Warm red with an orange tint; exact included weekly sub-cap only; approved revision 2026-11-01 |
| Cursor · other models | `#67E8D4` | Cyan — external models on the Cursor plan |
| Cursor · own models | `#7E93B8` | Grey-blue — the plan's own pool |
| Unresolved family | `#8A968F` | Neutral grey — fallback only, never a product color |
| Demo data | `#8AB4F8` | The old blue, kept so mock data does not masquerade as unresolved. Phone-side only: `watchRingCatalog` drops mock accounts, so it never reaches a band |

A local budget ring takes the family color of the connection it belongs to, exactly like that
connection's allowance rings; period is carried by the type in the band (see Ring type texture),
never by a color of its own. For Cursor that colour is the **cyan**: grey-blue names one pool of
one plan, so nothing but that pool may wear it — a budget spans the whole connection
(`RingFamily.colorArgb`, and the `cursorPlatform` row on the Glance board).
Grey is what remains when a ring id resolves to no family, which should not happen for a ring
the product ships. It is deliberately colourless: the fallback used to be blue, and a blue
fallback beside Cursor's grey-blue pool would read as a product colour at band scale.

Distances, CIE76 ΔE on these values (a desk check, not a device one): the two Cursor pools sit 52
apart, which is what lets them share a band. Codex and its Spark limit sit **44.7** apart, the
same way. Dark green's tightest neighbour is not a family at all but the **track at 44.6**, and it
clears the surface by 53.6 — a half band still has to read against what it is drawn on. The
tightest pair in the whole palette is the grey-blue pool against **demo blue at 21**, then the
grey fallback at 25, then cyan against Codex green at 31 — all above the ~20 where hues start
collapsing on a 17-pixel band. The first two never meet on a band anyway: the grey fallback should
not ship at all, and demo blue belongs to the legacy single `mock` provider, whose accounts
`watchRingCatalog` skips outright — the seeded debug demo invents real families instead, so its
Cursor pools wear the pool colours. A new colour should clear 20 against every row here before it
is proposed.

Track (empty portion of the ring): muted graphite on dark surface (`#2E3632` in review art;
theme `outlineVariant` at runtime).

## Composition (active)

```text
  ┌──── remaining arcs (0–3 slots; hard max three) ──────────────┐
  │                                                              │
  │                       ( 18°C )                               │
  │             ( Tue )              ( UV 7 )                    │  ← three cells, on an arc
  │                                                              │
  │                   WARDPULSE watermark                        │  ← quiet mono, no ring
  │                       10:08                                  │  ← whole time (hero)
  │            ┌─ sunk well ──────────────┐                      │
  │            │▌ 8% · 500                │                      │  ▌ = family accent
  │            │▌ 39%                     │                      │
  │            │▌ 72%                     │                      │
  │            └──────────────────────────┘                      │
  └──────────────────────────────────────────────────────────────┘
```

Rules:

- **Time is the hero** — active 86 Bold and ambient 86 Thin share the reference `y=166`,
  `height=90` box under the common composition scale. Optical/native acceptance remains
  Pending under the [ambient-clock alignment](#revision-2026-11-03--ambient-clock-alignment).
- **Upper cells** — three customizable complication cells in the band the baseline reserved for
  a weather glance until **2026-10-09**. They retain a curved row, with the middle one higher
  than the outer two; the operative **2026-10-27** origins and 52-unit wells are listed above.
  All occupied borders retain their outward radial fade; only lateral borders add the
  strictly bottom-directed fade. The central border keeps its original outward treatment.
  The wearer chooses what each one holds. A fresh install shows the day of the week, the
  temperature and the UV index, but only the day is a complication: the two weather readings are
  the face's own chrome, so all three cells stay free for the wearer. A cell showing nothing is
  a well with a graded rim, which is how an empty cell says it is empty (see Upper cells).
- **Watermark** — ringless mono `WARDPULSE` + pulse/eye below the central cell and above
  the clock, image-box centre (225,173); active 64/ambient 54 squares at alpha95/70. Preserve
  the source PNG's original bottom dissolve. Same faded PNG is reused on the phone
  home widget (day/night tint). Details: `docs/DESIGN_ASSETS.md`.
- **Lower strips** — short rounded rectangles, not full-width tablets and not stadium pills:
  - sunk into the surface (dark well, no high-contrast border card);
  - thin left **family accent** bar (same ColorRamp / `ring.id` family as the matching arc);
    WFF strip slots are `RANGED_VALUE` so accents use `[COMPLICATION.RANGED_VALUE_COLORS]`;
  - **equal 132-unit width** for every strip, with the finite 20/18/16 label sizes above
    (compact `K`/`M`/`B`/`T` credits); wells stay inside the clear aperture. Extreme
    values retain the explicit ellipsis limitation;
  - measured horizontal padding so Bold labels clear the well edges;
  - strip order = tightest remaining on top (nearest center) when plan rings exist; since
    **2026-10-09** each strip is drawn by its own ring's slot and the stack fills from its
    bottom row upward, so one and two rings sit low rather than leaving a gap mid-stack
    (see Upper cells, rule 3);
  - content: `%`, or `% · credits` when that strip’s provider family reports purchased remaining
    (per-provider from `allowances`, same as Glance — not gated on aggregate `creditsGlance`);
    omit unused halves / omit empty strips;
  - **budget strips are the one exception to the remaining language** — they read spend of
    limit (`$12.34/100`), because a budget ceiling is a number the wearer typed and money is
    how the product already names it everywhere else; the arc above still melts by remaining.
    Spend keeps cents, the limit is whole (rounded to nearest). The earlier fit comparison
    recorded cents on both halves (`$999.99/999.99`) as 14 % wider than the then-worst credits
    label; that ratio belongs to the older font/strip geometry. The current finite-size
    corpus includes `$999.99/999`, with explicit ellipsis for extreme values. Currency travels as
    a code in the payload and Wear spells the symbol — a `$` baked into the watch would be a
    lie the day a connection bills in something else. A currency with no one-glyph symbol on
    the watch falls back to the plain `%` label rather than a spelled code: `EUR 999.99/999`
    was 118 % of the earlier locked width. The currency fallback rule is unchanged;
  - credits text is compact (`500`, `1.2K`) — never a `TOK` suffix;
  - a **split** strip is the exception to the accent rule and to credits alike: a marker at each
    end in the two pool colours, two percentages, no credits (see Split band);
  - ring band **20.2 units** in the 450-unit design language so arcs read clearer while a
    **3-strip** stack still clears the aperture (see Ring geometry: it is neither the nominal 40
    nor the 18.8 the scaling factor predicted — the band was measured, not derived).
- **Ring type** — a budget ring's band repeats its period; other rings carry none (see Ring type
  texture).
- **Credits-only**: thin framing track, large time, credits strip only — no percent arcs.
- No orphan captions (`Codex left`, floating unit labels) outside the strip row.
- Review art focuses on 1–3 provider families. A local **budget** metric may still occupy a product
  ring slot, drawn in its connection's family color; do not ship a “4 providers” face variant in
  review art.

## Split band (revised 2026-09-16)

A Cursor plan reports two pools — its own models and the external ones — and they are not
substitutes: exhausting one does not let the work continue on the other, it changes the tool.
Both deserve a ring, and spending two of three slots on one subscription is what makes the face
useless for everything else. So the two share **one band, split lengthwise**, each half melting
on its own value.

1. **Only when both are picked, and only one slot.** The division is allowed for
   two pools or limits of the same plan of the same connection: Cursor own/external pools
   and Codex main/Spark limits, plus ordinary Claude/Fable under the 2026-11-01 revision.
   Everything else stays one ring, one metric.
   The Watchface tab offers each pool as its own row: **ticking both** is what shares a band —
   either alone is an ordinary, undivided ring. A pair costs one of the three slots, which is the
   whole point: a plan with two pools does not cost two.
   Codex windows collapse independently to `allowance.codex.plan` and
   `allowance.codex.spark`, choosing the tightest known window per limit, including zero;
   ties prefer primary. Empty limits offer no ring; unavailable limits cannot be added,
   while saved unavailable choices remain removable. Fully exhausted selected limits
   remain visible. The picker keeps `Codex plan`
   and `Codex · Spark` stable; the winning window remains in the subtitle and payload.
   Old per-window Watchface selections migrate and deduplicate without capacity trimming;
   widget selections remain per-window. Spark window labels are `Spark 5h` / `Spark Weekly`.
2. **The order inside a pair is fixed by pool, never by usage.** Cursor own models take the
   inner half and left marker; external models take the outer half and right marker. Codex main
   takes inside/left, Spark outside/right; its darker `#186020` reads on the longer outer arc.
   Ordinary Claude takes inside/left in `#E8915A`, Fable outside/right in `#FF603D`.
   Position inside the pair is a name, not a rank: urgency is already carried twice, by each half's own melt and by
   where the pair sits among the rings. A third encoding would only make the colours swap sides
   at the moment the reader is looking at a problem.
3. **The pair sorts by its tighter half.** Layer rule 3 is unchanged and still means what it
   says — innermost is closest to exhaustion — because it ranks rings against each other, while
   rule 2 above orders the halves inside one of them.
4. **The strip splits with the band.** A pair's strip carries a marker at each end, in the two
   colours, and two percentages in one TEXT, as every strip label is composed whole. One marker
   stays the rule for every other strip: two of the same colour would say a thing twice, which is
   the defect this language exists to avoid. Each strip's `TITLE` carries a closed outer-pool
   token: `cursor-other` selects static `#67E8D4`, `spark` selects static `#186020`, and
   `fable` selects static `#FF603D`.
   An empty or unknown family token paints no far marker. Known zero does not remove a marker.
   The inner accent keeps `[COMPLICATION.RANGED_VALUE_COLORS]`; the
   outer accent does not borrow its colour. A new outer pool requires a matching token in Wear
   and the face generator. The far marker keeps its 3x14 geometry inside the strip's own slot,
   replacing the shared marker slot introduced on **2026-08-16**.

   **Old-face compatibility:** service names remain stable, but their data changes. With one
   pair, old slot 109 receives `NoData` and its far marker disappears. With two pairs, the first
   keeps both arcs without its marker; the second has no outer arc because old slot 109 still
   draws a marker. It interprets the second split's outside-counted band index as a payload row
   and may mark another row. Updating the face restores the matching layout; retaining service
   names alone cannot preserve the old rendering.

5. **A split strip carries no credits.** The well is measured for one worst-case label, and two
   percentages spend that width. Nothing is lost: Glance already lists purchased credits per
   provider, and that is where a reader looks for a number rather than a warning.
6. **Known zero keeps the pair (revision 2026-10-13).** Both known pools retain their fixed
   inner/outer positions and full grey half-tracks. A zero half paints no coloured arc and its
   `0%` token is pale red; the positive half keeps its colour and ordinary percentage. With
   both exhausted, retain both tracks, both family markers and **`0% · 0%`** with only the two
   percentage tokens red. The pair still costs one band and one Glance row. An unavailable
   half remains absent; the known survivor can render as an ordinary pool, and two unavailable
   halves render nothing. Unknown and exhausted therefore remain distinct. This supersedes
   the former exhausted-half collapse rule.
7. **One payload entry, two complications — two shared slots for outer halves.** A
   `RANGED_VALUE` complication carries one value, so two melts need two complications however the
   payload is shaped. A WFF scene holds at most eight `ComplicationSlot` elements (`maxOccurs="8"`,
   unchanged in format versions 2, 4 and 5), and this face still uses exactly eight. Until
   **2026-10-09** those were three band slots, two outer-half slots and three strips; since that
   revision they are three band slots that each also draw their own strip, two outer-half slots,
   and three upper cells (see Upper cells, rule 2). Moving the marker into each strip frees slot
   109 for the second outer half without adding a slot.

   `RingSplitComplicationDataSourceService` selects split ordinal 0 in slot 106;
   `StripSplitComplicationDataSourceService` selects ordinal 1 in slot 109. Ordinals follow the
   payload's split entries, not all its rings. A missing selected outer half yields
   `NoData`; a known exhausted half carries real zero data and does not shift the next ordinal.
   Each slot's `BoundingArc`
   reaches all three bands. Its `TITLE` names the band index **counted from the outside**, mapped
   from the payload index by `RingSurfaceOrder`, and a string comparison selects the radius.
   At most two bands can split; a third outer half has no slot.

   The band's own `TITLE` still says `split` for an inner half. Period tokens belong only to
   budget rings, so these uses cannot collide. The phone offers Cursor and Codex/Spark pairs;
   both outer-half slots can be active together.

8. **The payload says "one band", not "two rings".** The contract caps `rings` at three entries
   (`schemas/watch_dashboard_summary.schema.json`, `maxItems: 3`), and three entries mean three
   bands. If a pair travelled as two entries, a face holding a pair and two other rings would
   need four, and the cap would have to grow — which would also make "one slot" true only in
   prose. So the slot stays one entry and carries its second pool in `split`, added by **schema
   version 9** (2026-08-14). The version moved on both sides in one commit, as it must: a
   mismatch makes the watch discard the whole payload rather than part of it.

A split band never carries ring type, and no rule is needed to keep them apart: type belongs to
budget rings, and a Cursor budget ring hangs off the **team Admin** connection that reports
spend (`cursor/platform.rs`), while the two pools live on the **plan** connection
(`cursor/mod.rs`). Different connections, so a band is either one or the other. Which is
fortunate — a cap of 15.8 units does not fit in half a band.

Geometry was settled on a device, not in arithmetic: the halves measure 9.75 units each and
meet without a seam — numbers, and the four readings behind them, in Ring geometry under
*Halves of a band*.

## Upper cells (revision 2026-10-09)

The band above the clock was reserved for a weather glance from the baseline until this
revision, and carried nothing. It now carries **three complication cells the wearer fills**.
The reasoning is that the conventional watch metrics a wearer expects of any watch — the
temperature, the UV index, the date, a step count — are precisely what a face that otherwise
speaks only about AI spend has no way to say, and a reserve with no owner says nothing at all.

The weather the band was held for does arrive, and without taking a cell: WFF reads it from a
built-in source in an expression, so the face draws the temperature and the UV index itself,
beneath two of the cells, and yields them the moment the wearer puts something there (rule 11).
What the old reservation had wrong was not the content but the price it assumed.

**A note on the word.** These are *cells*, not apertures. This document already uses **clear
aperture** for the circular region inside the innermost band that the strip wells must stay
within, and that meaning is load-bearing in the strip-width rule. The earlier composition
called this band the "upper aperture"; it is the same band.

1. **Three cells of 52 units in a curved row, refined on 2026-10-27.** Each complete
   well/border/text/icon/slot moves together. The integer coordinates below must match
   in the WFF and review generators. Both whole clocks follow the current alignment revision:

   | Cell | Centre | Box origin, integer | Radius from face centre |
   |---|---|---|---:|
   | left | 173, 135 | `147, 109` | 103.9423 |
   | middle | 225, 121 | `199, 95` | 104.0000 |
   | right | 277, 135 | `251, 109` | 103.9423 |

   The derived clearances, against the clear aperture of **133.8** (the innermost band's
   outer edge at 154, less the 20.2 the band renders inward) and current `TimeText` boxes at
   `y=166` in both active and ambient, before the common composition scale:

   | | Value |
   |---|---:|
   | Left/right cell to inner band | **3.8577** |
   | Middle cell to inner band | **3.8000** |
   | Lowest cell to the clock box | **5.00 in both modes** (nominal box separation, not native glyph clearance) |
   | Between neighbouring cells | 1.851648 |
   | Middle cell above the outer two | 14.00 |

   **The former concentricity is historical.** The 2026-10-09 layout was derived from a
   circle of radius **106.8** around `225, 225`, at **−29°, 0, +29°** from vertical. Its ideal
   centres were `173.22, 131.59` / `225, 118.20` / `276.78, 131.59`, rounded by WFF to
   `173, 132` / `225, 118` / `277, 132`. A constant nominal radius gave a derived **6.00**
   gap to the band; the measured gap on `emulator-5554` on **2026-10-11** was **5.79**.
   That reading belongs to the former placement. The current row retains the curve and
   14-unit rise with slightly wider spacing, giving up exact concentricity with the bands.
   The current clearance table is calculated from the integer centres, not presented as a
   new device measurement.

   **What the straight row got wrong.** Until the 2026-10-09 cell-layout revision the cells were 48 units at
   `y=134`, on `x=169 / 225 / 281`. A straight row under a circular boundary cannot hold an
   even gap:

   | Cell | Radius of centre | Far edge | Gap to the band |
   |---|---:|---:|---:|
   | left | 106.85 | 130.85 | **2.95** |
   | middle | 91.00 | 115.00 | **18.80** |
   | right | 106.85 | 130.85 | **2.95** |

   A spread of **6.4 times** across one row, and — the three cells sharing one `y` — **2.0**
   units between all of them and the clock. What the eye reads there is not three discs but the
   wedge of empty space between them and the band, narrowing towards the outer two — the row
   looked uneven because it was, and the measurement came after the owner said so, not before.

   **Historical 42-unit placement, 2026-10-13.** The complete cells moved three units down
   to origins `(152,114) / (204,100) / (256,114)`. The following measurements belong to
   that older build and do not validate the enlarged wells above.
   The square `BoundingBox` remains distinct from what is painted. At that lowered integer
   placement its furthest corner reaches **132.8533**, now inside the 133.8 aperture. The
   well's furthest edge is **125.0**, and the inset text box's furthest corner is **121.8277**.
   These are derived bounds. A bounding box is where taps land (rule 9); the cell still draws
   its well and border inside the 42-unit circle. The lowered placement was verified on
   **2026-10-13** on `wardpulse_wear_round_api36_1`, `emulator-5554`, **384×384**, after the
   final finite XML was installed. All three cells retained their contents and clearance;
   the integer origins moved by three design units. The captured text moved about two screen
   pixels; glyph differences and antialiasing make that a separate observation from the
   declared **2.56 px** translation.

2. **The three cells cost the three strip slots, and each strip folds into its own ring's
   slot.** The eight-slot cap is now established twice over: a ninth `ComplicationSlot` is
   rejected by the validator in format versions 2 and 5, and the schema states it outright
   (`sceneElement.xsd:45`, `ComplicationSlot maxOccurs="8"`). Raising the format version buys
   nothing. The budget after this revision:

   | Slot | Draws |
   |---|---|
   | 101 | outer band + its own legend strip |
   | 102 | middle band + its own legend strip |
   | 105 | inner band + its own legend strip |
   | 106 | outer half of the first split |
   | 109 | outer half of the second split |
   | 201 / 202 / 203 | upper cells — the wearer's choice, above the clock |

   Folding is only possible because the band slots give up their `BoundingArc`, which clips a
   slot's drawing to its own band and would erase a strip lying below it (Ring geometry, *The
   cause of the half-nominal band*). What the two jobs do to the slot's data channels is rule 4.

   **A changed slot does not pick up its new default on an installed face.** Measured
   2026-10-09, in this order: cells declared on the freed ids 104 / 107 / 108 drew nothing;
   moving them to the unused ids 201 / 202 / 203 drew nothing either, with the runtime logging
   `id[201] : EMPTY`; only uninstalling and reinstalling the package made the slots take their
   declared providers, after which the same ids logged `SHORT_TEXT`. So the binding is held
   against the installed face rather than against the slot id, and a fresh id is not an escape
   from it. This is a fact about updating a face in place, and it is the same hazard the
   migration note in `docs/DEVELOPMENT_PLAN.md` Phase 20 records for the Wear services.

   The cells are nonetheless given ids of their own rather than the freed 104 / 107 / 108. That
   is a choice, not a remedy: an id that once named a WardPulse strip and later names a cell the
   wearer configures is a name that means two things across the face's history, and this
   document has kept slot ids stable and meaningful since the baseline. Reusing them buys
   nothing, since neither id survives the update without a reinstall.

3. **The strip stack anchors to its bottom row.** Each ring slot paints its strip at a fixed
   height — 105 at `y=259`, 102 at `y=286`, 101 at `y=313` — and nothing in the markup varies
   with how many rings are active. That is sound because arc slots always fill from the outside
   (`RingSurfaceOrder` maps slot *k* counted from the outside to payload `n-1-k`), so the
   occupied rows are always contiguous and always end at `y=313`:

   | Rings | Bands drawn | Strip rows | Tightest |
   |---|---|---|---|
   | 3 | 101, 102, 105 | 259 / 286 / 313 | `y=259` |
   | 2 | 101, 102 | 286 / 313 | `y=286` |
   | 1 | 101 | 313 | `y=313` |
   | 0 | none | 313 — credits only | — |

   **The zero row is a shipped state, not an edge case.** A payload may carry purchased
   credits and no plan ring at all, and the face has always shown that as a lone strip; before
   the fold it was strip 0's job, by the branch in `stripLabel` that falls back to
   `creditsGlance` when no ring sits at that index. The row follows the rule rather than the
   old numbering: one row that is contiguous and ends at `y=313` **is** the row at `y=313`, so
   the bottom row carries it and slot 101 paints it. Putting it on `y=283`, where strip 0 used
   to live, would open under it exactly the hole this anchoring exists to prevent.

   The slot cannot tell that case from an ordinary one by its value — a credits row carries a
   full bar — so it says so in `TITLE` instead, with `credits` (rule 4), and the face branches
   the band away on that token rather than on the number. That is why the row draws with no arc
   behind it.

   Layer rule 3 therefore holds at every count: the tightest remainder is the topmost occupied
   row, and the stack never opens a hole in the middle. The visible change is that one and two
   rings now sit low in the well area instead of hugging the watermark. A top-anchored stack
   cannot be folded at all — the row a slot must paint would move with the ring count, and one
   slot has one height.

4. **One slot, two jobs: only `TITLE` collides.** Audited against the shipped `watchface.xml`
   by which slots read which channel:

   | Channel | Read by | Folded |
   |---|---|---|
   | `RANGED_VALUE_VALUE` | band and outer-half slots only | free |
   | `TEXT` | strip slots only | free — a band slot never reads it, so it carries the strip label |
   | `RANGED_VALUE_COLORS` | both | same family colour either way |
   | `TITLE` | both — bands branch on `D` / `7D` / `M` / `split`, strips on `cursor-other` / `spark` / `fable` | **collides** |

   The collision is resolved by a combined closed vocabulary, with each branch comparing against
   the full set of combinations joined by `||` — WFF has no prefix test, so a token is matched
   whole or not at all. A budget ring is never shared, so no period token gains a zero suffix.
   The selected-zero revision adds one ordinary plan token and three optional paired suffixes:

   | `TITLE` | Band | Strip |
   |---|---|---|
   | *(empty)* | a plan ring's full band | no far marker |
   | `zero` | a plan ring's grey track, no coloured arc | pale-red `0%`; no far marker |
   | `D` / `7D` / `M` | a budget ring's band, with its type | no far marker |
   | `split` | the inner half only | no far marker — outer family token absent |
   | `split:cursor-other` | the inner half only | the Cursor pool's marker |
   | `split:spark` | the inner half only | the Spark pool's marker |
   | `split:fable` | the inner half only | the Fable metric's marker; Source revision 2026-11-01 |
   | `credits` | **no band at all** | the lone credits row (rule 3) |

   Each paired base (`split`, `split:cursor-other`, `split:spark`, `split:fable`) accepts no suffix
   or exactly one of **`:zero-inner`**, **`:zero-outer`**, **`:zero-both`**: sixteen closed spellings.
   Every spelling preserves the band's half geometry and its base family-marker selection.
   The zero suffix selects only the exhausted percentage token(s) for pale red. Full `TEXT`
   still carries the complete label, with separators and credits retaining normal colour;
   budget periods and the credits-only token are unchanged.

   The Fable extension remains Pending for native acceptance; the historical runtime record
   below covers the earlier pool tokens.

   **The combined branch has now executed.** Until the generator changed, live data sent a plain
   `split` and this was recorded here as unverified through several revisions. It is not any
   more, and not by accident: the Wear service composes the suffix by construction whenever a
   shared band has a known pool. Measured on `wardpulse_wear_round_api36_1` — a Cursor pair
   rendered its inner half with the teal far marker on its row, which is the
   `split:cursor-other` branch and nothing else.

   Note that the validator does not check expression keywords at all — calibrated 2026-10-09, an
   invented `[COMPLICATION.BOGUS_FIELD]` passes — so a validator pass is evidence of well-formed
   markup and nothing more. The reading above is the evidence; the validator is not.

5. **The cells belong to the wearer, and nothing of ours can own them.** Slot configuration is
   edited by the system — a long press on the watch, or the Wear OS companion app on the phone
   — and the reason is stronger than an API we happen to lack. This package ships **no code**:
   zero `.dex` entries, `android:hasCode="false"`, no activity and no service. A Google process
   draws it, `com.google.wear.watchface.runtime/DeclarativeWatchFaceRuntime0`, and the provider
   chooser is a system activity in `com.google.android.wearable.sysui`. A WFF face therefore
   cannot hold an editor at all, and the configuration is not our package's to write. Measured
   2026-10-09; the readings are in `docs/ANDROID_TOOLCHAIN.md`, *Watch Face Format*. The
   WardPulse phone app is excluded twice over, since
   `ComplicationDataSourceUpdateRequester` only asks our own providers to refresh their data.
   What this document owns is the declaration: the cells are `isCustomizable="TRUE"`
   with supported types `SHORT_TEXT RANGED_VALUE MONOCHROMATIC_IMAGE EMPTY`, and that only the
   left cell ships bound to a provider, `DAY_OF_WEEK`. The other two ship `EMPTY`, with the
   temperature and the UV index showing through from the face's own chrome beneath them
   (rule 11). A fresh install therefore reads as a finished watch without spending a cell to
   look like one, and the wearer who wants all three keeps all three.

   **Editing correction 2026-10-11 — the system edits the cells only if the package asks it
   to, and this one never did.** Everything above about *who* edits a cell was right and is
   unchanged: the package ships no code, a Google process draws the face, and the chooser is a
   system activity. What was missing is the declaration that asks the system to offer its
   editor at all. `watch_face_info.xml` declared one element, `Preview`. The metadata file also
   carries **`Editable`, which defaults to `false`**, and that flag is what shows or hides the
   Edit button in the favorites list; the documented condition for setting it is a setting or
   at least one non-fixed complication, which this face has met since 2026-10-09 with three.
   So from the day the cells were locked until today, rule 5 described a path a wearer could
   not walk.

   **Before**, measured on `emulator-5554`, 2026-10-11, three readings that agree.
   `dumpsys wear_service` reported `Editable Resource Only WatchFace=false` for the active
   face, alongside `activeWatchFaceComponent=WatchFaceId[app.wardpulse.watchface,null]` and
   `Resource Only WatchFace=true`. In the system picker, WardPulse centred, a UI dump offered
   only `Activate WardPulse` and `Move watch face left`; scrolled one face along in the same
   session, the neighbour offered `Edit watch face` as well — so the editor exists on that
   build and was withheld from ours, not absent. Launching the chooser directly
   (`ProviderChooserActivity`, `ACTION_CHOOSE_PROVIDER`, complication id 202) failed with
   `Failed to find watch face info`, for both the face package and the runtime package as the
   component.

   **After**, same AVD and same session, with `<Editable value="true" />` declared and the
   package rebuilt and installed. `dumpsys wear_service` reports
   `Editable Resource Only WatchFace=`**`true`**, everything else in that block unchanged. The
   picker offers `Edit watch face` for WardPulse at bounds `[140,310][244,374]` — the bounds
   the control face carried when ours carried nothing. The button opens
   `com.google.android.clockwork.sysui.experiences.watchfaceeditor.WatchFaceEditorActivity`,
   drawn over the face with a selection box on each upper cell, and it exposes **exactly three
   targets and nothing else**: `Day of the week` at `[130,95][166,131]`, `Add complication` at
   `[174,83][210,119]`, `Add complication` at `[218,95][254,131]`. That is this face's own
   declaration read back — slot 201 holding its `DAY_OF_WEEK` default, 202 and 203 empty — and
   it is the first evidence that the eight-slot scene exposes its three customizable slots and
   only those. Selecting a cell opens `ProviderChooserActivity`, on a list of providers that
   begins `Empty`, `Battery · Wear OS`, `Date` — its full extent is under rule 8. The editor
   log names the slots in a numbering of the system's own, not the face's:
   `slotId=16 … DayOfWeekProviderService type=3`,
   `slotId=17 providerComponent=null type=2`, `slotId=18 providerComponent=null type=2`. One
   holds the day-of-week default and two are empty, so 16, 17 and 18 are this face's 201, 202
   and 203; how the system arrives at those numbers was not established and is not assumed
   here.

   The declaration also ships: the compiled APK's `res/xml/watch_face_info.xml` reads
   `E: Editable / A: value=true` under `aapt2 dump xmltree`.

   **One AVD, one Wear build.** `emulator-5554`, the canonical round Wear OS image. Nothing
   here is a claim about other devices or other system versions; it is what this one does.

   **The validator cannot catch this class of mistake**, which is worth knowing before trusting
   a green run here. `tools/validate-watchface/validate.sh` passes exactly one file to the
   official validator, `res/raw/watchface.xml`, and the schema bundle inside that jar
   (`docs.zip`, versions 1 to 5) contains no schema for `WatchFaceInfo` at all. A misspelled or
   invented element in the metadata file compiles into the APK and passes every gate in this
   repository in silence.

6. **A cell holds about four ordinary-size glyphs.** 52 design units is about 44 px at 384 —
   an icon, or a short label such as `72%`, `$12`, `2h`, `UV 7`. This is why the budget label
   stays on a strip: `$999.99/999` is a strip-width number and has no reading at cell scale.
   A cell never carries a value that only makes sense at full strip width.

   The historical ink measurements behind "about four" were taken in the original **48-unit**
   cell, before 2026-10-09: `Tue` 23 units, `18°` 18, `UV 7` 27. At the subsequent 42 units the
   same three labels were rendered on the AVD in the 37-unit line box of rule 7 and read
   cleanly, but their ink was not remeasured. That observed fit belongs to the old font/box.
   The upward-digit revision records dated Round default-reading fit and the narrower
   Square cell-well scope; arbitrary custom/extreme readings and physical fit remain unproved.

7. **A complication has no appearance of its own; the face draws all of it.** WFF gives a
   provider no say in how its data looks. What arrives is data — `TEXT`, an optional `TITLE`, an
   optional monochromatic icon, a ranged value and a colour ramp — and every visual decision is
   the face's: font, size, weight, colour, alignment, and what to draw at all. A cell cannot
   inherit a system style, and nothing stops three cells fed by three unrelated providers from
   reading as one row. `SHORT_TEXT` draws `TEXT` alone, centred on one line, in the face's own
   label voice: Bold, `#fff4fbf8`, size **18**, **14** at 5–6 characters and **12** at 7 or more,
   ellipsised for arbitrary overflow. The **46×24** text box is centred in the 52-unit well at
   **x=3/y=14**, giving an integer centre on both axes. The provider's `TITLE` and its icon
   are both dropped. At four ordinary-size glyphs there is no second line to put a title on,
   and a cell's own position is the label the wearer
   learned when they chose it; an icon beside the text would halve the text, and the value is
   what the cell was filled for. The 2026-10-09 spike rendered size14 — `Tue`, `0` and `UV0`
   all read at 384 px. That older observation does not establish fit for the new font branches.

   **Historical 37-unit box: `x=2` carried one unit of asymmetry.** WFF coordinates
   are integers: the validator rejects a fractional one outright, `'152.2' is not a valid value
   for 'integer'`. The exact inset is `(42 - 37) / 2` = 2.5, so the box runs 2..39 inside 42 and
   sits half a unit left of the cell's own centre. An even leftover — a 36-unit box at `x=3` —
   would land exactly, but it has not been rendered, so it is recorded as where the number comes
   from rather than as a recommendation.

   **The complete reading is centred, including its scale (revision 2026-10-13).** The
   temperature now reads `18°C` or `51°F`, so the scale is part of the label. Its whole string
   uses the same unshifted box as `UV 7`; the operative revision uses **x=3/width46**. This leaves
   the same clearance on both sides without assuming an advance for the device's own font.

   **The former correction centred the digits of a degree-only reading.** Measured
   2026-10-09, `18°` sat with its string centre at 224.5 against a cell centre of 225, while its
   digits sat at 222.5. Moving the box right by 2 (`x=4`), half the degree sign's advance,
   brought the digits to 224.5. Adding a scale letter invalidates that measured two-unit
   correction, and increasing it would take clearance from the right side. The new revision
   therefore replaces numeric-only centring with complete-label centring, rather than guessing
   a new offset. From 2026-10-09 until 2026-10-12 the former shift was present even though the
   template drew a bare number; the historical readings in rule 11 record that mismatch.

8. **The other accepted types, and the two that are refused.** `MONOCHROMATIC_IMAGE` is the one
   type whose whole content is an icon. It is drawn at **24 units in the 52-unit cell** and
   rendered in `#fff4fbf8`, the same colour as the text, so an icon reads as face text rather than as
   a foreign mark; half the diameter leaves the well's rim clear on a round recess. The
   integer inset **14** centres both axes exactly. Inside the existing icon-only Group, a
   full local face-coloured Rectangle is drawn as `SOURCE` before the live icon is drawn as
   `MASK`. This WFF2 composition selects face RGB through the image's alpha; the well and
   border stay outside it. The Group alone dims the composed icon from alpha 255 to **140**
   in ambient; its source and mask have no tint or extra attenuation. The icon deliberately
   does not use a family colour: on this face a family colour means *this ring's
   provider*, and a cell is not a ring. `RANGED_VALUE` is drawn as **text, never as an arc** —
   nonempty provider `TEXT` wins verbatim, including `0` and whitespace, at the existing
   **18/14/12 Bold** sizes selected by lengths **5/7**. Otherwise an explicit Default sends
   the raw `RANGED_VALUE_VALUE` directly to a `%s` Template at **18**, without measuring the
   number's length, rounding, normalizing against min/max or inventing units or percentages.
   Zero, fractions and signs retain their meaning; `4` versus `4.0` is not a cosmetic rule.
   Both paths retain the centred **46×24** ellipsis box and ambient alpha **140**, inside one
   occupied Group with its existing opaque well and border. Neither path adds `TITLE` or a
   companion icon. A small arc in a cell would
   put a second arc language on a face whose arcs already mean one thing, layer rule 1's *one
   ring = one metric of one connection*, and it would say it a few units from the real ones —
   rule 1 records the clearances of every cell's far edge from the innermost band.
   The ramp colour goes unused for the same reason family colouring does. Representative
   native null-TEXT selection and monochrome paint passed the bounded 2026-11-04 checks
   recorded in the correction below.

   `SMALL_IMAGE` and `LONG_TEXT` are left out of `supportedTypes` on purpose, which is what
   keeps the system editor from offering a provider that supplies only one of them.
   `SMALL_IMAGE` is the provider's own picture in the provider's own colours and WFF offers no
   tint for it — a foreign colour image in a 52-unit circle, on a face whose whole palette is
   family colours over near-black, reads as a sticker on the glass. `LONG_TEXT` is sized for a
   slot several times this one and has no reading at four glyphs (rule 6).

   **Correction 2026-11-04 — explicit ranged fallback and monochrome composition.** On the
   canonical 384×384 round API36 emulator, the old Legacy 688 renderer at instance `wfId-15`
   showed a blank reading for valid `RANGED_VALUE` data with `TEXT=null`, min 0 and max 10
   in canonical slot 201 (native slot 16, controller 98; original `25c60e…`). The runtime
   numeric value was **REDACTED**: the fixed `4` in the QA source and successful stock
   wire/Parcel test are separate provenance, not a runtime numeric readback. A valid
   single-hue magenta `MONOCHROMATIC_IMAGE` remained magenta despite the old Group tint
   (original `d80c95…`), including the recorded true-AMBIENT/settled-return observation
   `6cc6…`. Correct shape and fit did not establish recolouring. These were renderer
   failures with valid inputs, not `EMPTY` data or a reason to recolour the producer.

   The Source repair in `cellSlot` of `tools/render-watchface.mjs` now chooses nonempty
   provider TEXT explicitly, with a direct raw-number Default, and replaces icon tint with
   the local WFF2 `SOURCE`/`MASK` composition described above. The existing `cell_readouts`
   and `check_temperature` assertions in `tools/check-watchface-structure.py` cover synthetic
   empty TEXT, numeric zero/fraction/sign, verbatim provider text and the isolated icon tree.
   They do not emulate WFF null coercion, Float spelling, localization or native paint.

   **Bounded native acceptance, 2026-11-04.** Source `975e533` passed the mandatory HOST
   checks and matched LegacyRuntime0/`wfId-15` and PushRuntime1/`wfId-16` observations.
   Actual null-TEXT ranged input visibly produced `4`, the present-TEXT control showed `64`,
   and the legal magenta icon rendered a face-white Pulse in INTERACTIVE, true AMBIENT and
   settled return. Root and independent review covered the originals; matched pixel checks
   retained silhouette, antialiasing and background with no magenta. Numeric VALUE stayed
   redacted: the fixed QA input and wire test do not establish a runtime scalar readback or
   universal Float spelling/localization. All eight choices on both renderers and the Legacy
   favourite/instance were restored before both QA overrides returned to DEFAULT; all four
   input holders retired with touches released, font/bridge retained and newer Live preserved.
   Push materialized absent style as explicit Auto with the same effective setting; raw style
   byte equality is not claimed. This is representative emulator acceptance, not every
   provider, extreme reading, physical/OHealth or public-capture verification. The old probe's
   Day/default overrides, all eight slots, favourite, instance, package, OS and bridge state
   were restored; that recovery alone is not acceptance of this repair. Physical devices remain outside this bounded emulator evidence. The dated
   audits below retain what was and was not observed at those earlier revisions.

   **Scoped compatibility audit, 2026-11-01.** Current `cellSlot` in
   `tools/render-watchface.mjs` reads only `[COMPLICATION.TEXT]` for `SHORT_TEXT` and
   `RANGED_VALUE`; it does not draw their `TITLE` or companion icon. The monochrome-only
   branch remains separate. The intended numeric fallback above has no explicit Source
   branch, and the checked [WFF Complication reference](https://developer.android.com/reference/wear-os/wff/complication/complication)
   lists text and ranged fields separately without guaranteeing an automatic fallback or a
   blank result. Actual ranged data without `TEXT` remains unverified, not a proved blank bug.

   On the canonical 384×384 round API36 emulator, Legacy `6fc79b39…` retained instance
   `f78b616d…`. Battery was configured and observed as `SHORT_TEXT` in all three positions,
   showing `100`; the middle/right opaque wells hid built-in weather/UV. All three readings
   remained visible in true `AMBIENT` and after return to `INTERACTIVE`. A centre-region tap
   opened Settings Battery, without proving a specific completed slot dispatch. Emulator
   Placeholder Heart Rate showed mock `79` as short text, not real health data. WardPulse
   outer half 1 in the middle cell was configured/observed as `RANGED_VALUE` and showed its
   supplied text `64`; editor-preview `62` was separate evidence, not that live value.
   Day/Empty/Empty and Auto were restored; the final read-only probe passed six complete
   eight-slot inventories against configuration `a0f58cef…` and the same instance. The full
   restored face retained newer Live metrics. No OS preferences or physical devices changed.
   Missing-TEXT ranged data, monochrome/ambient-image rendering, long/custom/extreme labels
   and a positive NoData-placeholder case remain unobserved. This is bounded compatibility
   evidence, not every provider/field combination or physical/OEM acceptance; no runtime
   change is justified by the unavailable missing-TEXT case.

   **Correction 2026-10-11 — what a device confirmed was the `SHORT_TEXT` path, not this one.**
   An entry written here earlier that day claimed a `RANGED_VALUE` had been witnessed drawing as
   text. It had not. On `emulator-5554`, `Battery · Wear OS` was put into the middle cell
   through the system editor — reachable at all only since rule 5's Editing correction — and the
   face drew **`100` as text inside the hairline ring**. That rendering is real, and it is a
   witness: of rule 7's `SHORT_TEXT`. The runtime had bound the slot as short text,
   `slot=17 type=3 provider=…BatteryProviderService`, and `type=3` is `SHORT_TEXT`. The face
   drew text because it was handed text, and nothing here exercised a ranged value. In the same
   frame the right cell stayed a graded recess with no ring, which is rule 10. The cell was then
   set back to `Empty` and the slot confirmed at `slot=17 type=2 provider=null`, so the device
   was left as it was found.

   **The face does not choose the type; the system does.** A cell offers
   `SHORT_TEXT RANGED_VALUE MONOCHROMATIC_IMAGE EMPTY`, and every provider tried that offers
   short text was bound as short text — `Battery · Wear OS` and `WardPulse ring 1`
   (`TodayComplicationDataSourceService`), both at `type=3`. A `RANGED_VALUE` binding can
   therefore only come from a provider that offers nothing else.

   **One was reached, and it had nothing to say.** The Wear manifest declares `RANGED_VALUE`
   alone for exactly two sources, `RingSplitComplicationDataSourceService` and
   `StripSplitComplicationDataSourceService` — the chooser's `WardPulse · outer half 1` and
   `outer half 2`. Selecting the second into the right cell bound
   `slot=18 type=5 provider=…StripSplitComplicationDataSourceService`, and `type=5` is
   `RANGED_VALUE`. The cell drew the **empty treatment** — graded well, lit rim, no hairline, no
   text — which is right rather than a defect: `SplitBandComplicationDataSourceService` returns
   `null` unless the stored summary carries a split band at that index, and the payload on that
   device had one pair at index 0 and nothing at index 1. A complication with no data is `EMPTY`,
   and rule 10 draws `EMPTY` as free.

   So the binding is reachable and the drawing is not. **A `RANGED_VALUE` carrying data has
   never been put in a cell on that AVD and cannot be**, because the only two providers that
   force the binding are ours and both decline the request. Witnessing it needs a provider that
   offers `RANGED_VALUE` without `SHORT_TEXT` and returns data for an arbitrary slot; none is
   installed there. Until one is, *drawn as text, never as an arc* stands as a declaration.

   `MONOCHROMATIC_IMAGE` was not reached either, and nothing on that AVD is known to supply
   one. The chooser was walked in overlapping steps
   until the list stopped growing: **eighteen entries counting `Empty`** — ten stock providers
   under *Wear OS* (date, time, day, battery, step count, notifications, sunrise and sunset,
   world clock), one `Placeholder Heart Rate` under *Emulator complication providers*, and six
   under *WardPulse*. **None of ours can supply an icon**, and that is checkable here rather
   than on a device: `apps/wear_android/app/src/main/AndroidManifest.xml` declares
   `SUPPORTED_TYPES` on all six WardPulse data sources — `RANGED_VALUE,SHORT_TEXT` for Today,
   Week and Ring3, `RANGED_VALUE` for RingSplit and StripSplit, `SHORT_TEXT` for Status — and
   `MONOCHROMATIC_IMAGE` appears in none of them. Six declared and six offered is also the two
   readings checking each other. What each stock entry supports was not established, so the
   historical 21-unit tinted draw had no device reading behind it. The current 24-unit icon
   in rule 8 also remains unverified; witnessing it needs a provider that supplies the type.
   And the sentence above about a provider that sends no `TEXT` stands
   unmeasured as it says: `Battery` sends `TEXT`, and `100` is what it sent. The split-band
   source does not measure it either — it returns no complication at all rather than a ranged
   value with the text missing, and those are different things.

   One entry in that list is not a watch's. `Placeholder Heart Rate` comes from *Emulator
   complication providers*, a package that ships with the AVD image and not with a device, so a
   reader comparing this list against a real watch will come up one short. That is a property
   of the emulator, not of the face.

9. **A tap reaches the cell, not the band under it.** Folding makes each band slot claim the
   whole canvas, so all three bands lie under the cells. Measured 2026-10-09 on
   `wardpulse_wear_round_api36_1` with every bounding arc replaced by a full-canvas
   `BoundingBox`, resetting to the face between taps:

   | Tap at (x, y), screen px at 384 | On | Opened |
   |---|---|---|
   | 192, 20 | outer band | `app.wardpulse/MainActivity` |
   | 70, 192 | outer band | `app.wardpulse/MainActivity` |
   | 192, 300 | band only, below the clock | `app.wardpulse/MainActivity` |
   | 144, 114 | cell bound to `DAY_OF_WEEK` | nothing — that provider carries no tap action |
   | 240, 114 | cell bound to `WATCH_BATTERY` | the watch Settings app |

   These are screen pixels, not design units — a tap is delivered in the device's own
   coordinates, so recording it in the 450-unit language would be a conversion with no source.
   The two bindings are the spike's, chosen because they differ in whether they carry a tap
   action at all; the shipped defaults are rule 5's.

   WardPulse opened on no tap into a cell. A third-party complication placed in a cell therefore
   opens its own app, which is the whole point of giving the cells away.

10. **An empty cell carries no mark of ours, but it does say it is empty.** No glyph, no
    WardPulse logo — the non-goal "Brand/marketing chrome, floating badges" stands, and the face
    already carries the wordmark once, as a watermark. An empty cell shows its well, and the
    weather reading where the face declares one beneath that cell (rule 11); nothing else. The
    well sits over the face background `#ff0a0d0b` and its radial lift (`#18201C → #101412 →
    #0A0D0B`, centred `225, 216`, radius 279).

    **The well has three treatments, chosen by what the cell is showing — not by what it is
    called.** A flat well told the wearer nothing: until this revision a cell holding a
    complication and a cell holding nothing were the same dark disc, distinguishable only by the
    presence of text, so an empty cell read as a fault rather than as an invitation.

    | Cell shows | Well | Ring | Drawn |
    |---|---|---|---|
    | a complication | flat `#ff0b0e0c` | yes | inside the slot — it is the occluder |
    | our weather reading | flat `#eb0b0e0c` | yes | scene chrome |
    | nothing at all | graded, below | no | scene chrome |

    **The ring is what says a cell is occupied (revision 2026-10-10; border revised 2026-10-13).**
    The operative revision uses a stroke of **1.5** on a path of **50.5** — radius **24.5 to 26.0**,
    inscribed in a well whose edge is at 26, in the face's own text colour. All three borders
    retain the outward radial fade from peak alpha `0xaa`; only lateral borders add the
    vertical 6 o'clock treatment. The centre has no ADDED bottom fade, not a uniform rim.
    It goes on the wearer's
    complication and the face's own weather reading alike, and never on an empty
    one. That is the whole of the language: **a ring means occupied, a recess means free**, and
    a cell is never both.

    **Historical directional border revision 2026-10-13 — fade towards the band.**
    The geometry and device readings in the following account belong to the older 42-unit
    wells. The current 52-unit rule retains their outward radial language at its new centres
    and adds a separate bottom-only lateral treatment; these old coordinates are historical.
    The owner chose the same soft dissolve the watermark uses towards the legend, then asked
    that it follow the shortest path to the adjacent band after the initial fixed directions
    looked asymmetric. The original **10:30 / 12:00 / 1:30** treatment is superseded. The
    direction then used was derived from the actual cell centre `C` and face centre `F=(225,225)`:
    `u=(C-F)/|C-F|`. The nearest point on the circular boundary of radius 133.8 is `F+133.8u`,
    and the cell's nearest outer border point is `C+21u`. The directions are therefore
    **329.9816° / 0° / 30.0184°**, about **11:00 / 12:00 / 1:00**, with exactly mirrored side
    vectors. These angles are calculated, not tuned by eye. They do not move with a band's
    remainder or arc end. The border grows inward from 1 to 1.5 units; reducing
    its path diameter from 41 to 40.5 preserves the outer radius of 21 and the existing
    clearance. This is declared geometry, not a new device measurement.

    The native WFF version-2 `Stroke` uses a `LinearGradient` from `C-20.25u` to `C+20.25u`,
    the opposite and band-facing points of its centreline. WFF and review art use the same
    integer cell positions and normalized radial vectors. Alpha stays at **170** across the inward half;
    five stops approximate a smoothstep on the outward half, ending at **10**, the watermark's
    six-percent floor rounded to the eight-bit alpha grid. The positions are
    `0 0.5 0.625 0.75 0.875 1`, with alphas `170 170 145 90 35 10`. RGB stays the face's own
    text colour throughout. Review SVGs carry the same coordinates and stop alphas; ambient
    still multiplies the whole border by **140/255**. The official validator accepted this
    gradient and the fractional arc dimensions in format version 2 on the host on
    2026-10-13.

    **Final radial verification 2026-10-13.** The installed APK's embedded XML matched the
    final generated source byte for byte. On `wardpulse_wear_round_api36_1`, `emulator-5554`,
    **384×384**, the lowered cells showed `Tue` · `49°F` · `UV 0`, with all three main arcs and
    legend strips present. All **11** generated border axes were independently checked as
    parallel to their face-to-cell rays, with mirrored side axes. Captured peak RGB readings
    in the outward direction cones were:

    | Cell / derived direction | Outward | Opposed contour |
    | --- | --- | --- |
    | Left / 329.9816° | `23, 28, 26` | `167, 172, 169` |
    | Middle / 0° | `20, 24, 22` | `167, 172, 169` |
    | Right / 30.0184° | `21, 25, 22` | `167, 172, 169` |

    These pixel readings show the outward dissolve and retained opposite contour; they do
    not measure alpha. The ambient capture retained all three occupied cells, values, arcs
    and strips dimmed, at the lowered positions with the same radial fade directions. The
    device was returned to interactive mode.

    **Finite geometry is checked before export.** The native `cellRing` and review
    `upperCells` generators reject non-finite geometry or a non-positive radius, stroke,
    size or distance from the face centre, and reject non-finite gradient coordinates before
    writing the target. Isolated host probes on 2026-10-13 covered a wrong face-centre
    expression, zero distance, infinite or NaN radius and coordinate overflow; all failed
    before a target write. Valid geometry passed, and adding the guards left the generated
    XML and art bytes unchanged. A separate host probe confirmed that the official **1.7.0**
    validator accepted format-version-2 XML with `LinearGradient.endX="NaN"`; schema validation
    alone therefore does not establish finite shader geometry.

    **Initial device verification 2026-10-13, before the lowered placement and radial correction.**
    After `just check-watchface`, the built APK was installed
    and selected on `wardpulse_wear_round_api36_1`, `emulator-5554`, **384×384**. The interactive
    capture showed `Tue` · `50°F` · `UV 0`, the widened lower contours and the three distinct
    outward fades. Directional border peak RGB readings changed as follows:

    | Cell / direction | Before | After |
    | --- | --- | --- |
    | Left / 10:30 | `112, 117, 114` | `23, 28, 25` |
    | Middle / 12:00 | `119, 124, 121` | `21, 24, 22` |
    | Right / 1:30 | `112, 117, 114` | `21, 25, 22` |

    The opposed contours remained visible; antialiasing affects these pixel readings, so they
    do not measure the gradient's alpha. Those readings witness the initial fixed directions,
    not the later radial correction. The main arcs and all three legend strips remained
    present. An ambient capture retained the values, strips and arcs dimmed, with the same
    three fading directions. The device was returned to interactive mode with phone pairing
    still connected. This verifies the installed WFF rendering, without extending the
    historical provider-type checks in rule 8.

    **Geometry correction 2026-10-11 — the ring is inscribed, not inset.** Until today this
    paragraph read *radius 20.25 to 20.75, a quarter of a unit inside the well's edge at 21*,
    and three other places said the same: Non-goals, and the `CELL` comment in each of the two
    generators. All four were wrong the same way. A stroke is centred on its path, so one of
    thickness 1 on a path of diameter 41 runs from radius **20.0 to 21.0**; 20.25 to 20.75 is
    the span of a **half**-unit stroke. That the stroke is centred rather than inset is this
    document's own reading, not an assumption — Ring geometry measured `width=384 thickness=20`
    painting 182.5 to 202.2, the whole nominal centred on `width/2`, for an arc drawn outside a
    `BoundingArc`, which is what a cell's hairline is.

    **Nothing moved in the 2026-10-11 correction.** Its markup was unchanged: it corrected
    the description rather than revising the geometry. The 2026-10-13 border revision above
    later widened the stroke inward. What went with the wrong
    numbers is the reason they carried: there is no quarter-unit of well left clear outside the
    ring, because the ring's outer edge *is* the well's edge.

    The property that reasoning was reaching for survives, and it is the sharper one: the ring
    is **inscribed**. Its outer edge and the well's coincide at 21, so no part of the stroke
    falls outside the well onto the lift, and the two meet the lift on one antialiased curve
    rather than leaving a sliver of well showing beyond the line. The ring is drawn over the
    well and after it — `cellWellFlat`, then `cellRing` — so what it covers is the well's own
    outermost stroke, which on a flat well costs nothing: the lit rim belongs to the graded
    treatment of an **empty** cell, and an empty cell wears no ring.

    It was added because a filled cell had no edge at all. The occluder is `#ff0b0e0c` on a
    lift measured at `19, 24, 22` — a step of eight to eleven levels, which reads as depth
    under a recess but leaves a filled cell as a dark disc on a dark field, so only the glyphs
    registered and the cell itself went unseen. Three widths were rendered and compared on the
    AVD: 1 unit at 40 % of the text colour, the same at 67 %, and 2 units at full strength. The
    first does not read at a glance; the last competes with the text it encloses and with the
    bands behind it. The middle one was the shipped value until the 2026-10-13 inward widening
    and directional fade above. Giving the weather cell the same ring
    is a decision, not a carry-over: without it the face would have three kinds of cell instead
    of two, and the wearer would have to learn which of two dark discs was theirs to fill.

    The third is a radial gradient centred on the cell at radius **26** (previously 25/24/21),
    running
    `#ff0b0e0c #ff0b0e0c #ff242a27` at positions `0.0 0.55 1.0`: opaque, and lightening only
    across the outer 45 % of the radius. It reads because the rim `#242a27` is `36, 42, 39`
    against a surrounding lift of `19, 24, 22`. Branching between the second and third is
    expressible — `WEATHER.IS_AVAILABLE` in a `Condition` — and the left cell has no weather
    under it at all, so its chrome is always the third.

    **`#242a27` is a new colour.** The face's chrome palette was four entries — background
    `#ff0a0d0b`, track `#ff2e3632`, well `#eb0b0e0c`, text `#fff4fbf8` — and this is a fifth.
    Adding to a palette that small deserves its reason stated rather than passed over. The ring
    above adds no sixth: `#aaf4fbf8` is the text colour at a lower alpha, which is why a ring
    reads as the same light as the reading it encloses rather than as a colour of its own.

    The obvious candidate was the track, since the palette already holds it. Two things against
    it. The track means something here: it is the unspent part of a band, the groove an arc runs
    in, and a cell is not a ring — rule 8 refuses a family colour in a cell for the same kind of
    reason. And it is brighter: `#2e3632` is `46, 54, 50`, which against a surround of
    `19, 24, 22` is a step of 27 to 30 levels per channel, where `#242a27` is 17 to 18. A rim at
    the track's contrast stops reading as the lit edge of a dish and starts reading as a drawn
    ring — which is the hairline the paragraph below rejects, arrived at by the back door. That
    last point is arithmetic and reasoning: the track colour was never rendered as a rim, so it
    is an argument, not a reading. `#242a27` sits between the lift's brightest stop, `#18201C` =
    `24, 32, 28`, and the track — a surface catching light just short of the groove's own value.

    **Why the empty cell keeps a gradient rather than an outline.** Three treatments were
    rendered and compared on the AVD for the empty cell: this gradient, a stronger one, and a
    hairline ring. The ring reads most literally — a socket waiting to be filled — and it was
    still not taken here, and the reason has outlived the one first written down. It was
    recorded as *a ring around a cell is a border around a card, which the non-goals refuse*;
    that is no longer the governing argument, because a ring is exactly what a cell holding
    something now wears, and the non-goals carry the exception that says so.

    What survives is the stronger reason, and this revision is what made it legible: a ring and
    a recess now mean opposite things. Putting a ring on an empty cell would say *occupied* of
    a cell that is free, and would leave nothing to say *free* with. The gradient also borrows a
    voice the face already owns, since the lift states depth the same way. Approved from three
    captured states — the shipped default, one cell cleared, and all three cleared.

    **What makes a well read as sunk is the fill, not where it sits** — and not, as this
    revision first claimed, a lift that is brighter at the cells than at the strips. It is not:
    measured on the shipped face in screen pixels at 384, the whole spread across the cells and
    the three strip rows is two levels out of 255, and the gradient reproduces every reading to
    within a level. Position does nothing for depth either way. The fill does all of it, taking
    the lift under a well down by eight to eleven levels per channel, and a step that size needs
    no shadow behind it.

    **The 2026-10-09 arc layout evened the lift too, which was not the point of it.** The lift is a
    radial gradient about `225, 216`, a different centre from the one the cells are arranged
    around, so a cell's distance to it is not its distance to the face centre. The straight row
    stood at 82 for the middle cell and 99.3 for the outer two, reading `20, 26, 23` against
    `19, 24, 22`. On that former arc the three sat at **97.80, 99.02 and 99.02**, and all three read
    **`19, 24, 22`** — measured at screen pixels `192, 101`, `236, 112` and `148, 112`, with the
    face active, confirmed by a control of `24, 32, 28` at the screen centre, the gradient's
    first stop. So those three wells composited to one colour, which the straight row never
    managed. That is a consequence of the former concentric layout, not a new measurement
    of the three-unit lower placement introduced on 2026-10-13.

    The well is **scene chrome drawn behind the slot**, not slot content. Measured 2026-10-09:
    markup placed inside `<Complication type="EMPTY">` does not render. With the slot's type
    confirmed as `EMPTY` in the runtime log, the centre pixel of the cell stayed at the
    background value `19, 24, 22`, against `243, 250, 247` in a filled neighbour. Drawing the
    well outside the slot is also what makes rules 11 and 12 expressible.

    **A filled cell draws a second well of its own, and that one is opaque.** It is `#ff0b0e0c`,
    not the chrome's `#eb0b0e0c`, because it has to cover whatever the chrome put under it.
    Measured 2026-10-09 against deliberately hostile chrome — a cell filled pure `#ffff0000`, so
    any leak lands in one channel — a `#eb0b0e0c` well read `30, 13, 11` at three points inside
    it, against `17, 22, 20` for the bare face just outside it — a darker reading than the
    `19, 24, 22` quoted above because it sits further out in the lift, not a disagreement.
    Alpha `0xeb` is 235/255, so 7.8 % of what
    lies beneath comes through: `0.9216·11 + 0.0784·255 = 30.1`, `0.9216·14 = 12.9`,
    `0.9216·12 = 11.1`, which is the reading. The leak does not only add the colour underneath,
    it drops green and blue *below* the surrounding face, so the cell reads as a warm disc
    rather than a neutral recess. The same markup filled `#ff0b0e0c` read `11, 14, 12` — the
    declared colour exactly, with nothing from beneath. Over a real reading the leak would be
    milder than over red, but it is structural: the colour of a well would depend on what the
    face happened to be drawing under it.

    Splitting the occluder from the chrome costs nothing visible. Composited over that
    `17, 22, 20`, `#eb0b0e0c`
    comes to `11.5, 14.6, 12.7` against the opaque `11, 14, 12` — under a unit per channel,
    derived from the measurements above rather than measured as a pair. That is also why the
    graded well above can be opaque without looking different from the translucent one: at these
    luminances the lift contributes less than a level. The strips keep `#eb0b0e0c`: nothing lies
    beneath them but the lift, and letting it through is the point.

11. **The default weather is the face's own chrome, not a complication.** WFF carries a built-in
    `WEATHER.*` data source — `WEATHER.TEMPERATURE`, `WEATHER.UV_INDEX`, `WEATHER.CONDITION`,
    `WEATHER.IS_AVAILABLE` and the rest — available in format version 2, the version this face
    declares. It is read in an expression like any clock field and **costs no complication
    slot**. The face draws the temperature beneath the middle cell and the UV index beneath the
    right one, as scene chrome declared in `Scene` ahead of the first `ComplicationSlot`, which
    is what puts it under every slot's content. Nothing is declared beneath the left cell, so
    its chrome is the graded well of rule 10 whenever the wearer clears it.

    **Face-local Temperature revision 2026-11-01.** The owner's 2026-10-30 decision adds one
    **Temperature** choice to the existing system watch-face editor: **Auto**, **Celsius (°C)**
    and **Fahrenheit (°F)**, default **Auto**. The WFF2 `ListConfiguration` uses string option
    IDs `auto`, `celsius` and `fahrenheit`; these are distinct from the numeric weather-unit
    enum. Labels belong to the canonical Android strings shared by Legacy and Push. No phone
    preference, sync field, weather service or additional complication slot is involved.

    Auto preserves the source integer and scale: unit **1** draws `%s°C`, unit **2** draws
    `%s°F`. A matching explicit selection also preserves that integer. Only a known opposite
    unit converts the original `[WEATHER.TEMPERATURE]`: Celsius to Fahrenheit uses
    `round(t * 9 / 5 + 32)`; Fahrenheit to Celsius uses `round((t - 32) * 5 / 9)`. The display
    stays at whole degrees with the explicit target suffix, reflecting the integer precision
    supplied by WEATHER. Never convert an already displayed value or infer a unit from locale,
    preview text, bare degrees or a plausible number. Unsupported source units keep the original
    `%s°` fallback even with an explicit selection; unavailable weather keeps the existing bare
    recess. The existing 18/14/12 branches use the **displayed** integer: 14 below zero or at
    least 100, with 12 taking precedence at −100 or below, otherwise 18. Geometry, centring,
    fonts, colours and ambient treatment stay unchanged.

    This choice controls only built-in weather chrome. An assigned upper-cell provider keeps
    its verbatim `COMPLICATION.TEXT`, existing taps and opaque well covering that chrome;
    Temperature neither configures nor converts the provider. Clearing the middle assignment
    reveals the built-in reading again when weather is available. The illustrative `18°C`
    review art remains an Auto example with a known Celsius source, not a Celsius default.

    `check_temperature` in `tools/check-watchface-structure.py`, invoked by `assertConditionTrees`
    in `tools/render-watchface.mjs`, exercises the emitted list, canonical labels, conditions,
    parameters, numerical/rounding/size boundaries, unknown/unavailable fallback, provider text,
    opaque wells and eight-slot ownership. This is source regression coverage, not native proof
    of every fallback or numerical boundary.

    **Scoped native acceptance, 2026-11-01.** On the canonical 384×384 round API36 emulator,
    installed Legacy APK `6fc79b39…` retained instance `f78b616d…`. The system editor saved
    Celsius and Fahrenheit across reopening; separate live frames showed `57°F`, converted
    `14°C`, then `57°F`. Auto was restored and the live face again showed `57°F`. The editor's
    fixed `25°C`/`77°F` preview is separate from live weather; these observations are not a
    simultaneous exact weather cohort. The selection applies only to built-in WEATHER;
    external opaque-provider `7°` was not natively retested in this session. The final
    read-only eight-slot bracket passed with the expected restored configuration and same
    instance. Full HOST WFF/Wear gates passed. Native negative/extreme values and unsupported/
    unavailable-source branches remain unobserved; their coverage above is source-only.
    Physical/OEM confirmation remains deferred, and earlier Fahrenheit observations below
    retain their dated scope.

    So the default costs the wearer nothing. All three cells stay theirs: the moment one is
    filled, its opaque well covers the chrome under it and that reading is gone; empty it again
    and the reading comes back. Measured 2026-10-09 — a cell bound to `DAY_OF_WEEK` drew `Tue`
    on its own well with the chrome beneath invisible, while the two cells left `EMPTY` showed
    their chrome through, carrying `[WEATHER.TEMPERATURE]` and `[WEATHER.UV_INDEX]`.

    There is no other way to make weather a default. `defaultProviderType` is a closed
    enumeration — `APP_SHORTCUT, DATE, DAY_AND_DATE, DAY_OF_WEEK, EMPTY, FAVORITE_CONTACT,
    HEART_RATE, NEXT_EVENT, STEP_COUNT, SUNRISE_SUNSET, TIME_AND_DATE,
    UNREAD_NOTIFICATION_COUNT, WATCH_BATTERY, WORLD_CLOCK` — with no weather entry, so a face
    cannot ship a cell bound to weather even where a weather provider is installed. On the round
    AVD none of the 23 installed providers is one, although the package
    `com.google.android.wearable.dwf.weather` is present.

    **What a real reading looks like has not been seen.** The AVD has no weather provider, and
    on it `[WEATHER.TEMPERATURE]` rendered an empty string while `[WEATHER.UV_INDEX]` rendered
    `0`. The spike proves that the expressions evaluate and that the chrome sits in the right
    layer; it proves nothing about the format of a temperature, its unit, or whether that unit
    follows the wearer's setting. The face reads `WEATHER.IS_AVAILABLE` and falls back to the
    graded well of rule 10, because a cell reading `0` or nothing at all is worse than a cell
    that is plainly empty — and that branch has not run against real data either. This revision
    fixes the rules; the readings they will show are measured when the generator changes.

    **Reading revision 2026-10-12 — a weather cell says what it is showing.** The generator
    changed, so the paragraph above is answered. A real reading was seen on `emulator-5554`:
    the cells read **`51`** and **`0`**, and the owner could not tell what either was — a
    number with no unit, and a number with no subject.

    **The source-unit baseline, retained by Auto.** Locale and the earlier bare `51` alone
    cannot establish a source unit. The format carries
    `WEATHER.TEMPERATURE_UNIT`, an integer enum: **1 is Celsius and 2 is Fahrenheit**, available
    in format version 2. The face selects `C` or `F` from that enum instead of printing the
    integer or inferring a scale from locale. The value already follows the wearer's unit, so
    Auto applies no conversion. These meanings are specified in the official
    [Android data-source reference](https://developer.android.com/reference/wear-os/wff/common/attributes/source-type).

    **The face drew the marks nowhere, and the design had shown them all along.** From
    2026-10-09 until this revision both cells templated the bare expression, `%s`, while the
    Primary baseline board, the shipped picker preview and rule 7's own worked example all drew
    `18°` and `UV 7`. This is the face catching up with its own document; only the scale below
    is a new decision.

    **Temperature-scale revision 2026-10-13 — the owner chose `51°F`.** The degree-only form
    adopted on 2026-10-12 left the scale ambiguous. The owner explicitly selected an added
    scale after a measurement on `emulator-5554`: `51°` occupied about **19.9 units** of ink in
    the 37-unit box, while the existing `UV 0` occupied **28.1**. The added `F` was estimated
    to bring `51°F` to about 27 units; that is an estimate, not a measurement of the new
    reading. The face now draws `%s°C` for unit 1 and `%s°F` for unit 2. An unsupported unit
    falls back to `%s°`, keeping the degree sign without guessing a scale. Missing weather
    still draws the empty recess rather than a label.

    The primary board and its generated previews show `18°C`, the weather-available Celsius
    example. In Auto, the scale follows the weather source rather than the preview. Verified after
    installation on **2026-10-13**, before the three-unit lowering, on
    `wardpulse_wear_round_api36_1`, `emulator-5554`,
    **384×384**: the live reading was **`50°F`**, fully visible. Its bright ink bounds were
    `(180, 97)` to `(203, 105)` pixels, a width of **26.95 design units** inside the 37-unit
    box; its midpoint was **191.5 px** against the cell's axis at **192 px**. Only this current
    Fahrenheit reading was measured. Celsius, negative temperatures, three-digit temperatures
    and `UV 11` remain unmeasured on the device.

    **Lowered-position verification 2026-10-13.** The final installed face showed **`49°F`**
    on the same round AVD at **384×384**. Its bright ink bounds were `(180, 99)` to `(203, 107)`
    pixels, again **26.95 design units** wide in the 37-unit box, with midpoint **191.5 px**
    against the cell's axis at **192 px**. The prior `50°F` bounds above belong to the earlier
    placement. These two readings confirm those two Fahrenheit labels only; Celsius, negative
    or three-digit temperatures and `UV 11` remain device checks.

    **The UV index takes its name in front — `UV 7`**, the board's form, because a bare `0` is
    a number with no subject at all and the cell is the only place the subject could go.

    **Complete-label centring, historical 2026-10-13 geometry.** That revision gave the
    temperature the same unshifted `x=2` box as the UV reading. The former offset
    measured half a degree sign, not half a degree sign plus a scale letter, and retaining it
    would not preserve numeric centring. Centre the complete label instead, preserving room
    on both sides; that revision removed the obsolete correction from the generator. Current
    geometry retains complete-label centring in the **46×24 box at (3,14)** from rule 7;
    the `x=2` box and the 37-unit device readings above are historical.

    **The shift was there without its mark.** `CELL_MARK_SHIFT` put the temperature's box at
    `x=4` from the day the cells shipped, correcting for a degree sign the template never drew,
    so the bare digits sat about 1.5 units right of the axis — inside a screen pixel at 384, and
    not what anyone noticed. Drawing the mark on 2026-10-12 made that existing two-unit shift
    correct for the degree-only reading. The 2026-10-13 revision retires it for the suffixed
    label, as described above.

    **Observable for the first time, and still unsettled.** With the mark drawn, the shift has
    an effect something can be measured against, and `Mon` · `51°` · `UV 0` was read on
    `emulator-5554`. Ink centres against their cells' axes: the `51` digits at −2.3 units, the
    whole `51°` string at +1.2, and `UV 0` — centred whole, taking no shift — at **−1.0**. That
    last is the control, so about a unit of every figure here is the method rather than the
    layout: an ink box is not an advance box and a threshold eats antialiased edges. The digits
    sit roughly 1.3 units further left than the control explains, which is **not** evidence the
    shift is too small: `1` carries wide side bearings, so the ink of `51` sits left inside its
    own advance box wherever that box is. A symmetric pair — `88°` — would separate the two, and
    the weather is not ours to choose. This is evidence for the former degree-only rule;
    it does not measure the complete-label centring introduced on 2026-10-13.

    **Widths remain device-dependent.** Measured on the host on 2026-10-13 with the review
    font, Noto Sans Bold at size 14, advances were `18°C` **30.94**, `51°F` **29.70**,
    `-10°F` **34.22**, and `-12°C` **35.45** units, all inside the 37-unit box. `101°F` was
    **37.72**, just beyond it, and `UV 11` was **39.34**. These are host-font advances, not
    device ink measurements: the face uses `SYNC_TO_DEVICE`, so those host advances prove
    neither a live overflow nor a live fit. The separate device readings above confirm only
    `50°F` before lowering and `49°F` after it. Those measurements do not validate the new
    18/14/12 weather branches in the operative readability revision. Negative/three-digit temperatures
    and `UV 11` remain device checks, with explicit ellipsis for unexpectedly verbose values.

12. **Ambient: the wells stay, the values dim.** Three things make up a cell across its two
    states — a filled one has a value over an occluder, an empty one has a recess and whatever
    chrome shows on it — and ambient takes each by the job it does, not by what it is called.

    **The value dims.** A complication in a filled cell, or the weather reading showing through
    an empty one, dims with the bands in the proportion the face already uses — ring type goes
    `alpha="115"` to `63` as the arcs go 255 to 140. It dims rather than switching off because
    dropping it would lose the reading outright, and nothing else on the face carries it. The
    legend strips were the counter-example when this rule was first written, dropped on the
    reasoning that a strip restates its band; since **2026-10-10** they dim too, because that
    reasoning covered their percent and nothing else they print. They dim one step further, to
    90, and not because they cost more to light — a legend row and an occupied cell are the
    same lit area to within a few pixels. A cell is a token read at a glance and the legend is
    three lines of running text, so the step puts the legend second in the reading order rather
    than second in brightness for its own sake (Ambient).

    **The occluder stays, and it has to.** The opaque well a filled cell draws inside its own
    slot (rule 10) is not chrome; it is the one thing standing between the complication and the
    chrome under it, and nothing else can do that job — the chrome is declared outside the slot,
    and no expression in the scene can ask whether a slot is filled. Switch it off in ambient
    and the weather reading comes back out from under the complication, with two values drawn
    over each other in the same cell, which is exactly what rule 11 says a filled cell puts
    an end to.

    **The recess stays too**, in both of the forms rule 10 gives it, and this overturns the rule
    as this revision first wrote it, which had every well switch off with the strips. A well
    here is not a lit element but a darkening: `#eb0b0e0c` over a lift measured at `19, 24, 22`
    composites to about `12, 15, 13`, so switching it off in ambient would make that patch
    *brighter*, which is the reverse of what switching anything off in ambient is for. The
    graded well is darker still across the middle and only lifts at its rim, so the same holds
    for it. That was an inference when this rule was written and is now a reading: measured
    2026-10-10 at an equal radius from the lift's centre, a cell's well sits at `4, 6, 5` in
    ambient against a lift of `8, 10, 9`, and at `11, 14, 12` against `19, 24, 22` in active
    mode — filled and empty alike, four levels down in ambient and eight to ten in active, with
    the sign never turning. Nor could it turn: the system dims the assembled frame by close to
    one factor, the well going 13 to 5 and the lift 22 to 9, and multiplying both sides of a
    ratio cannot invert it.

    The strips are no counter-example either, and since **2026-10-10** they are not even a
    contrast: a row dims with its well rather than going, and a strip's well darkens the lift
    exactly as a cell's does — at alpha 140 it reads `6, 8, 7` against a lift held at
    `8, 11, 10` on the same radius. With the row switched off it read the lift itself,
    `8, 10, 9`, because nothing was drawn there at all. A cell is drawn in both modes, filled
    or not.

    **The ring dims, because a ring is the one part of a cell that lights.** Everything above
    turns on a well being a darkening, and the border of rule 10 is the opposite: it adds
    light where there was none. Leaving it at full strength would make the brightest thing on
    an ambient face the outline of a cell rather than anything a cell is saying, in the one
    mode where lit pixels are kept few. So it goes with the value it encloses, in the arcs' own
    proportion, 255 to 140 — the ring is not exempt from the division this rule draws, it falls
    on the other side of it from the well.

    The exact dimmed level and the square-screen layout are to be measured when the generator
    changes; this revision fixes the rule, not the number.

13. **One WardPulse metric belongs in a cell: sync freshness.** A stale face lies silently —
    every arc keeps its last value and nothing says when that was. Nothing else in this language
    says it, and `StatusComplicationDataSourceService` already composes it. The summary could
    also feed spend today, credits remaining, an alert count, or the time to the next window
    reset; those are things a cell *may* hold, offered to the wearer like any other provider.
    This revision commits the face to none of them.

14. **The recovery marker is not part of this design.** It remains the open question recorded in
    `docs/DEVELOPMENT_PLAN.md` Phase 15, and the face keeps saying it in its own language: an
    exhausted selected ring stays at zero, so recovery restores its coloured arc. Giving the cells to the wearer does
    not reserve one for it.

## Ring geometry (revised 2026-08-02)

Numbers here are **measured off a device screenshot**, never read off `watchface.xml`. Two
things the file does not say:

- WFF draws a band at roughly **half the nominal `thickness`** — `thickness="25"` rendered a
  10 px band on a 384 px round watch, which is why arcs read thinner than every review board.
  Corrected **2026-10-09**: this was never a property of WFF. It was the slot's `BoundingArc`,
  which the three ring slots no longer carry; each band now declares the 20 units it paints.
  See *The cause of the half-nominal band* and *The declaration was restated* below;
- `width` sets the band's **outer edge** on a `BoundingArc`, and twice the **centre line** on an
  arc drawn inside a slot. The two are not the same number, and conflating them is what made the
  clip cut exactly half.

Every number in this document is a **design unit**: the 450-unit language the generator is
written in, the boards are drawn in, and the shipped `watchface.xml` declares as its canvas —
one number throughout, no conversion. The canvas is also the resolution WFF renders at before
scaling to the screen, so raising it costs antialiasing on every edge of the face; see Ring
type texture for the one feature that tempted it and why it no longer does.

| | Value |
|---|---|
| Declared `thickness` | 20 since **2026-10-09**; 40 before it, when a `BoundingArc` cut half away |
| Declared `width` | 384 / 336 / 288 — twice the centre line, not the outer edge |
| Rendered band | 20.2 units (17 px at 384) — unchanged by the restatement |
| Ring pitch (outer edge to outer edge) | 24 units |
| Outer edges, outer to inner | 202 / 178 / 154 — three current bands |
| Gap between bands | 3.5–4.8 units |
| Strip clearance to the inner band | **2.0730** units calculated for the current 132×26 target; historical 120×26 calculation4.9745, older 104×22 calculation8.50 and measured8.4 |

Widening the band alone is not enough: at the original 18-unit pitch a thickness of 40 made
neighbouring bands touch, and a first attempt at pitch 21 still left a 0.8-unit hairline
because the band renders 20.2, not the 18.8 a 0.44 factor predicted. Measure after every
change — the factor is not exact.

**A `ROUND` cap reaches past the angle it is drawn to, so the melt is inset by one.** Measured
2026-08-16: a band declaring `thickness="40"` lost **6.42° per end**, half its nominal thickness
laid along the arc, so a ring at 4% used showed a 3° gap instead of 14° and read as closed. The
face draws the melt short by one cap at each end (`capDegrees` in `tools/render-watchface.mjs`).

Two things in that note need correcting, and both were found on 2026-10-09 rather than
remeasured. The reading was recorded as *"at radius 159"*, and no ring has that radius — the
diameters in `RINGS` were 404 / 356 / 308 at `df3cdae`, as they are now. 6.42° of a 20-unit
reach belongs to **radius 178**, ring 102 under its old declaration, which is also what
`capDegrees` computed for that ring. The radius in the original note matches nothing in the
geometry of its own commit and is recorded here as an error in the note, not a measurement to
preserve. The same note's *"at 50% used the gap measures 180.3° against a true 179.95°"* is a
**historical reading of the clipped geometry** and the face no longer draws that way; it is kept
for the record, like the 2026-08-16 marker reading further down, and has not been remeasured —
no ring on the emulator currently sits near 50%.

The claim that *"review art carries the same inset, which is why the boards and the watch still
agree"* was written in good faith, and was **false from the day it was written until
2026-10-09**.
Review art has always drawn the measured model — `tools/render-watch-ring-designs.mjs` sets its
own `outer = size * 0.4264`, `gap = size * 0.0084` and `thickness = size * 0.0449`, which is
centre line 191.88 and a 20.2-unit band, with a comment saying so — while the face declared 40
under a clip and inset its melt by a cap of 20 units instead of 10. The boards drew the true
remainder; the watch drew it short. Nothing caught it: `just check-designs` compares the art
against its own generator, never against the face. The two agree as of the melt-length
correction below, to within the 0.1 unit between the art's measured 20.2 and the face's
declared 20.

**Historical clock measurements; superseded by the upward-digit 2026-10-27 target.**
At that measured baseline, `TimeText` used `y=160, height=90`, its centre 20 above the canvas centre;
measured 2026-08-13, WFF rendered the digits **21.7** up. Review art then adopted that
measured lift; the historical combined y152 revision lifted it another 8. The subsequent
centred review art used `TIME_LIFT=0`.
The initial nominal y182 was a 30-unit shift from y152, projecting a centre near 225.3 from
that older reading. The matched 2026-10-27 six-frame measurement above instead found
226.171875, leading to the historical y181 calibration and Source6397 record above.
Current review art uses per-mode baselines with enlarged type and the approved active translation;
the upward-digit revision records historical Round calibration/corpus, not acceptance of the new
active placement. Projections do not prove board/device agreement or every time string's optical centre.

**Clock colon spacing stays device-defined (revision 2026-10-01).** On the `emulator-5554`
screenshot used for the 2026-09-26 decision, `03:24` at 384×384 produced these bright-pixel
spans:

| Glyph | `0` | `3` | `:` | `2` | `4` |
|---|---:|---:|---:|---:|---:|
| Columns | 118–145 | 151–180 | 187–195 | 203–231 | 237–266 |
| Width | 28 | 30 | 9 | 29 | 30 |

The four inter-glyph gaps were 5 / 6 / 7 / 5 px, so the colon had 6 px on its left and 7 px
on its right. Its centre was column 191 against 192 for the full time's bright-pixel span: one
screen pixel left, or `450 / 384 = 1.17`, approximately **1.2 design units**. The digit widths
were 28 / 30 / 29 / 30, so the device font is proportional rather than tabular and the
imbalance changes with the value; `12:24` will not lay out like `03:24`.

Both active and ambient modes intentionally keep one complete `TimeText` with `format="hh:mm"`,
`align="CENTER"`, and `family="SYNC_TO_DEVICE"`. The generator centres each whole string, but
the device's clock font owns the spacing inside it. The one-pixel imbalance is accepted and the
layout stays unchanged. Baking tabular digits would pin the metrics—the ring-type texture
already uses baked Noto Sans Bold—but would abandon the intentionally device-synced clock font.
Splitting hours, colon, and minutes would use three elements per mode, six total, and would
centre their boxes rather than their ink because the system colon metrics remain unknown.

**Historical full-ring repair (revision 2026-08-17).** The cap inset above is what
makes a small melt visible, but at `usedPercent == 0` there is no melt to inset and the inset
leaves the ring open anyway: measured on the paired band, a seam of about **1°** at 12, four
pixels wide at that radius. A literal `360` sweep collapsed to a `ROUND` tip on the tested
watch; `359.9` preserves that dated workaround. The repair removed the start transform at
maximum but retained the partial end inset. The contemporary claim that its two caps closed
smoothly was not sustained by the later exact-full nick. The board's `ringArc` full branch
uses an SVG circle (`round-3-plan-untouched.svg`); that is intended appearance, not evidence
of native WFF continuity.

**Exact-full construction revision 2026-10-26 — native acceptance pending.** The original
physical 466-pixel orange/100% photo records a visible nick without measuring its ranged
Float. A later clean Round 384 capture and joined installed-resource/service/data receipts
bind one ordinary outer Claude case to actual `VALUE=100`, `MAX=100` and the previous
canonical XML. The mixed compositor frame is excluded as a clean repeated witness. These
observations establish an actual full-ring defect; they do not isolate its exclusive cause.

`bandArcs` previously drew exact full from 0 to `359.9 - capDegrees`: 356.92° on the ordinary
outer band. Ideal circular-cap geometry predicts an outer-edge indentation of about 1.50
units there and 0.77–0.79 on the halves. The chosen first repair removes that end inset
only for actual `VALUE >= MAX`. One `Arc` now runs from 0 to 359.9 with the existing
`ROUND` `WeightedStroke`, live family ColorRamp and alpha 255 / ambient 140. It adds no
path junction, offset, texture or overlapping drawing element. Keeping both endpoints in
one path avoids introducing a second independently blended stroke; native brightness still
requires measurement.

For radius `r`, half-thickness `h` and half of the undrawn angle `a`, the ideal cap union
at the gap midpoint covers radial interval
`r*cos(a) ± sqrt(h*h - (r*sin(a))²)`. With the retained 0.1° gap, the maximum ideal edge
deficit across all nine geometries is under **0.004 design units**. The caps remain inside
the original annulus; this is an analytical bound, not a pixel measurement or permission
for a visible nick. `assertFullRing` checks the generated full path's centered radial
envelope, family source and ambient alpha. `assertNearExhaustedArcs` now covers ordinary
384/336/288 at thickness20, inner 374/326/278 and outer 394/346/298 at thickness10, retaining
both cutoff invariants and proportional positive partials. Both outer-half services retain
their three TITLE branches; their shared round-edged clip is checked to contain every
half's complete envelope, including the join. Ordinal1/innermost remains unreachable.

Actual 99.9 and 99.6 remaining may round to a `100%` label and still take the proportional
partial branch. Double-to-Float conversion, min/max, integer labels, cap compensation,
clockwise-from-12 melt, exact-zero gray tracks and unknown/NoData absence remain unchanged.
The review-art generator already expresses the intended closed annulus, so its exports do
not change with this runtime construction repair.

No candidate native continuity pass is recorded by this revision. HOST acceptance remains
pending: bind installed resources and actual Float/MAX; review two settled original frames
per controlled scene in actual INTERACTIVE and AMBIENT on small round and nonround targets;
measure the complete annulus, both edges and brightness. Inherited physical 466 acceptance
also remains pending while that target is unavailable. Safe debug-only Mock delivery,
writer isolation and preservation/restoration of stored and derived state belong to HOST
after Runner completion and retirement; the synthetic scene data does not prove those steps
or establish a signed-release physical delivery route.

**A positive remainder below the two-cap cutoff stays visible (revision 2026-10-01).** The
owner reproduced a face with strips reading `2%`, `69%`, and `94%` on `emulator-5554` on
2026-09-26: the 2% strip still had data, but its ring showed only the track. The inset above
had consumed more than that ring's remaining centreline. Its cutoff is derived per ring as
`2 * capDegrees(width, thickness) / 359.9`, not chosen by eye.

The arguments are the band's **declared** `width` and `thickness`, which is not the `diameter`
in `RINGS` — that entry is twice the band's outer edge and still reads 404 / 356 / 308. What
changed on 2026-10-09 is what reaches `capDegrees`: the declaration now carries the 20 units the
band paints rather than 40 under a clip, so the cap halves and every cutoff halves with it.

| Ring | `RINGS` diameter | Declared `width` | Cap | Remaining cutoff |
|---|---:|---:|---:|---:|
| 101 Today | 404 | 384 | 2.98° | 1.66% |
| 102 Week | 356 | 336 | 3.41° | 1.89% |
| 105 Ring3 | 308 | 288 | 3.98° | 2.21% |

Until that revision the same column read 3.15% / 3.58% / 4.13%, computed from a cap of 5.67° /
6.44° / 7.44°. Those are the figures of the clipped geometry and no longer describe the face.
Both melt branches still deliver the true remainder on either side of the line, so only the
switching point moved; `assertNearExhaustedArcs` asserts that continuity on every render.

At or below its cutoff, a positive remainder keeps its proportional centreline without the
two cap insets and uses straight ends. Above the cutoff the measured round-cap inset geometry
is unchanged. This deliberately does not impose a minimum sweep: doing so would overstate
remaining capacity at the edge of the scale. This low-positive revision left the then-existing
zero-spend/full-ring branch, band thickness, split halves, and slots unchanged; the later
2026-10-26 revision above changes only the full path's end inset. Review art mirrors the rule in
`round-3-plan-near-exhausted.svg` with the observed `2%`, `69%`, and `94%` values.

**Measured correction 2026-10-06.** On the owner's 384×384 capture, a 1% remainder on Ring3
occupied 5.06% of the circumference; the previous below-cutoff branch left both round caps
outside the proportional centreline, adding one band thickness to the visible arc. A straight
cap removes that overstatement: the visible arc now equals the true remainder, and it meets the
ordinary round-cap branch continuously at the cutoff.

**Halves of a band, measured 2026-08-13.** A split band (see Split band) is two arcs inside one
ring slot, and the numbers that work are **centre lines at `outer − 5` and `outer − 15`, both at
`thickness="10"`** — 197 and 187 on the outermost band, 173 and 163 on the next, 149 and 139 on
the third, since a pair can land on any of them. In the markup that is `width="394"` and
`width="374"` for the outermost: **twice the centre line**, not twice the outer edge as the
whole-band rule above would suggest. Getting that translation wrong is what the first two
probes did, and it fails silently — the halves land on top of each other and read as one band.
Measured on the round AVD at 384 on the outermost: the halves paint 182.5–192.25 and
192.25–202.25, **9.75 units each** (8.3 px),
meeting with no gap and no overlap, identical in all four diagonal breaks. All three bands were
measured the same way when the split shipped (2026-08-16), moving one pair from band to band:
centres **187.0 / 197.1**, **163.2 / 173.4** and **139.4 / 149.0** against the 187/197, 163/173
and 139/149 the offsets predict, every half 9.1–9.5 units, no gap at the seam. The offsets hold
on every band, and so does the shared slot that draws the outer ones.

**A `BoundingArc` takes its outer edge in `width`, unlike the arcs it clips.** The shared slot
that draws outer halves spans every band, and setting its `width` to twice the centre line —
the rule for arcs *inside* a slot — clipped the outermost half at its own centre, leaving a
half-width arc that looked like a rendering bug. `width="414" thickness="68"` is the span from
207 down to 139, and only then does the clip stay out of the way.

Those numbers are not derived from the two rules above, and they cannot be: **an arc behaves
differently inside a complication slot than outside one**, and neither behaviour was predicted
by the other. All four readings, same device, same session:

| Where | Markup | Painted |
|---|---|---|
| Scene level, no slot | `width=404 thickness=40` | 201.75–221.5 — 19.75 units, inner edge at `width/2`, growing outward |
| Ring slot (shipped) | `width=404 thickness=40` | 181.6–202.1 — 20.5 units by angular coverage, which is the locked 20.2 plus antialias; outer edge at `width/2`, growing inward |
| Ring slot | `width=384 thickness=20` | 182.5–202.2 — 19.7 units, i.e. the whole nominal, centred on `width/2` |
| Ring slot | `width=394` / `374`, `thickness=10` | 192.25–202.25 and 182.5–192.25 — 9.75 each |

The half-nominal rule at the top of this section holds for the first row and is what the
shipped band was fitted to; rows three and four paint the full nominal instead.

**The cause of the half-nominal band, measured 2026-10-09.** The `BoundingArc` was the obvious
suspect and this document kept it as a guess. It is now the measurement. The same face was
rendered twice, changing nothing but the bounding element on the five arc slots:

| Slot bound | Declared | Painted |
|---|---|---|
| `BoundingArc` | `thickness="40"` | 20.1 / 19.9 / 20.5 |
| full-canvas `BoundingBox` | `thickness="40"` | 40.4 / 44.3 |

So a `BoundingArc` does two things to the slot it bounds: it clips the slot's drawing to its own
band, and it halves the stroke. The Surfaces table has asserted the clipping since the strips
got their own `BoundingBox` slots; the halving is what this reading adds, and the two are the
same mechanism.

This matters beyond bookkeeping, because the upper cells are paid for by folding each legend
strip into its own band's slot, and a strip cannot be drawn inside a `BoundingArc` — it lies off
the band and is clipped away. The folded face therefore bounds its band slots with a full-canvas
`BoundingBox`, and the **declared** thickness has to fall to keep the locked 20.2-unit rendered
band. The rendered band is the constant; the declaration follows it and must be re-measured on
the device when the generator changes, exactly as every other number in this section was. The
40.4 and 44.3 above are one declaration measured on two bands, and that spread is itself a
reason not to predict the new declaration arithmetically.

**Without the clip, a band both doubles and re-centres.** On the 2026-10-09 spike the inner
band painted from design radius **134 to 175**, against 133.8 to 154 for the shipped band at
the same `width`. So dropping the `BoundingArc` moves rows two and three of the table above
into each other: the stroke goes from 20.2 units with `width/2` as its outer edge to the full
nominal centred on `width/2`, and the band grows outward over the gap and its neighbour. On the
spike that read as a grey mass filling the middle of the face.

Where those figures come from, since two of them are not the subtraction a reader would try.
Two scans of the same capture — one along a single row, one radial at four angles clear of the
coloured arcs and the text — read the inner edge at 134.8 and 133.9, and the outer at 175.2 and
174.4. The edges are therefore quoted whole: most of a unit separates two reads of one
antialiased edge, and the method does not carry tenths. The **span** is each scan's own
difference, **40.4 and 40.5** units, not the difference of the rounded edges, and it agrees with
the 40.4 this section's table measures for a declaration of 40 under a full-canvas box. The
**centre**, 154, is the slot's `width/2` and not a reading at all; the two scans' midpoints
bracket it at 155.0 and 154.2. The same radial scan reads the shipped band at 133.9 to 154.1,
against the locked 133.8 and 154.

Both halves of that are recoverable in the declaration, and the rule is one this document
already records for arcs drawn inside a slot: give `width` **twice the centre line** and
`thickness` the true band. Keeping each band exactly where it is today was therefore a generator
change rather than a visual compromise, and it was re-measured on the device rather than
derived — the 40.4 and 44.3 above are one declaration reading differently on two bands, which
is why no arithmetic was trusted here. The restatement and its readings are below.

**The ring-type textures need no clip and are unaffected.** They are square files, but their ink
is not: measured by radial alpha profile, `ring3_type_day.png` carries ink only between radius
135 and 153 and is fully transparent inside 135, and `ring1_type_month.png` only between 183 and
201. Each texture already carries its own geometry, which is what being baked per ring and
period means. They survive the change as long as the bands stay where they are; they would have
to be redrawn only if a band moved.

**The declaration was restated on 2026-10-09, and the melt grew.** The three ring slots gave up
their `BoundingArc` for a full-canvas `BoundingBox`, and each band now declares what it paints:

| Slot | Was, inside a `BoundingArc` | Is, unclipped | Paints |
|---|---|---|---|
| 101 Today | `width=404 thickness=40` | `width=384 thickness=20` | 182 – 202 |
| 102 Week | `width=356 thickness=40` | `width=336 thickness=20` | 158 – 178 |
| 105 Ring3 | `width=308 thickness=40` | `width=288 thickness=20` | 134 – 154 |

The rule is `width = diameter - thickness`, because a `RINGS` diameter is twice the band's outer
edge while an arc inside a slot takes twice its centre line. The nine textures came out of the
regeneration byte-identical, as the paragraph above predicted.

Why the clip took exactly half is now plain rather than measured: its outer edge was `diameter /
2`, which is precisely where the stroke's own centre line sat, so the outer half of every stroke
fell outside the clip and the inner half survived. Nothing about WFF was involved.

**A clipped `ROUND` cap is a wedge, and the melt was drawn short because of it.** A clip cuts
across a band, never along it, so it never shortened a cap in the direction the cap actually
reaches. What it did was shave the cap's disc radially: a 40-unit stroke ends in a disc of
radius 20, and keeping only the half inside the band left a wedge that reached its full 20 units
at the band's **outer edge** and tapered to nothing at the inner one. On the centre line it
reached `sqrt(20² - 10²)` = 17.3 units, not 20 — and the melt was inset by the full 20. So the
visible arc fell short everywhere except the band's outer rim, by 2.7 units of arc length on
the centre line, which is a different angle on each ring:

| Ring | Centre line | 2.7 units, predicted shortfall per end |
|---|---:|---:|
| 101 Today | 192 | 0.81° |
| 102 Week | 168 | 0.92° |
| 105 Ring3 | 144 | 1.07° |

The measurement comes in under that: ring 102 gained 1.45° in total, so **0.73° per end**
against the model's 0.92°. The model is the upper bound and the reading is the fact. They part
company because a wedge tapers to a point, and its last fraction of a unit covers a pixel only
partly — the colour threshold a scan uses still finds that pixel, so the measured end sits a
little past the geometric one. Only ring 102 was measurable: the other two bands take branches
that use no round cap, which is also why neither moved.

Measured on `emulator-5554`, tangential scan along each band's centre line, searching for the
family colour, before and after the restatement on the same three rings:

| Ring | Before | After | True remainder |
|---|---|---|---|
| 101 Today, 100% | 0.95° – 359.00° | unchanged | — |
| 102 Week, 36% | 231.05° – 359.15°, span **128.10°** | 230.40° – 359.95°, span **129.55°** | **129.56°** |
| 105 Ring3, 1% | 355.90° – 359.90° | unchanged | — |

An independent scan of the same two captures read 127.90° and 129.35° for ring 102 — the two
differ by about 0.2° on where an antialiased end begins, which is the method's own precision,
and agree on the 1.45° the melt gained. Rings 101 and 105 do not move because neither uses a
round cap: a band with nothing spent takes the closed branch, and one below the two-cap cutoff
takes the straight-ended branch.

So this is not a change the face absorbs invisibly. A partially spent band now shows the
remainder it always meant to, and the boards have been showing that all along.

The strip stack was originally resized with the rings — 88x18 boxes stepping 21 units from
y=283, a stack pitch of its own that has nothing to do with the 24-unit ring pitch. The previous 96x20
stack reached radius 142.3 and would have cut into the widened inner band.

Only three strips render, matching the three-ring cap. As of **2026-09-16**, the former fourth
**ring** slot (106) carries the first split's outer half, and the former fourth **strip** slot
(109) carries the second split's outer half. Both reach all three radii and select the band by
its outside-counted `TITLE`. The far-end marker now lives inside each strip slot, selected by
its outer-pool token, with the same declared 3x14 arc and right-edge position. Nothing in the
eight-slot budget is spare now.

As of **2026-10-09** the strips no longer hold slots of their own: each one is drawn by its own
band's slot at a fixed row, and the three slots this frees are spent on upper cells under new
ids (Upper cells, rule 2). That revision retained the 88x18 boxes at 21-unit pitch from
`y=283`, but fixed which slot paints which row rather than following the payload index.
The initial **2026-10-25** readability revision used104×22 at23-unit pitch fromy271.
The operative target is **132×26**, pitch **27** from **y=259**, preserving the
same bottom339, bottom anchoring and all ring geometry.

The historical **2026-08-16** reading is the "before": the shared marker landed at x 265–268 of
the 181–269 strip, on the paired row only. That is evidence for the previous rendering, taken
before the slots moved.

**Marker equivalence confirmed 2026-10-12.** The check this paragraph deferred to live data has
been made, on the device it named — `wardpulse_wear_round_api36_1`, a round API-36 emulator, not
shipped watch hardware. With a real paired band on the middle strip (`100% · 68%`), the two pool
markers measured:

| Marker | Measured | Strip box |
|---|---|---|
| near, inner pool | x 179.3 … 184.0 | left edge 181 |
| far, outer pool | x **264.8 … 269.5** | right edge 269 |

The far marker sits where the 2026-08-16 reading put it, so moving the strips into their bands'
slots did not move it. The deferral is retired and the geometry constants and review art stand
as they are. The figures are the coloured chip's ink read off a 384-pixel capture, where one
pixel is 1.17 design units, so nothing finer than that is claimed — the near marker straddling
the box edge is inside that tolerance, not a measured overhang.

`tools/render-watch-ring-designs.mjs` carries the same measured values, so review art shows
what the watch shows. Before that revision the generator drew the nominal 26, roughly 2.3x
the real band; it also sized each strip box to its own label until **2026-08-09**, which drew
the retired 96-unit stack in a 12pt-face world. The stack is now a constant there too, and the
generator must reject a supported review label wider than the operative **120-unit** text
region at its selected 20/18/16 size rather than let it overhang; the face would ellipsize it.

The family accent bar is the band trap again at strip scale: its 3x14 arc carries a 3-thick
stroke, so it paints 17 units tall and 6 wide with the left half clipped by the box edge —
measured 16.4 x 4.7 on device. Review art draws 4.5 x 17, not the 3 x 14 the markup declares.

## Ring type texture (revision 2026-08-11)

Three same-family budget rings are three identical orange arcs, and the strip stack names them
only in the order they melt. The band carries the missing word: each budget ring repeats its
**period** around its own circumference. Plan and allowance rings draw none — a moving window
is not a calendar period, and an empty band is itself the signal.

- **Vocabulary** — `D`, `7D`, `M`. Not `W`: at ring scale `W` and `M` are near-mirror shapes,
  and the watch already labels the Claude window `5h`, so duration tokens are the house
  vocabulary.
- **Cut-out, not ink** — glyphs are painted in the face background color and punched through
  the band, so the arc underneath keeps carrying the family and the melt boundary can never
  slice a glyph in half. WFF also refuses the alternative: `Font color` will not take
  `[COMPLICATION.RANGED_VALUE_COLORS]`.
- **45% opaque** — the punch is a shade, not a hole. At full strength the tokens read as a second
  row of marks and the ring stops reading as a ring; at 0.45 what survives is the arc, darkened by
  that share. Ambient keeps the ratio: 115 dims to 63 as the arcs dim 255 to 140.
- **Source** — the ring complication writes the token into `COMPLICATION.TITLE`
  (`WatchComplicationText.ringPeriodToken`), and the face branches on it. A ring whose id names
  no period sends none and matches no branch.
- **Size** — cap height **0.78 of the band** (15.8 of 20.2 units). Noto Sans Bold caps at 0.714
  of `size`, so the type is set at 22.1; the generator derives it rather than declaring it,
  because the band is the measured constant and the font size follows.
- **Baked, not typeset** — the face draws the type from **an image per ring and period**
  (`res/drawable-nodpi/ring{1,2,3}_type_{day,week,month}.png`, nine files, ~220 KB), not from a
  `TextCircular`. WFF rounds every glyph it lays out to a whole **canvas** unit, and each token
  takes that unit of radial play: **0.93 units** of baseline jitter, 3.0 peak to peak, identical
  in units at 384 and at 768 device pixels and repeating exactly every 90° — letters that
  visibly do not sit on their circle. Screen-independent means quantization, whose only cure is
  resolution: 0.61 units at a canvas of 900, 0.25 at 1800. The canvas cannot pay it. It is the
  resolution the **whole scene** is rendered at before scaling to the screen, so raising it
  roughens every edge on the face — 0.128 / 0.137 / 0.147 px measured for 450 / 900 / 1800 at
  384 — and it never reaches the rest of the unevenness anyway: per-glyph ink weight held at
  **17%** spread from 450 to 1800, that one being the final blit into the screen's own pixels.
  An image has no glyphs to round, carries its own spacing, and moves as one thing under any
  scale. So the band shows what the generator drew, and the canvas stays at 450, where the face
  is sharpest. Do not reach for the canvas to sharpen something else; bake it.
- **Four breaks on the diagonals** — the type does not run the whole way round. Each band is
  **four sweeps** of the same run, with **10° of bare band** between them, centered on 45°, 135°,
  225° and 315° and therefore aligned across every ring. The breaks are the design, not a defect
  to be hidden: they punctuate a texture that would otherwise read as a solid pattern, and they
  are what keeps the four bands speaking together — the same four gaps at the same four angles,
  whatever period each ring carries. Off the diagonals they would collide with 12, where both
  ends of the melt live: a break there frames the round cap, while type closes over it as a row
  of holes.
- **Placed by rotation** — within a sweep each token is rotated onto its own equal share, so the
  spacing is uniform by construction: nothing is justified, nothing is centered with a remainder
  left at the ends. The repeats per sweep are **15 / 13 / 11** for `D`, **9 / 8 / 6** for `7D`
  and **12 / 10 / 9** for `M`, outer ring first. Those counts were fitted to a token advance
  measured on device while the type was still set as text, and they are kept rather than
  recomputed — they are what the band was designed around, and a font's own metrics would fit a
  different number on the same arc.
- **One font, every watch** — baking pins what WFF otherwise cannot. Fonts are `SYNC_TO_DEVICE`
  and no font can be bundled for text, so a band set as type is fitted to a metric the watch is
  free not to have: a system face one per cent wider opens 3.6° in a full band. The image carries
  Noto Sans Bold everywhere, so the texture is identical on every device rather than merely
  tolerant of the difference. `BitmapFonts` are the other way to pin it — an image per glyph, and
  a silent ~50-glyph limit per run that a whole band exceeds. An escape hatch to remember, not to
  take.

Review art draws the same texture from the same table at the same cap height, breaks and repeat
counts — `tools/render-watch-ring-designs.mjs` copies them from the face generator and never
recomputes them, so the boards and the watch count alike. The ambient board is the one place
the height moves: that art paints a thinner band, and the type follows it at the same 0.78 of
whatever is drawn.

## Ambient

The current ambient whole clock uses integer `y=166, height=90` with **86 Thin**, matching
the active reference box and size under the common composition scale. Review baseline is
**240.78125**, rendered **240.8**. This is the
[2026-11-03 candidate](#revision-2026-11-03--ambient-clock-alignment), not a native optical
alignment result or a retained-bottom claim. The original logo is **54×54
at (198,146)**, centre (225,173), alpha70; active uses **64×64 at (193,141)**, alpha95.
Legend wells remain 132×26 with 120-unit 20/18/16 mixed-run labels and whole-row alpha90.
The upward-digit revision records historical Round Thin calibration and twelve-case
Round/Square clock/label fit, with populated defaults observed on Round. Those results apply
only to their original artifacts. Current native clock fit, quantitative composited-logo
ink/opacity, arbitrary custom/extreme readings and physical fit remain Pending.

Muted remaining arcs (when plan rings exist) and large centered time. Ring type dims with the
band it is punched into (alpha 140, same as the arcs) — it is part of the ring, not chrome to
switch off. `round-ambient-budget.svg` shows that it survives, not at what level: review art
mutes an ambient arc to one gray, while the face keeps the family color and dims it, so the two
cannot agree on a number.

**The legend strips dim rather than switch off (revision 2026-10-10).** Until this revision
they went to `alpha="0"` and ambient carried no legend at all, on the reasoning that *a strip
repeats its band*. That holds for a percent and for nothing else a strip prints: the credits in
`75% · 62.5K` and the money in `$12.34/100` appear nowhere else on the face, and ambient
dropped them with no other carrier. The division this section draws for the cells says the
opposite — what is the only carrier of its own value cannot go — so the two rules contradicted
each other, and the strips lost by seniority rather than on the merits. The worst of it was the
lone credits row of Upper cells, rule 3: with no plan ring the face draws exactly one
meaningful line, and ambient took it, leaving a clock, two recesses and nothing of WardPulse.

**The whole row dims, not its parts.** The tempting shape was to keep the well lit as it is,
dim only what shines, and leave the plain percent rows dark. Both halves of that are refused,
one by the platform and one by the stack.

Measured on `emulator-5554`: moving `Variant mode="AMBIENT" target="alpha"` off the row's
`Group` and onto the individual `PartDraw` elements leaves the family accent at full strength.
Peaks in the accent column and the label column:

| Variant sits on | accent | label |
|---|---:|---:|
| nothing — the row is off | 11 | 23 |
| the `Group`, alpha 60 / 90 / 140 | **30 / 40 / 58** | 32 / 44 / 62 |
| a `PartDraw`, the same three | **98 / 98 / 98** | 31 / 41 / 61 |

The accent does not move across three levels, while the label tracks each one. **An ambient
alpha variant on a `PartDraw` does not reach a `WeightedStroke` whose colours come from
`[COMPLICATION.RANGED_VALUE_COLORS]`; on the enclosing `Group` it does.** The markup validates
either way, so only a reading catches it. Split by role, the coloured accents would be the
brightest thing in the stack — the same trap rule 12 avoids for a cell's ring, reached from the
other side.

Dimming only the rows that carry something unique is possible and still wrong. Format version 2
has `subText(,,)` and `textLength()` (`arithmeticExpressionType.xsd`, lines 58–59), so a face
can branch on what `TEXT` holds. But with three rings, where only the bottom row carries
credits, ambient would light one bottom row (operative target `y=313`) and leave two dark gaps above it.
The stack is anchored to its bottom row precisely so it never opens a gap (Upper cells, rule 3), and
selective survival puts that gap back. The zero-ring case needs no special handling either: a
lone credits row dims like any other row.

**The level is 90, where the rest of the face uses 140.** 140 is the arcs' own proportion, worn
by the bands, by the ring type and by a cell's border, and taking it here would put one
number on the whole face. Label peaks against the surround:

| | label peak | surround |
|---|---:|---:|
| off | 9–10 | 7–9 |
| alpha 60 | 31 | 7–9 |
| **alpha 90** | **41–43** | 7–9 |
| alpha 140 | 58–61 | 7–9 |
| active mode | 232–247 | 18–21 |

At 90 a label is five times its surround — read without effort, and plainly quieter than the
arcs.

**The reason is reading order, and it is not lit area.** The first draft of this revision said
the legend at 140 would outweigh the arcs by lit area; measured 2026-10-10 on an ambient
capture, that is wrong by two orders of magnitude. Counted as pixels whose brightest channel
clears **20** — above the ambient background at 7–9 and above a well at 6–8, so only ink is
counted — with the light each carries over that line:

| In ambient, threshold 20 | lit pixels | light over threshold |
|---|---:|---:|
| the three arcs (radius 130–206) | 46,460 | 2,117,059 |
| the legend at alpha 90 | 708 | 9,083 |
| the legend at alpha 140 would be | 708 | ~14,129 |
| one occupied cell, glyphs and ring | 222 | 4,165 |

The threshold has to be named, because a small count is sensitive to it: at 11 the same capture
gives the legend 977 pixels against the arcs' 47,995, a third more on the small side and three
per cent more on the large one. The **ratios** are not sensitive, and they are what the argument
rests on — the legend is 1.5 % of the arcs' lit area at threshold 20 and 2.0 % at 11, and under
1 % of their light either way. So neither power nor burn-in can be what chooses between 90 and
140. Nor does size separate a legend row from a cell: a row averages 236 lit pixels against an
occupied cell's 222 at threshold 20, and 326 against 298 at 11 — the same element twice over on
either count. Both levels are legible and both are cheap.

What 90 buys is the order a wearer reads the face in. Three cells are three tokens, each a word
or a number, taken in at a glance; the legend is three lines of running text, and at the cells'
own level it reads as a paragraph competing with the time for first place. A step down puts it
behind them without putting it out of reach — still five times its surround. So the face
carries two ambient proportions instead of one, and the cost is named rather than hidden: the
reason is what should be read first, not what costs the most to light.

In the upper cells the wells stay and the values dim (revision **2026-10-09**). The dimming
follows the same division: what restates something else on the face can go, and what is the
only carrier of its own value cannot. A complication in a cell repeats nothing, and neither
does the weather chrome showing through an empty one, so both dim. The wells go the other way
for two reasons. A filled cell's well is the only thing hiding the weather chrome beneath it,
so it has to survive ambient or two readings land in the same cell. And a well darkens the
lift rather than lighting it, so switching one off would raise ambient luminance instead of
lowering it. The dimmed level is to be measured when the generator changes, in the proportion
the face already uses for the ring type — see Upper cells, rule 12.

## Review variants

`node tools/render-watch-ring-designs.mjs` regenerates the boards, **one PNG preview per board**,
and the face-picker preview from the WFF copy of the Primary baseline. To open the
primary review preview after generation:

```sh
xdg-open apps/wear_android/design/preview-3-plan-credits.png
```

The current maps contain 42 boards/42 PNGs and 39 WFF mirrors. The 14 adaptive additions
come from `adaptiveVariants` in `tools/render-watch-ring-designs.mjs` and are included in
both `variants` and `wffFiles`. All model the whole
clock at font **86**, active weight **700** / ambient **100**, with the shared baseline
**240.78125** (rendered **240.8**),
52-unit cells and 132×26 wells with 20/18/16 labels.
Ordinary boards stay mark-free; the shipped portrait alone overlays the active 64-square
logo at (193,141), alpha95, read from generated XML.
Generate WFF first, then review art; inspect actual PNGs separately from SVG drift checks.
These images are review/picker art, not native or public-capture acceptance.

| File | Meaning |
|------|---------|
| `round-3-plan-credits.svg` | **Primary baseline** — three providers, plan + credits |
| `round-3-plan-split.svg` | **Split band baseline** — a Cursor plan's two pools on one band, two markers and two percents on its strip |
| `round-3-plan-two-pairs.svg` | Three bands with Cursor and Codex/Spark pairs, fixed inner/outer order and two far markers |
| `round-plan-fable.svg` / `round-plan-fable-zero.svg` | Synthetic Claude/Fable illustrations: fixed halves and both exhausted; native acceptance Pending |
| `round-3-plan-untouched.svg` | A pool nobody has spent: its half closes, while the pool beside it keeps its gap |
| `round-3-plan-near-exhausted.svg` | Near-exhaustion regression — `2%`, `69%`, and `94%` remain, and the 2% ring still has a visible mark |
| `round-1-plan-exhausted.svg` | Selected Claude 5h at zero: grey track and pale-red `0%` |
| `round-3-plan-exhausted-claude.svg` | Claude zero remains beside the Cursor pair and Codex; three selected bands |
| `round-plan-pair-inner-zero.svg` / `round-plan-pair-outer-zero.svg` | Fixed paired identities with either known half at zero |
| `round-plan-pair-both-zero.svg` | Both known halves retain grey tracks, family markers and two red percentage tokens |
| `round-3-plan-all-zero.svg` / `round-3-plan-two-pairs-zero.svg` | Full selected-zero cases, including two paired bands |
| `round-ambient-all-zero.svg` | Zero tracks and legend values retained in ambient review treatment |
| `round-plan-positive-rounds-zero.svg` | Positive arc geometry with an ordinary `0%` label; subpixel visibility is not asserted |
| `round-plan-zero-credits.svg` | Red zero percentage beside neutral `0` credits |
| `round-plan-unavailable-inner-zero-outer.svg` | Invalid inner usage omitted; the known zero outer survivor keeps its own family identity |
| `round-budget-exhausted.svg` | Grey exhausted budget track, with its existing money label unchanged |
| `round-3-plan-budget.svg` | Two plan rings + a budget ring reading `$71.30/250`; only its band carries type |
| `round-3-budget-periods.svg` | **Ring type baseline** — one connection's three budget periods, told apart by `7D` / `M` / `D` alone |
| `round-2-plan-credits.svg` | Two providers |
| `round-1-plan.svg` | Single plan ring, `%` strip only |
| `round-1-plan-credits.svg` | Single plan + credits |
| `round-credits-only.svg` | No plan rings — time + the lone credits strip, on the bottom row |
| `round-3-plan-cell-cleared.svg` | **Empty-cell baseline** — the left cell cleared, showing the graded recess beside two filled ones |
| `round-ambient-3.svg` | Ambient, three muted rings |
| `round-ambient-budget.svg` | Ambient with type — the band dims and takes its type with it |
| `round-1-plan-split.svg` | One widened adaptive band with a Cursor pair |
| `round-2-plan-two-pairs.svg` | Two widened adaptive bands with Codex/Spark and Cursor pairs |
| `round-{1,2}-budget-{d,7d,m}.svg` | Six active adaptive budget boards; all periods at each new radius, with distinct periods rotated across two-band layouts |
| `round-ambient-{1,2}-budget-{d,7d,m}.svg` | Six ambient counterparts for the new-radius period fits |

**Preview coverage revision 2026-10-11 — every board in that table has a preview beside it**,
named `preview-<board>.png` for `round-<board>.svg`, and the generator derives that list from
the boards rather than keeping a second one next to them. Seven of the fourteen had no preview
at all until today, three of them rows this table labels *baseline* — Split band, Ring type and
Empty cell — so a reader sent to a baseline board had nothing to open, and `design/README.md`
named `round-3-plan-split` among the variants while no such preview existed. A hand-kept list is
a second thing to remember, which is the failure the preview-ownership revision above is about,
one level up: a preview that is never written cannot lie, but the rule it demonstrates goes
unwitnessed.

Wear: `apps/wear_android/design/`. WFF copies: `apps/watchface_wff/design/`.  
OpenPencil `rings.fig` is a frame inventory only (`.fig` write drops ellipse `arcData`).

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app Glance | **Not** this face language — locked text legend (`WEAR_GLANCE_DESIGN.md`, 2026-07-26) |
| WFF watch face | Same language with large time hero; concentric `RANGED_VALUE` arcs plus sunk `RANGED_VALUE` strips (`%` / `% · credits` / `$12.34/100` for budgets) in `watchface.xml`. Every strip TEXT is the full label (WFF `length(TITLE)` Conditions are unreliable). Inner strip accents use `[COMPLICATION.RANGED_VALUE_COLORS]` (family ColorRamp); far markers use static palette colours selected by strip `TITLE` (Split band, rule 4). Keep progress/track spans below 360° (scale onto 359.9°) — a closed circle collapses to a ROUND tip. Remaining melt is clockwise from 12: Transform `startAngle` to `(1 - value/max) * 359.9` with fixed `endAngle` 359.9. A `BoundingArc` clips its slot's content to the arc band and halves its stroke (measured 2026-10-09, Ring geometry), so a slot that must draw both a band and a strip takes a full-canvas `BoundingBox` instead. An ambient alpha `Variant` reaches a `WeightedStroke` coloured from `[COMPLICATION.RANGED_VALUE_COLORS]` only from the enclosing `Group`, never from the `PartDraw` that holds it (measured 2026-10-10, Ambient), which is why a legend row dims whole rather than by part. A scene holds **at most eight** `ComplicationSlot` elements in every format version — the validator rejects a ninth, and `sceneElement.xsd:45` says `maxOccurs="8"` — and this face has used all eight since 2026-07-25, so a new slot has to come out of that budget (Split band, rule 7; Upper cells, rule 2). Three of them are customizable upper cells and belong to the wearer, edited in the system watch-face editor rather than by the WardPulse phone app (Upper cells, rule 5). The temperature and UV index a fresh install shows are not complications at all: they are scene chrome reading the built-in `WEATHER.*` source, declared ahead of the first slot, so a filled cell's opaque `#ff0b0e0c` well covers them while the strips keep their translucent `#eb0b0e0c` (Upper cells, rules 10 and 11). |
| Phone Watchface tab | Slot selection + preview of next payload rings (not Settings). Rows are grouped since 2026-08-16: a heading per kind of connection, a sub-heading per connection, the same outline the Widget tab uses |

## Non-goals

- Side-by-side `RING 1` / `RING 2` wireframe complications as the target language.
- Large remaining % as the hero in the middle of the face, in place of the time.
- High-contrast bordered strip “cards” or ring-cast drop shadows as strip chrome. The border
  an occupied upper cell wears (Upper cells, rule 10) is the one exception, written in on
  **2026-10-10**: this refuses chrome that frames content which is already legible without it,
  and a filled cell was not — an opaque well on the lift is a step of eight to eleven levels,
  which reads as depth under a recess but leaves a filled cell edgeless, so only its glyphs
  registered. The ring remains a 1.5-unit line in the face's own text colour. The
  operative **2026-10-25** clarification preserves its outward radial fade on all cells and
  adds a strictly bottom-directed fade only to lateral borders. It remains inscribed, its outer
  edge meeting the well's own at **26** after the refinement (previously 25/24/21;
  Upper cells, rule 10), carrying no fill, no shadow and no colour of its own. It makes
  *occupied* and *free* distinct at a glance.
- Time-based rotation of which metric is “on top” in the first iteration.
- Brand/marketing chrome, floating badges, or dense face captions.
- LLM token counts (`TOK`) on the face — those belong on phone history charts, not strips.
- A second arc language anywhere on the face: a ranged value in an upper cell reads as text,
  never as a small arc of its own (Upper cells, rule 8).

### Previews are generated — and the picker's showed the first non-goal

Found 2026-10-09 while reading the system face picker on `emulator-5554`. The picker renders
`apps/watchface_wff/src/main/res/xml/watch_face_info.xml`, which points at
`@drawable/preview`, and `apps/watchface_wff/src/main/res/drawable/preview.png` — 450×450,
unchanged since `2c5aec3` — draws two hollow rings side by side labelled `RING 1 25%` and
`RING 2 49%`, under a `WARDPULSE` heading and over an `OPENAI · OK` line.

That is the first entry in the list above, drawn at full size. The picker is where a wearer
chooses the face, so the retired wireframe language is the first and sometimes only thing they
see of it, and it resembles nothing the face has rendered since the 2026-07-25 concentric
baseline. `just check-watchface` cannot catch this — the preview is an opaque asset, gated by
no generator — and `docs/ANDROID_TOOLCHAIN.md` already asks for a fresh capture after visual
changes, which this file has not had.

**Preview-ownership revision 2026-10-10.** A preview nothing regenerates is a preview that
will lie: it keeps the face it was made from while the face moves on, and it is read as current
either way — by a wearer choosing in the picker, by a reviewer checking the baseline. Ownership
belongs to a generator, not to a command in a README that someone has to remember to run. The
principle is general, and another baseline may adopt it word for word; the authority of this
one is not, so what follows locks it for the two previews this document owns — the shipped
picker asset, and the face review previews it cites.

For the shipped asset that means `apps/watchface_wff/src/main/res/drawable/preview.png`, named
by `watch_face_info.xml`, is generated from `round-3-plan-credits.svg`, the **Primary baseline**
of Review variants, which is already 450×450 in its own viewBox and already draws the face's
language: three concentric bands, three upper cells behind their occupied borders, the time hero, and
the three legend strips. A generator owns the rasterization and rewrites the file whenever the
face art is rendered. Which generator that is belongs to implementation; that there is one does
not. The defect above was never the picture alone — it was that nothing regenerated it.
`2c5aec3` is dated **2026-07-25**, the day the baseline was locked, so every revision in the
chain at the head of this document postdates the file and none of them reached it.

The rule governs the face review previews this document cites — the `preview-*.png` renders of
the Review variants boards, `preview-3-plan-credits.png` among them, which the head of this
document calls canonical. They carried the identical defect, measured **2026-10-10**: that file
is 675×675 and dated 2026-08-18, while the `round-3-plan-credits.svg` it is made from had been
regenerated the same day, and `design/README.md` carries its
`convert -background none -density 144 …` line as something a person runs. Running that exact
command and comparing against the committed file gives **9,694 differing pixels** at identical
dimensions — content, not metadata — and the committed image has no upper cells at all, so the
whole of Upper cells is missing from the picture this document calls canonical. A preview the
baseline cites is held to the baseline.

It reaches no further than that. `apps/wear_android/design/` also holds the Glance boards and
their `preview-glance-legend-*.png` renders, which belong to
`docs/product/WEAR_GLANCE_DESIGN.md`, and a face placement preview lived under separate brand
ownership in `brand/watchface/`. Those were their own documents' to rule on, and root
`AGENTS.md` keeps component guidance beside its owner. Sharing a directory with a face board
confers nothing here. Both have since ruled: the Glance baseline adopted the rule on
**2026-10-11**, and `docs/DESIGN_ASSETS.md` generated its placement preview the same day and
then retired it, once the watermark revision below made this document's own portrait the same
picture.

No preview carries a byte comparison, and that is a decision rather than a gap. The header on
`emit` in `tools/design-output.mjs` already refuses one for generated images, and says what
replaces it: "SVG is compared byte for byte because it is text the generator wrote. PNG previews
are not compared here: ImageMagick stamps metadata that changes between runs, so equal images
differ as bytes. What stands in place of a byte gate is `renderPreviews` below — every preview is
rewritten from its board on every render, so none of them can keep art the design has left
behind." That rewriting is what stands in its place here too;
the shipped asset is held twice over, because `watch_face_info.xml` names it by resource and a
missing one stops the build. The tree already holds two working ways to keep such a file from
churning in the diff: `write_png_if_pixels_changed` in `tools/export-icons.sh` renders to a
candidate and runs `compare -metric AE`, replacing the committed PNG only when the pixels
differ — that is how `apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png`, a watch face
drawable, is written — and `rasterize` in `tools/render-watchface.mjs` passes `-strip` so the
render timestamp never reaches the bytes. Either settles the churn. Neither is mandated here.
Those three name functions rather than lines deliberately: the last of them was cited as
line 674 of `render-watchface.mjs` on **2026-10-10** and pointed at the wrong sentence by the next day,
when an unrelated comment three hundred lines above it grew. The `sceneElement.xsd:45` cited
elsewhere here is the exception that holds: that file ships inside the pinned validator jar, so
no commit in this repository can move it.

What the gate cannot do, it does not claim: `just check-designs` compares the boards against
their own generator and nothing else (the `check-designs` recipe in the `justfile`), so a
preview generated from a board is proved to match that board, never to match the face. The
face is what a device capture proves, by hand, as the acceptance for this phase already asks.

**That comparison was made on 2026-10-11, for the first time.** A 384-pixel capture of the face
on `emulator-5554` and `round-3-plan-credits.svg` rendered to the same 384, both reduced to grey
and scanned along the horizontal centre line: the band edges in the left half are
`19, 37, 40, 58, 60, 78` **in both**, identical at all six. Inside them the edges part where the
content differs, which is data and not geometry — the device was showing its own payload and its
own cells. So the boards and the face agree on where the bands are, measured rather than
asserted, and the agreement is one the gate above could not have produced.

A preview draws only what the face draws, from the face's own declared sources, and never an
invented complication set. In the cells that means the weather chrome of Upper cells, rule 11,
where `WEATHER.IS_AVAILABLE` is true; the graded well of rule 10 where it is not; and a
complication where a slot is bound — the `Tue` on the primary board is a `DAY_OF_WEEK` reading
on the left cell, which rule 11 leaves with no chrome declared beneath it, not weather. It takes
no marketing chrome, no badge, no caption, and no reading a wearer could not get.

The board's `18°C` and `UV 7` are therefore the weather-available state, not a universal one.
Measured on `emulator-5554`, **2026-10-10**, on a fresh install from this baseline: the left
cell drew `Sat` with its hairline, and the middle and right cells drew empty graded wells, no
weather being available to that device. A preview may show the available state — it is a state
the face renders — but no rule here may be read as requiring a fresh install to produce it. A
preview that flatters the face by showing what it does not do is the same failure as the
wireframe it replaces, one generation later.

**Surface correction 2026-10-11 — what displays this asset is not settled, and the rule does
not rest on it.** The finding above opens *the picker renders
`apps/watchface_wff/src/main/res/xml/watch_face_info.xml`, which points at `@drawable/preview`*,
and then describes what that file draws. Read again, that is a **chain of inference** and not a
sighting: picker, to metadata, to declared file, to the file's own content. The subject of
*draws two hollow rings* is `preview.png`, and the detail around it — the `WARDPULSE` heading,
the `OPENAI · OK` line — describes the image. Nothing in that paragraph, in the Phase 20 entry
of `docs/DEVELOPMENT_PLAN.md`, or in the commits of that day records anyone looking at the
picker and seeing `RING 1`.

The one direct measurement of the picker is **2026-10-11**, on `emulator-5554`, and it shows a
live render of the face rather than the asset:

| | picker, measured 2026-10-11 | the shipped asset that day |
|---|---|---|
| watermark | present | absent |
| upper cells | `Fri` `25` `3` | `Tue` `18°` `UV 7` |
| strips | `8` `39` `72` | `8% · 500` `39%` `53%` |
| arc colours, outer to inner | green, orange, teal | blue, orange, green |
| time | 10:08 | 10:08 |

The watermark settles that row on its own: the asset was rasterized from a review board, and no
board draws the mark. The cell values read as preview complication data, and 10:08 is the
preview reference time.

**So this is not two behaviours on two dates.** The simpler account fits every fact on record:
the picker may always have rendered live, and the 2026-10-09 conclusion *about the picker* was
inferred from the metadata chain, while the staleness of the **file** — which was real, and
which the find got right — was read off the file itself. No change needs explaining, so none is
offered here.

What **is** established, measured 2026-10-11, is the other half of the chain: the asset ships.
The installed package was pulled off `emulator-5554` and unpacked, and its
`res/drawable/preview.png` is byte-identical to the file in the tree — same sha256, same 64,316
bytes, 450×450, `compare -metric AE` of 0 — with `wardpulse_mono.png` and the nine ring-type
textures shipped beside it. So the generator's output is what reaches the device, which is the
part of the 2026-10-10 work that can be confirmed on hardware rather than in the repository.

That is the whole of what is known, and the rule is written to that boundary and no further.
Known: the asset was stale and drew the first non-goal; the format requires a `Preview` and
`watch_face_info.xml` declares this file; the build needs it; it ships intact to the device; and
the picker, measured once, renders the face live. Not known: whether any surface displays the
file, and whether the picker ever did. **The ownership rule above never depended on either.** A
shipped image that no generator rewrites will lie wherever it is shown, and an asset that ships
on every device is one that must never be stale.

The dated find above stays as written. The correction is to what was concluded about the picker
from it, not to the find — and the distinction is the same one this section exists to defend: a
documented inference hardening into a remembered observation is how a preview hardens into a
remembered face.

**Watermark revision 2026-10-11 — the face's portrait carries the mark the face carries.** The
shipped asset omitted the quiet `WARDPULSE` watermark then locked between time and strips
(now above the clock under the 2026-10-27 revision) and drawn by `watchface.xml`. It omitted
it because it is rasterized from a review board and review boards are mark-free. That is right for a board and
wrong for this file. A board is read by a reviewer checking ring geometry; this asset is the
face's own portrait, declared as its `Preview`, and a portrait that drops a locked element of
the face shows a wearer a face they will not get.

So the asset is **composed** rather than only rasterized: the Primary board at 450, then the
faded mono drawable `apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png` at the box
`watchface.xml` gives the mark — currently 64×64 at (193,141), alpha95; historical 66-square
boxes were (192,227), then (192,214) — read out of that file at
render time rather than copied into the generator, so the portrait cannot disagree with the face
about where the mark sits. The ambient mark is not drawn: this is the active portrait, and the
smaller 54×54 at (198,146), alpha70 only appears under an ambient variant (Upper cells, rule 12, and
`docs/DESIGN_ASSETS.md`).

**The review boards stay mark-free, and that is not an inconsistency.** They are review art for
the ring language; the mark is brand-owned and not covered by Apache-2.0
(`docs/DESIGN_ASSETS.md`); and the non-goal against brand chrome keeps it out of art whose job
is to let a reviewer read the band it sits over. The portrait is the one place the face is being
*shown* rather than *reviewed*, and it is the only one of these images the package ships.

Nothing new enters the package by this. `wardpulse_mono.png` was already shipping beside the
portrait in the same APK — both were read out of the installed package on 2026-10-11 — so the
composite puts a drawable the face already carries into the picture of the face that carries it.
It changes what the shipped portrait shows, not what the shipped package contains, and it grants
nothing: a composite is not a licence.

One asset is retired by this, which `docs/DESIGN_ASSETS.md` had already written as the
condition for it: `brand/watchface/preview-face-active-quiet.png` was composed from the same two
parts in the same box, so with the mark on the portrait the two are the same picture, and a
second canonical copy of one image is worse than none. It is gone, and that document now cites
the face's own asset. The ordering between the two generators reverses with it: `just export-icons`
no longer reads the picker asset, and `just render-designs` now reads the faded mono drawable,
so a change to the **mark** reaches the portrait through `just export-icons` first.

## Future direction (not locked baseline)

Recorded for planning only. Today’s **Max three** rule and “purchased meters are not rings”
are locked; do not raise the face cap without an explicit later design revision.

- **Multi-profile per provider** — up to three profiles/accounts of the same provider may
  eventually share a device. Same-family rings on one face must then differ by more than family
  color (color alone is not enough for two Codex or two Claude windows). The band is already
  spoken for on budget rings, so a profile marker either shares that channel — a profile token
  read together with the period — or finds another; a second pattern layered on the same band
  would make both unreadable. Since 2026-08-13 a split Cursor band has no room left at all: its
  two halves are already the division, and dividing a half again is not a thing a 17-pixel band
  can carry. Two Cursor profiles will have to give up either the split or the same face.
