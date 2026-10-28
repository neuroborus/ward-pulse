# Wear Glance Design

**Baseline locked 2026-07-26** — accepted visual target for the Wear OS **app** home Glance
(first page after opening the tile) until the next explicit design revision. Distinct from the
watch-face baseline in [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md): this screen is a
**text legend** for face ring colors, not a face clone.

The operative legend typography and overflow rules are in
[Revision 2026-10-24 — clock-free Glance and larger legend](#revision-2026-10-24--clock-free-glance-and-larger-legend).
Earlier measurements and acceptance records below describe only their dated builds.

**Selected-zero revision 2026-10-13.** The owner's two screenshots taken at 11:36 and 11:38
showed Claude's 5-hour window at **0% left** on the phone while the watch chose **Weekly,
23% left**. Select the tightest known window including zero and retain exhausted selected
rows. A zero pool keeps its grey mini-track with no coloured remaining arc; only its `0%`
token takes **`#FFB4AB`**, the existing phone dark theme's error role computed on the host.
This is a colour-token decision, not a measured device colour. Both known halves of a pair
remain in their fixed order when one or both reach zero. Missing/unknown values still stay
absent; non-finite or negative usage is unavailable too. The original screenshots record the
discrepancy. Subsequent injected-device and live phone-to-watch checks are recorded below.

**Injected-device verification 2026-10-13.** The canonical round API-36 AVD,
`wardpulse_wear_round_api36_1`, `emulator-5554`, **384×384**, selected `Claude · 5h` at
**`0% left`** from captured normalized `5h used=100` / `Weekly used=77` data. The zero pool's
mini-track was grey and only its percentage token was red. Inner-zero, outer-zero and
both-zero Cursor cases retained both known tracks and family identity; two pairs retained
their ordinals, and all three selected exhausted bands retained **three rows**. The existing
budget percentage also used a red zero token, while the face's money label stayed white.
All **10** canonical Wear device tests passed; the captured Claude zero case was rechecked
after installing the final Wear APK. These broader variant checks used injected data on
this round AVD; notround and hardware zero states are not claimed.

**Live phone-to-watch verification 2026-10-13.** The intermediate phone APK built from
the frozen zero-policy runtime refreshed the real Dashboard at **12:38:04**, showing Claude
**5h 0% / Weekly 23%** and Codex **94%**. Its schema-9 summary, generated at
`2026-10-13T10:38:04.000Z`, reached Wear with Claude `label=5h`, `usedPercent=100`.
`live-zero-glance.png` showed **`Claude · 5h` / red `0% left`** with a grey mini-track and
Codex **`94% left`**, matching the fresh Dashboard; the face matched too. No preferences
were injected between the phone's live sync and these captures. The locked face baseline
records the queue/receipt times and their device-clock offset. Live zero-policy acceptance
passes on the canonical round AVD; final persistent-cache APK and cold-worker verification
remain separate and pending.

**Revision 2026-09-16 — paired bands:** one Glance row per band, with two mini arcs
and two remaining percentages for an active pair. Typography, row pitch and Alerts clearance
are unchanged; the 2026-10-01 revision below verifies the paired-row fit on both screen shapes.

**Revision 2026-09-16 — Codex/Spark:** the full board was revised to show two pairs in three
rows. Codex main is the first arc/percentage and Spark the second; the title is
`Codex plan`. Geometry and typography stay fixed; the paired-row footprint and three-row fit
are covered by the 2026-10-01 verification below.

**Revision 2026-10-01 — round/notround fit verified:** the same three-band payload, with
`Cursor Models` and `Other Models` paired in the middle row, was measured on `emulator-5554`
(`round`, 384×384) and `wardpulse_wear_square_api36_1` (`notround`, 360×360).

| Measurement | Round 384×384 | Notround 360×360 |
|-------------|---------------|------------------|
| Row pitch | 46 px (0.120 of screen height) | 43 px (0.119 of screen height) |
| Arc left edge | x 112 (0.292 of screen width) | x 102 (0.283 of screen width) |
| Paired inner pool | x 102…132, left | x 102…132, left |
| Paired outer pool | x 155…187, right | x 143…173, right |

Both screens keep the inner pool before the outer pool, fit all three rows with the Alerts pill,
and show every label without clipping. Glance lays out against the available width without
screen-shape-specific behavior; it does not render a fixed-size canvas. WFF is different: its
fixed 450-unit canvas and inscribed circle make a separate round-versus-square fit check
unnecessary.

**Revision 2026-10-11 — previews are generated:** the ten `preview-glance-legend-*.png` this
document cites are written by `tools/render-wear-glance-designs.mjs` from their own boards, in
the run that writes those boards. Until this revision they were not. The generator wrote SVG
only, and the PNGs came from a `convert -background none -density 144 …` line printed here and
in `apps/wear_android/design/README.md` for a person to run — and two of the ten had been left
behind. Measured 2026-10-11 against a fresh render of their own boards at identical 675×675,
`preview-glance-legend-full.png` differed by 37,529 pixels and `preview-glance-legend-pair.png`
by 18,253, out of 455,625; the other eight matched exactly, so this is content, not metadata.
Both showed the layout the two 2026-09-16 revisions above retired: one row per pool, one arc
each. The `pair` board exists to show a pair, and its preview showed three unpaired rows.

A preview nothing regenerates will lie. It keeps the screen it was made from while the screen
moves on, and it is read as current either way, because a reviewer reads review art instead of
booting a watch. Ownership therefore belongs to the generator, not to a command someone has to
remember to run. `WATCH_RING_DESIGN.md` locked the same rule for the face on 2026-10-10 and
said its authority reached no further than the previews that document owns; this revision
adopts the rule for the Glance previews on this document's own authority. Acceptance below
already read `review art: render-wear-glance-designs.mjs → preview-glance-legend-*.png`; as of
this revision that line describes the tree rather than an intention.

What it does not buy: `just check-designs` compares the boards against their own generator and
nothing else, and no PNG is byte-compared at all — `tools/design-output.mjs` records why. A
generated preview is proved to match its board, never to match the Glance screen on a watch.
That stays a device capture's job.

**Revision 2026-10-11 — credit balances are compact:** a Glance row renders a purchased credit
balance in the face's own compact form and appends the unit word — `62.5K credits`, `320
credits`, `1K credits`, `0 credits`. Until this revision it printed the provider's own number
with nothing done to it but trailing zeros trimmed, which is no help when the tail is not zeros.
Seen on `emulator-5554` the same day, third row:

```text
Codex · Weekly plan
75% left · 62479.294375 credits
```

The face strip, one swipe away, drew the same balance from the same payload as `62.5K`.

Nothing here was ever ruled. This document showed only examples — `8% left · 320 credits`,
`82% · 41% left · 320 credits` — and every one is a short integer somebody chose by hand, so no
board, no preview and no run of `just check-designs` could have shown it. It took a real payload
on a real screen.

**The rule is the face's, and the reason is not width.** Those six decimal places are the
provider's arithmetic, not information anyone acts on; dropping them costs the wearer nothing at
any width. What the extra width does buy is the word `credits`, which the face strip has no room
for and this row keeps. More precision is declined on purpose: the same balance appears on
two screens one swipe apart, and a Glance that disagreed with the face about a number would make
the wearer decide which to believe. So the number is the strip's own and the unit word is the
Glance's own.

It also makes the subtitle bounded, which is what keeps the 2026-10-01 fit check honest. That
check measured three rows and found no clipping — with `320 credits` in them, a length nobody
had guaranteed. Compacted, the longest a paired subtitle can reach is
`100% · 100% left · 999.9T credits`, for any balance below a quadrillion credits; the old form
grew with whatever a provider sent.

The plan windows page draws the same `Quantity` in its no-share fallback and follows the same
rule (`apps/wear_android/README.md`). Out of reach of this document: the **phone** dashboard
renders the same balance uncompacted, which it ruled on 2026-10-11
(`PHONE_DASHBOARD_DESIGN.md`, Balances) — compaction belongs to a glance, and that screen is
not one.

**Revision 2026-10-11 — the suffix is credits or it is nothing:** *Revision 2026-10-11 — credit
balances are compact* assumed the balance it compacts is denominated in credits. The shared
contract does not guarantee that — `schemas/dashboard_snapshot.schema.json` allows `tokens` as
well — and the row printed whatever unit arrived, so a token balance would have read
`8% left · 62.5K tokens`, against this document's own *never LLM `TOK`* in Composition. No
adapter reports one today; nothing stopped one.

A purchased balance in any unit but `credits` is now treated as **absent**, and this row already
draws that: it omits the suffix, exactly as acceptance has always required when a balance is
unavailable. Showing the number without its word was refused — `62.5K` beside a credits-shaped
row says credits, and would be wrong rather than merely forbidden.

The guard sits in `purchasedRemainingForRing`, the one lookup behind this row, the face strip
and the complication, so the three cannot drift apart. Why the contract keeps `tokens` instead
of losing the variant, and why the payload is not rejected on arrival, is `PROVIDER_NOTES.md`,
*The credits channel carries only credits*. This document rules only on the row.

**Verified 2026-10-11 — the composition holds on a device.** The 2026-10-01 entry measured this
screen's layout and nothing had ever checked what its rows *say*. Read on `emulator-5554` with
the live payload the phone was pushing, three bands selected:

```text
      (↻ OK)            gray, no detail line

 (●)  Claude · Weekly
      65% left

 (●)(●)  Cursor plan
      100% · 68% left

 (●)  Codex · Weekly plan
      87% left · 62.5K credits

      [ Alerts: 0 ]
```

Every composition rule the screen can show, it showed. The bands are the face's three in the
face's order — its strips read `65%`, `100% · 68%`, `87% · 62.5K` in the same minute. The pair
keeps its band position and spends one row, inner pool left and outer right, one `left` covering
both percentages, primary line `Cursor plan` exactly. Claude is collapsed to a single ring and
the short label says which window won, `Claude · Weekly`. Credits appear once, compact, with the
unit word, on the one row whose family reports a balance. The `Alerts: 0` pill is present and
disabled. Every mini arc opens its usage gap at 12.

One clause the order rule needs: **it is the payload's order, not the instant's.** A few minutes
earlier the two screens disagreed, the face still drawing an older summary; they matched as soon
as both held the same one. A reader comparing them mid-sync is comparing two payloads.

**The pulse and the control were seen apart, which is the whole of that rule.** Under *Refresh
status control* their independence is a table; on the device it was two readings hours apart on
the same screen. With the phone syncing, the glyph read a **gray `OK` with no detail line** —
healthy, manual sync not yet allowed, the cadence-cooldown row of that table. Before the phone
was syncing, the same glyph read **`!OK` with the detail `Stale`**. Neither is a degradation of
the other, which is what the non-goal against conflating cadence cooldown with `!OK` /
`Rate limited` defends.

**The cap correction was confirmed by eye and not measured.** The Cursor row's inner pool sits at
100% remaining — the case the correction exists for — and on a 5× crop of the capture its ring is
open at 12: the stated failure, a nearly full row reading as a closed ring, does not happen. No
angle was taken. Isolating the arc by colour kept catching the neighbouring pool and the track,
and the figures that came out were impossible and were discarded rather than reported. The
8.4°-per-cap arithmetic above stands on its own derivation, not on this reading.

What this does not cover: the geometry, which the 2026-10-01 entry owns and this one does not
restate; the empty and exhausted states; and any rate-limited or alerting payload. One AVD, one
build, one payload.

Do not reintroduce a face clone (large concentric stacks, sunk strips, watermark, or
time-as-hero), stacked icon-above-label refresh, or conflating cadence cooldown with
`!OK` / `Rate limited`.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-wear-glance-designs.mjs`  
Primary preview: `apps/wear_android/design/preview-glance-legend-3.png`.

## Revision 2026-10-16 — watch-face utility entry

The Wear app retains two home pages: Glance, then Plan windows. One **Watch face** action
follows the complete Plan windows list, after its last row, and opens a swipe-back utility
route. Before the first phone summary, the same entry appears below the sync prompt. The
utility is not a third home page and adds no controls to Glance or Alerts.

The pre-summary action's later presentation and clock clearance are specified in
[Revision 2026-10-28 — compact no-summary Watch face action](#revision-2026-10-28--compact-no-summary-watch-face-action).

Preserve Glance typography, refresh behavior, row and paired-pool ordering, the 54-unit row
pitch and 12-unit Alerts clearance. Keep every existing Plan windows row and its ordering.
This revision changes no face geometry, ring selection, data contract or provider behavior.

Status checks are read-only. Installation does not activate the face. Activation requires
the explicit **Use watch face** action, with at most one permission request and activation
attempt; refusal or a consumed opportunity leads to manual selection. Updates are explicit,
newer-only and preserve face selection and customization without another activation request.
An unknown occupied slot is never replaced or deleted. **In use** requires a current
observation; it does not hide an available update. After an update, show **Installed**
without an immediate active-state query. Summary availability must not reset this route or
replay an operation.

**Verified 2026-10-16** on canonical `wardpulse_wear_round_api36_1` / `emulator-5554`, API 36,
round **384×384 px / 320 dpi**. Installed Wear version **0.1.0 / code 1**, minimum API 33,
target API 36, from reviewed Source `abebbbc5`. Bounds below are actual screen pixels.

| Canonical item | Actual verification |
| --- | --- |
| Glance refresh and clock | Refresh `[144,46]–[240,130]`; clock `[0,28]–[384,46]`, unchanged from the pre-feature reference. |
| Glance rows and Alerts | Provider-title top positions `148`, `194`, `240`; Alerts label `[168,325]–[218,341]`, unchanged. |
| Complete Plan windows list | All five actual rows retained in order, followed by exactly one utility entry. |
| Fully scrolled utility entry | Hit region `[20,216]–[364,344]`; label `[44,240]–[221,278]`; fully readable and enabled after further normal scrolling. |
| Utility copy and action | Top/middle/end scrolling exposes the complete instruction and enabled **Use watch face**. End-position button `[20,240]–[364,344]`, label `[48,274]–[273,310]`. |
| Preserved selection/data | Existing legacy face and Day/empty upper-slot choices retained; fresh phone summary reached Glance and the live face; ordinary editor returned to live. Canonical consent was not consumed. |

The entry's earlier first-visible bounds, `[44,301]–[340,384]` with label
`[65,322]–[217,354]`, describe a clipped scroll position, not the fully scrolled entry above.
At the extreme utility end position, the departing Make heading intersects the fixed clock
near `y24`; the middle position makes it fully readable. This is viewport-edge clipping,
not a promise that all copy fits in one frame. The approved
[manual-selection image](../assets/wear-watch-face-utility.png) avoids that overlap; private
canonical QA frames with a low-battery indicator are not public illustrations.

The genuine no-summary entry and real summary arrival/replacement were observed separately
on the task API36 UI08 runtime, `wardpulse_push_wear_api36_1` (**384×384 px / 320 dpi**).
Final device tests cover synthetic availability/loss and permission-return transitions.
Canonical data was not cleared to manufacture an empty state; synthetic loss does not prove
actual Data Layer loss. The utility UI owner is unchanged in the final reviewed Source.
These emulator observations establish neither API35 nor physical-watch acceptance; see
[the acceptance record](RELEASE_CHECKLIST.md#watch-face-push-acceptance).

## Revision 2026-10-17 — selected plan titles

Known ordinary Claude windows use `Claude plan · 5h`, `Claude plan · Weekly`,
`Claude plan · Opus weekly` or `Claude plan · Sonnet weekly`. Codex main uses
`Codex plan · 5h` or `Codex plan · Weekly`; the known legacy raw label `Weekly plan` is
recognized as `Weekly` for presentation only, without changing the payload. Unpaired Spark
keeps its selected window: `Codex plan · Spark 5h` or `Codex plan · Spark Weekly`.
Complete pairs remain exactly `Cursor plan` / `Codex plan`, with inner-first arcs and
percentages and purchased credits once per provider. If a half is unavailable, title the
surviving half by its own window or pool. Preserve unknown labels, externally composed labels,
budget labels and distinct `Cursor Models` / `Other Models` names; never strip arbitrary
suffixes or duplicate family/plan wording.

Phone selection and band order, including known zero and ties, remain unchanged, as do
values, pools, colours, exhaustion styling, credits, refresh, Alerts and navigation.
For that revision, typography, mini-arcs, 54-unit row pitch, 12-unit Alerts clearance and the
three-row ceiling stayed fixed. The October 24 revision below supersedes only its legend
typography, pitch and fit rules; clipping supported values remains unacceptable.

**Acceptance: Pending.** The revised SVG boards and their PNG previews must be regenerated
together after this Source work and the separate sync correction finish. The full board must
show the longest `Claude plan · Sonnet weekly` with complete credited Cursor and Codex pairs;
ordinary credited boards and paired credit extremes remain. Updated-app glyph/bounds proof,
with build and date, is pending on both the canonical 384×384 ROUND and existing 360×360
NOTROUND targets, including exhausted, positive-rounded-zero, unavailable, unknown, empty,
budget, refresh, Alerts and navigation cases. Historical measurements and readings above
remain evidence for their recorded builds and labels; source inspection establishes no new
art freshness, device-fit or runtime Pass.

## Revision 2026-10-19 — proportional native low-positive arcs

Actual **4% remaining** must paint its proportional family-coloured span. When two round
ends would consume the span, the native mini arc uses flat ends instead; it neither erases
the span nor inflates it with a percentage floor or minimum dot. Longer spans retain their
compensated round ends, clockwise-from-12 melt and near-full usage gap. The policy applies
to both pools of Cursor and Codex/Spark, including darker family colours.

True zero remains track-only `#2E3632`, with only its exhausted percentage token `#FFB4AB`.
A positive fraction rounded to `0%` retains its actual positive paint input and ordinary
token colour; this is not a promise that every subpixel span is visible. Fractions, rounding,
pair identities/order, credits, unavailable omission, three-row ceiling, 39-unit boxes and
5-unit strokes at design diameter 450, typography, 54-unit pitch, 12-unit Alerts clearance
and interactions stay unchanged.

**Acceptance: Pending.** `MiniRemainingArcPaintTest` exercises the production painter's
bitmap pixels at 384/450 and 360/450 scales, including 4% versus zero, the short-span
transition, both paired palettes, ordinary round ends and the near-full gap. Execution and
new native scene proof remain Pending on both shapes. Historical measurements and statuses
above remain evidence only for their recorded builds. Renderer/review-variant alignment,
paired SVG/PNG regeneration and integrated acceptance belong to the separate second task;
this native correction alone does not complete the 4% fix.

## Revision 2026-10-24 — larger Glance legend

**Historical first iteration, superseded below.** Runner commit `ff7cd209` and its later
reported HOST passes cover this 20/18 iteration only. Its measurements and execution-stage
Pending record below remain historical evidence, not acceptance of the clock-free refinement.

At design diameter 450 and default font scale, titles target **20**, secondary values **18**
and row pitch **62**, replacing 16/14 and 54. The centered block is at most **370 units** wide,
inside the existing horizontal content area. Each unchanged mini-arc occupies 39 units,
followed by a 12-unit gap: ordinary text has 319 units; paired text has 268. Short content
may use a narrower centered block. The target title/subtitle line boxes are 28/26 units,
with a 2-unit interline gap and no platform font padding.

Native measurement fits only the affected line, choosing the largest fitting size in
**title 18–20 / subtitle 16–18**. For the large compact credit example, the complete paired subtitle
`100% · 100% left · 999.9T credits` measures 279 at 18 and 266 at 17 in the accepted
Noto Sans Bold host measurements; these are design inputs, not Android ink measurements.
This test scene is not an upper bound: the compact formatter also permits larger T values.
Never change a value, remove a token or lower the fitting floor to manufacture fit.
If supported text still overflows, restart at the preferred size and wrap completely within
the same bounded range. Titles wrap at words; a paired subtitle first keeps its percentage
pair together and places purchased credits on the next line, replacing that separator with
the break. If the pair cannot fit at the floor, split between pools, inner first. An unusually
wide token may wrap by grapheme. Original numeric spans retain exhaustion coloring. Full
titles and original subtitle text remain accessible, including externally supplied titles;
the implementation wraps those titles too, without ellipsis or suffix removal.

Measure **every** complete row independently of width overflow. At system scale `s`, its
height is the maximum of 62×s, complete measured title/subtitle height plus their gap and
6×s breathing room, and the unchanged **39-unit arc floor**. Mini-arcs remain vertically
centered with their own labels. Preserve system font scaling. A width-fitting short row may
still require more height; do not wrap it merely to trigger the height fallback.

If the complete stack exceeds the actual weighted region, only the legend scrolls. Its top
stays below the actual header; its bottom ends at normalized **y=346**, 14 units inside the
region ending at y=360 and 26 above Alerts at y=372. Reserve six units inside the block's
right edge for the actual local-position indicator and clearance, leaving 313 ordinary /
262 paired text units. All selected rows remain reachable. Vertical drags/flings beginning
inside this viewport stay local even at both limits; outside gestures still page. Horizontal
back gestures and Pager accessibility page actions remain. Expose standard local forward/back
scroll actions and rotary scrolling when the legend owns focus, without requesting control
focus. Ordinary recomposition/status changes retain scroll position; shrinking content clamps
it, and a fitting stack returns to the centered presentation.

Refresh/status and Alerts retain their existing native/review-art control differences,
sizes, typography, anchors, hit areas, colors, cadence and navigation. Native metrics remain:
refresh 68, top clearance 62, detail 11 with gap 8, bottom clearance 42; Alerts height 36,
min/max width 128/200, font 16, padding/radius 18 and minimum clearance 12. Empty-state type
and placement remain unchanged. Three rows, tightest-first bands, pool order, known-zero and
low-positive behavior, names, credits meaning and unavailable-data handling are unchanged.
This revision does not address the separate double-back issue.

**Acceptance: Pending.** `GlanceLegendLayoutTest` adds native-font measurement assertions for
long titles, full paired credits, default refresh-detail clearance, bounded fitting, complete
wrapping with preserved exhaustion spans, short scaled rows that overflow by height alone,
and the sub-1.0 arc floor. It does not establish screen or gesture acceptance. Kotlin runtime
execution, review-art SVG/PNG regeneration and preview-to-board correspondence, full builds,
and actual consistent-state device review remain pending. The ordinary Runner generation
attempt completed real async Pillow measurement and SVG writes, then shared PNG export failed
with `spawnSync convert EPERM`. Its incomplete generated outputs were discarded; existing art
has not been refreshed for this revision. HOST must regenerate complete pairs with the unchanged
updated tool. Historical passes above do not establish any new pass.

HOST acceptance must cover round and nonround 360/384 scenes and the supplied OnePlus Watch 2
configuration (466×466, density 320, font scale 1.0, Wear OS 5; supplied facts, not a new device
observation). Compare fixed controls to the pre-change build at the **same** system scale.
At scales 1.0/1.5/2.0, cover one/two/three rows, both paired families, long Claude and Spark
titles, large/zero/absent credit balances, 100/100, 0/0, mixed 0/41 and positive-rounded-zero values,
unknown/unavailable/empty data, all refresh details and enabled/disabled multi-digit Alerts.
At 1.0, supported dense scenes must retain complete single lines and all three rows. At
1.5/2.0, verify both short single-line and wrapped rows, reach the final credit value and
return to the first row, and measure actual header, glyph/overhang, arc and circular bounds.
Include a scale below 1.0. Exercise drag/fling at each local limit, outside paging, horizontal
back, accessibility page/local-scroll actions, rotary focus, and retained/clamped position
through status updates and content changes. No build, generation or physical pass is claimed.

## Revision 2026-10-24 — clock-free Glance and larger legend

The Owner approved removing the clock from Glance and lifting its unchanged refresh control
to make room for larger, balanced text. This supersedes the preceding 20/18/62 targets,
370-unit width and top-62/clock constraint. The accepted design SHA-256 is
`fdc8ed44c8b344e64f2c30b76ac774a59aa2709ec74d1e1a32b45754ed822a12`.
It is design input, not native acceptance.

At design diameter 450, titles prefer **27**, values **23**, and rows **75 × system font
scale**. Keep bold type, contrast, palette and no platform font padding. Reserve full
**37/32-unit line boxes**, even when fitting reduces a line's font size, with **2 scaled
units between lines and 4 scaled units of total breathing room**. Measure every complete
row independently of wrapping: its height is the maximum of 75×s, the actual complete
title/subtitle reservations plus that gap/breathing, and the unchanged **39-unit arc floor**.
Independently round each full line reservation upward in pixels, then round the maximum
complete row upward; rounding only their combined height understates the stack.

The centered block is at most **360 units** wide. Each arc still occupies 39, with a 12-unit
gap, leaving **309 ordinary / 258 paired** text units. Shorter complete content may form a
narrower centered block. Fit only the affected line to the largest measured single-line
size in **title 18–27 / subtitle 16–23**. The host Noto Sans Bold input measures the usual
`Codex plan · Weekly` at 270 units (27) and `80% left · 59.5K credits` at 258 (23).
`Claude plan · Sonnet weekly` reaches 309 at 22, and the paired
`100% · 100% left · 999.9T credits` needs 16 (247 units). These are host metrics, not Android
ink proof or a universal credit limit; larger T values remain supported through fallback.
Preserve complete strings, unknown suffixes, credits, numeric values and exhaustion spans.
If single-line fitting fails at its floor, restart at the preferred size and use the existing
bounded complete wrapping strategy: words/graphemes for titles; keep paired percentages
together where possible, move credits to the next line, then split pools inner first if
necessary. Never ellipsize or lower the floors to manufacture fit.

The refresh plate remains **68 units**, centered at **(225,54)**, spanning **y=20–88**.
Only its top anchor moves. Preserve label typography, arrows, border, circle, actual native
hit region, colors, enablement, refresh action and phone-owned cadence. Native detail remains
type 11 with its existing 8-unit gap. Start the legend **10 units below the actual measured
header bottom**, including any detail; do not infer detail height from its font size.
The non-scrolling region ends at **y=360** and centers the complete stack. Empty/no-selection/
unavailable Glance retains its copy and type 16, centered in this newly available region.
Alerts stays exactly at **top 372, height 36**, with 42 bottom clearance, font 16,
min/max width 128/200, padding/radius 18, the existing border/colors/hit region/actions, and
its 12-unit gap after the weighted region. Preserve native/review-control style differences.

Without detail, the nominal region is y=98–360. With a conservative 16-unit native detail
line, it is y=122–360: three 75-unit rows center at y=166/241/316, with their final text
ending y=351.5. The 360-unit block has about 6.072 units of horizontal circular clearance
there. The moved refresh circle has 20 units of radial clearance. These are design bounds,
not proof of glyph overhang or an expanded touch rectangle. At diameter 360/384/466, the
independently rounded modeled rows are respectively **61/66/80 pixels**, with three-row
stacks **183/198/240** against conservative detail heights **190.40/203.09/246.46**.
Actual native header, line bounds and constraints are authoritative. The ordinary default
Cursor 100/64, Codex 80 with 59.5K credits, Claude 100 three-row scene must show the full
strings at 27/23 without local scrolling, both with and without detail. Report any native
failure to fit; clipping or scrolling does not replace that acceptance requirement.

Preserve system scaling, including below 1.0. Arbitrarily long or enlarged rows may overflow
by height even when their widths fit. Scroll **only the legend**, from actual header-plus-10
to normalized **y=346**, reserving the same six units for its actual position indicator:
**303 ordinary / 252 paired** text units. Keep every row/value reachable; no control moves
with scrolling. Retain local vertical drag/fling consumption at both limits, outside paging,
horizontal back, standard local accessibility scroll actions, Pager page actions, focused
rotary input without control focus stealing, stable-identity position retention and
clamping/reset when content shrinks or fits. The separate double-back defect is unchanged.

Clock visibility follows the actual destination, home Pager and summary state. Hide it on
summary-backed Glance in every refresh, known-zero, no-selection and unavailable-row state.
Keep it on Plan windows, Alerts, Watch face utility and pre-summary Empty Dashboard,
including when another route retains Glance underneath. Cold start, summary arrival/loss,
navigation/back, paging, restoration and recomposition must not leave a stale clock over
the raised control or hide it globally. Hide it while the Home Pager moves so an in-flight
Glance cannot receive an overlay; restore it on settled Plan windows. WFF and other-page
clock typography/layout are unchanged. Each destination owns its clock inside its own
`AppScaffold` within the navigation host. Back dismissal therefore moves/clips the foreground
clock with that page, rather than leaving a shared overlay on the Glance revealed underneath;
cancelled dismissal restores the foreground clock with its page. This applies to both legacy
horizontal swipes and API 36+ predictive-back previews without tracking private host state.

**Initial acceptance plan, 2026-10-24: Pending at that record.** `GlanceLegendLayoutTest` reserves independently rounded
37/32 lines and complete rows, checks the ordinary preferred-size scene and dense fitted
examples against the measured-detail model at 360/384/466, and retains wrapping, exhaustion,
height-only overflow and small-scale arc coverage. `WardPulseNavigationStateTest` adds one
bounded integration case using synthetic in-memory summaries and composition-local 2×
text scaling. It identifies the local legend separately from the Home Pager, invokes real
`AccessibilityNodeInfo.ACTION_SCROLL_FORWARD` / `ACTION_SCROLL_BACKWARD`, checks visible
content movement both ways and Glance isolation, then invokes Pager `ACTION_PAGE_DOWN` /
`ACTION_PAGE_UP` and checks page changes/return. It also checks meaningful clock visibility
through summary/recomposition,
empty selection, Alerts/utility/back and retained Pager transitions, without exact times,
device setting changes or sleeps. A focused case in that same harness additionally holds a
back preview from Alerts over Glance, verifies that the clock moves/clips with the dismissing
page, then checks cancellation restoration and completed dismissal. It injects horizontal
touch events on legacy hosts and uses the Activity's predictive-back dispatcher on API 36+;
frames and accessibility publication synchronize assertions. Only actual HOST execution can
establish these results.

The recorded **2026-10-24 authoring generation attempt** completed async Pillow metrics
and SVG writes, then failed at shared PNG export with `spawnSync convert EPERM`. That failure
describes that attempt, not the later admitted artwork in the reviewed checkout. The
2026-10-25 integration preserves that checkout's bound SVG/PNG bytes; its primary
`glance-legend-3.svg` uses 27/23. It imports
the face peer's awaited asynchronous preview helper, whose API the newer Glance generator
already awaits. No artwork is regenerated by this import, and SVG typography alone does not
prove PNG correspondence or native fit. After DONE, CLI exit and separate public retirement,
HOST runs the full unchanged design drift check and inspects preview/board correspondence.
Any necessary regeneration remains owning Runner work, outside this import; HOST regeneration
is not authorized by the integration task.

Rerun complete Wear/phone/docs gates, relevant skill validation, measurement/navigation and
the actual local/Pager accessibility-action case after that boundary. Measure actual header,
line ink/overhang, complete rows, circle and control click/accessibility bounds on 360/384
round/nonround targets and the supplied physical OnePlus 466×466/density 320/font scale 1.0/
Wear OS 5 watch. Compare the unchanged control styles/actions at the same system scale;
refresh position intentionally differs. Cover matched ordinary detail/no-detail scenes,
long Claude/Spark and external labels, paired large/larger-T/zero/absent credits, 100/100,
0/0, 0/41, positive-rounded-zero, budgets, empty/unavailable and every refresh detail.
At 1.5/2.0 and below 1.0, exercise complete reachability, drag/fling at both limits,
outside paging, back, actual accessibility actions and focused rotary input, with controls
stationary. Verify the clock matrix and safe state restoration. Preserve the pre-upgrade
failure-witness prerequisite and all conditional project gates. Root owns healthy same-state
screenshot cohorts/index and final website/browser description review. Record real build/date
results; no new runtime, physical, action, generation or visual pass is claimed here.
Widget, WFF, version 0.1.0 and all other backlog work remain outside this refinement.

**HOST acceptance record, 2026-10-25.** Before the harness-only corrections, the reviewed
Round native suite passed **32 tests in 47.793 seconds**.
`WardPulseNavigationStateTest` passed **12 tests in 44.581 seconds** on Square and **12 tests
in 38.891 seconds** on API 34, including the distinct local/Pager accessibility actions.
`just check-wear`, `just check-watchface`, `just check-designs` and `just validate-fixtures`
passed. The seven fresh same-session public frames now show matching selections after
the combined face correction. Capture/build scope is recorded in
[the screenshot index](../assets/README.md#shared-state-capture-refresh-2026-10-25).
Physical 466 active Glance and Face were verified with security enabled, keyguard hidden,
AC power true and FULL 100%; these diagnostic frames do not establish fresh provider data.
Round 384 Face AOD passed independent review, which does not establish Glance or physical AOD.
Public browser review passed all 15 routes in both themes, image/original links, menu and
anchors, with 35 served PNGs matching canonical bytes and no outstanding link issues.
Unchanged runtime-face, face-review and Glance-review generators exited normally in a
task-owned throwaway checkout; all 136 outputs matched the reviewed checkout, without
canonical regeneration. The bounded Reader and gate corrections completed through their
owning executions. The complete canonical phone/Wear `just test-phone-watch-sync` HOST run
passed after fresh Reader Java/DEX and Flutter builds and a renewed 32-test Wear suite.
All 16 Reader cycles returned complete headers with wrapper exit 0. Three quiet pre-death
observations preceded successful initial process deaths, delivery/relaunch,
retention and final saved-summary preservation. This is acceptance of that canonical pair.
The earlier post-update WorkManager service start was observed, but which job or worker
triggered it, including attribution to job1969, remains unproved.
These receipts do not certify the remaining historical interaction/variant matrix below.

## Revision 2026-10-28 — compact no-summary Watch face action

The pre-summary Empty Dashboard keeps its WardPulse heading, Sync from phone /
No dashboard data yet prompt and straight clock. Below the sync card, show one full-width,
label-only native tonal CompactButton named Watch face. Its component default has a
32dp visible surface and 48dp allocated tap area, including surrounding tap padding;
these are component contracts, not application measurements or a reduction percentage.

Use the ordinary native tonal Button for the same action when measured full label width
or full line height cannot fit the compact content box. Preserve the complete wrapping
label, system font scaling, native minimum touch sizing and content-sized height. Do not
shrink text, ellipsize it, choose an arbitrary font-scale cutoff or add an inner scroll area.

Give the retained clock and scrolling content distinct visual space. At every reachable
settled position, including both scroll limits, no heading, prompt, action label or surface
may paint over the clock. A heading may leave the visible list naturally during scrolling;
its departing paint must clear the clock rather than remain visible behind or across it.
Keep the heading and the start of the sync prompt readable initially. All prompt text must
remain readable through ordinary scrolling, across multiple settled positions when enlarged
text requires it. Keep the separation compact and native, without an arbitrary empty band.
The historical utility-end overlap from October 16 does not establish acceptance of this
pre-summary screen.

Preserve existing typography and system scaling. Normal list, rotary and accessibility
scrolling must make every part of the prompt readable, across multiple positions if needed.
The complete Watch face action and label must be revealed together at a settled usable
position within the actual viewport, retaining its padded touch area. The Plan windows
action retains its Card; Plan windows, Alerts, the Watch face utility and summary-backed
Glance keep their existing presentation and behavior. The destination clock matrix remains
unchanged: the pre-summary clock is visible, and removing it or globally hiding the heading
is not a solution to overlap.

This remains one enabled navigation action to the existing Watch face utility, available
before first sync regardless of installed, active, missing or unknown face status. It does
not itself install, update, activate or request permission. Back, summary transitions and
the utility's retained route, consent and status behavior keep their existing contracts.

**Emulator HOST acceptance, 2026-10-28.** The reviewed working-tree candidate based on HEAD
`eb0a371` used `WardPulseApp.kt` SHA-256
`e83faed21ab04553d3e3e7c87dc2be5d01c39d6b9ef337671a6900deffedc038` and
`WardPulseNavigationStateTest.kt` SHA-256
`953aa9f4d7dac3221d70652f9bca74eae94fd4d65f71d42de7c4909a9def83bb`.
`just check-wear` passed in 27 seconds. The full round suite passed
**39 tests, 0 failures/errors/skips**, taking
75.025 seconds on HOST and 61.856 seconds in JUnit. Four focused square cases passed in
9.8265 seconds. The actual OS-font-2.0 inherited-font case passed separately on Round in
6.8994 seconds and Square in 9.2677 seconds. Installed APK SHA-256 values were app
`5592dd766852d0f62e5a1035219dcbc1d6a67e33b228095c4166710abab5e77c` and instrumentation
`b6ad8829a17483e8cceac783ea24daa4b37faa0ba51934a167d5a34d0a3ccd2f`.

SDK 36 round **384×384 px / 192dp** and square **360×360 px / 180dp** targets at 320 dpi
were checked at actual system font scales **1.0 and 2.0**. Root reviewed all **22** full,
unedited native originals: the initial heading, prompt start and painted clock were
readable and clear; a genuine settled interior, both actual physical limits and the
after-Back start were observed separately. Every prompt line was readable through ordinary
scrolling, and the complete action/label was usable together at a settled position; an
oversized prompt was not required to fit one viewport. Initial readability was not equated
to the exact physical-start boundary. The 48dp finger case and padded touch, 80dp-wide
full-text fallback, injected 2.5 font-scale case, platform scrolling, button activation, navigation,
Back and summary transitions passed their required checks. The injected 2.5 case is separate
from the actual OS-font observations; the 32dp/48dp component defaults remain distinct from
case geometry.

Both targets returned to system font scale 1.0 with prior settings, UID/first-install
identity and saved summaries preserved; normal app presentation was restored. This is
emulator-native acceptance. Physical OnePlus verification remains deferred by the owner.
The full citation/documentation build and Watch-guide browser review passed before this
factual status update. Root reviewed four full browser originals in actual light/dark
themes at **1365×1000** desktop and **390×844** mobile sizes: the task paragraph and anchor
were readable without horizontal overflow, and the existing utility image matched.
Root's final whole integration review and documentation recheck follow this status update.
No new public no-summary image or screenshot freshness is claimed.

## Goal

Name each selected band with its provider/family, show remaining % and optional
per-provider purchased credits, and keep one mini-track per known pool beside its row so the
user can map face colors to providers.

## Composition

```text
      (↻ OK )                ← OK / !OK inside dual-arrow refresh glyph
      [detail]               ← optional; only for problems (Stale, Rate limited, …)

  (●)  Codex plan · Weekly   ← tightest remaining on top (same payload as face center)
       8% left · 320 credits

  (●)  Claude plan · 5h
       39% left · 80 credits

  (●)  Cursor Models
       53% left

      [ Alerts: 0 ]          ← pill button; disabled when N = 0
```

Rules:

- One row = one selected band from the watch summary (same set and order as the face).
- Row order = **tightest remaining first** (highest `usedPercent` first; equal percents break
  ties by credit request-runway from internal costs — credits shown, not request counts),
  matching the face. A pair keeps its band position and uses **one row**. Its two mini arcs
  and percentages always put the inner pool first (left), outer pool second (right),
  independently of which percentage is tighter.
- Mini arc = **remaining** (`100 - usedPercent`), family color from the face palette and the
  same clockwise-from-12 melt as the watch face (usage gap opens at 12). Longer spans
  compensate the round caps' half-stroke reach by drawing the sweep short by one cap at
  each end; without that a nearly full row reads as a closed ring (`WATCH_RING_DESIGN.md`,
  Ring geometry). If those two cap allowances would consume the span, use flat ends and
  the actual proportional sweep instead. Actual 4% remaining must paint family colour;
  no percentage floor or minimum dot is permitted for short spans.
  At known exhaustion, keep only the existing grey track `#2E3632`, with no coloured arc.
  Positive fractions that round to `0%` keep their positive paint input and ordinary label
  colour, without a universal subpixel-visibility guarantee.
- Primary line for a pair: **family name + ` plan`**, exactly `Cursor plan` for Cursor and
  `Codex plan` for Codex/Spark.
  The phone uses the same rule for its band label; the payload carries pool labels, not a
  separate band name. Ordinary recognized Claude windows use `Claude plan · 5h`,
  `Claude plan · Weekly`, `Claude plan · Opus weekly` or `Claude plan · Sonnet weekly`;
  Codex main uses `Codex plan · 5h` / `Codex plan · Weekly`. Recognize the known legacy raw
  Codex `Weekly plan` as `Weekly` only in presentation. Other ordinary labels keep the existing
  family/provider + metric form; unknown suffixes are never stripped, and already named or
  externally composed labels and budgets stay intact. Cursor Pro+/Ultra plan pools retain
  distinct `Cursor Models` / `Other Models` names (known exhausted pools remain visible).
  Codex main and Spark windows collapse independently; an unpaired Spark row names
  its winning window (`Codex plan · Spark 5h` / `Codex plan · Spark Weekly`). If a partner is
  unavailable, name the actual surviving window or pool rather than the complete pair.
  Claude’s subscription plan windows (`5h`, `Weekly`, optional Opus/Sonnet weekly) collapse to
  **one** ring on the phone, choosing the tightest known window including zero; Glance names
  that window with the plan wording above. Equal known percentages retain the existing
  priority: `5h`, `Weekly`, `Opus weekly`, `Sonnet weekly`. Unknown windows cannot beat a known zero.
- Secondary line: ordinary rows keep `N% left`. A pair shows `82% · 41% left`, inner pool
  first, with one `left` applying to both remaining percentages. Append purchased credits
  once when available: `82% · 41% left · 320 credits`. Per provider only — not a footer sum,
  not face `creditsGlance`, never LLM `TOK`.
- At actual exhaustion, colour **only the `0%` token** pale red. Keep `left`, separators,
  credits (including `0 credits`), the row title and every positive percentage in their
  normal colours. `0% · 41% left` highlights only its first token; `0% · 0% left` highlights
  both. This does not create an alert, alter refresh state or infer a user threshold.
- The credit balance is **compact**, the face strip's own form, with the unit word after it:
  `62.5K credits`, `1K credits`, `320 credits`, `0 credits`. A provider's trailing decimals
  never reach the row, and the number never differs from the one the face shows for the same
  band (revision 2026-10-11 above). A balance the provider denominates in anything but credits
  is not shown at all — the suffix is omitted as for an unavailable one, never relabelled.
- Rows target **75 units × system font scale**, with independently rounded complete height
  and the 39-unit mini-arc floor, following the clock-free October 24 revision above. Titles
  target 27, subtitles 23, with bounded fitting and complete supported-token wrapping.
- The block keeps **12 units clear of the Alerts pill**. Three rows is the ceiling, one per
  band, regardless of how many bands are paired. The 2026-10-01 round/notround measurement
  records the earlier three-row fit; fit and glyph bounds for the revised titles remain
  **Pending** on both screen shapes.
- Empty selection or unavailable data: short copy centered between refresh and Alerts;
  no fabricated placeholder rings. Selected known zero is a row, not an empty state.

| Empty state | Copy |
|-------------|------|
| No rings selected | `Choose percent rings` / `in the phone app` |
| Selected ring entries, but no known usable percentages | `Ring data unavailable` |
| All selected known metrics exhausted | Keep every selected row, grey tracks and pale-red `0%` tokens |

## Refresh status control

Circular **refresh** control: `OK` / `!OK` in the open center of a dual-arrow ring (not stacked
outside the glyph). Review art: butt-capped arcs, miniature chevrons inside the plate, same
label size for `OK` and `!OK`. Optional problem detail sits below the plate (muted `#5C655E`),
never on the ring. Tap → phone sync request; `PollCadence` decides if it runs.

| Pulse | Label | Accent (when enabled) | Meaning |
|-------|-------|------------------------|---------|
| Healthy | `OK` | `#65D78A` (green) | Overall sync status is ok — intentional exception to olive phone chrome |
| Anything else | `!OK` | `#E6C349` (orange / warn) | Stale, warning, error, auth, mock, provider rate-limited, … |

Pulse (`OK` / `!OK`) and interactivity are **independent**:

| State | Pulse | Control | Detail |
|-------|-------|---------|--------|
| Healthy, refresh allowed | `OK` (green) | Enabled | none |
| Healthy, cadence cooldown | `OK` (gray) | **Disabled** | none — still on plan; manual sync not allowed yet |
| Problem, refresh allowed | `!OK` (orange) | Enabled | e.g. `Stale` |
| Provider rate-limited | `!OK` (gray) | **Disabled** | `Rate limited` |

- When a **specific problem** is known, show it under the control (`Stale`, `Auth required`,
  `Rate limited`, `Mock data`, …). Keep the primary glyph as `OK` / `!OK` only.
- Cadence cooldown is **not** a problem — do not show `Rate limited` or flip to `!OK` for it.
- Only **one** detail fits, so problems have a precedence: `Mock data`, then `Stale`, then
  `Rate limited`, then the remaining statuses. Trustworthiness of the numbers outranks the
  reason a refresh failed, because a rate limit already shows as a gray disabled control while
  age has no other channel. Precedence changes the detail line only — the control still follows
  the rate limit.
- The **phone** decides allowance from the **PollCadence hard floor** (strictest provider
  minimum, currently 5 minutes) — not the Settings auto-poll slider — and pushes
  `manualRefreshAllowed` / `manualRefreshAvailableAt` on the watch summary. Wear reflects those
  flags (and may re-enable when wall clock passes `manualRefreshAvailableAt`); it must not invent
  a separate local cooldown that can disagree with the phone.
- **Enabled**: accent stroke + label; tappable → phone refresh request.
- **Disabled**: muted gray stroke + label; non-interactive.

## Alerts button

Footer pill `Alerts: N`:

- `N > 0`: active (warning stroke, readable label); tappable → Wear **Alerts** screen
  (active list only).
- `N = 0`: disabled / non-interactive (muted fill, muted label, quiet stroke).

## Family colors

Same strokes as the face (`WATCH_RING_DESIGN.md`) for metric mini-arcs:

| Family | Stroke |
|--------|--------|
| OpenAI / Codex | `#65D78A` |
| Codex · Spark | `#186020` |
| Anthropic / Claude | `#E8915A` |
| Cursor · other models | `#67E8D4` |
| Cursor · own models | `#7E93B8` |
| Unresolved family | `#8A968F` — fallback only |

A local budget row takes the family color of the connection it belongs to; the period lives in
the row label, not in a color of its own. **Cursor pools or Codex main/Spark limits share one row**,
each with its own grey mini-track, positive remaining arc and remaining fraction. The pair reaches the watch as one
payload entry with its second pool inside (`WATCH_RING_DESIGN.md`, Split band). When either
pool is exhausted, retain both known pools, their fixed mini-track positions and both
percentage tokens; the positive half keeps its coloured arc. When both are exhausted the
row remains with two grey tracks and `0% · 0% left`. An unavailable half is absent and its
known survivor becomes an ordinary pool row; two unavailable halves yield no row. Purchased credits appear once per
row — a split face strip gives its width to the second percentage instead.

Refresh `OK` reuses Codex green as status affordance on this control only — do not spread that
into Alerts chrome or general Wear buttons. Surface / track / label match face review art
(`#101412` / `#2E3632` / `#F4FBF8`). Font: Noto Sans Bold in review art.

## Review variants

```sh
node tools/render-wear-glance-designs.mjs
xdg-open apps/wear_android/design/preview-glance-legend-3.png
```

The table describes the current generator variants. Regeneration of all affected SVG/PNG
pairs and preview-to-board review for the October 17/19/24 revisions are **Pending**; existing
art and historical device readings do not establish acceptance of the revised legend.
The synthetic 1.5×/2× boards model legend text scaling and local scroll positions only;
they retain the existing review-control rendering and are not native full-screen font-scale
or gesture evidence. Real native controls must be compared at the same system scale.

**2026-10-19 renderer correspondence:** `miniArc` now follows the native proportional
Butt/compensated Round cap policy above, including track-only zero. The two low-positive
Source variants use 96% used for 4% remaining and 100% used for true zero. Their normal PNG
companions and all affected SVG/PNG pairs await external regeneration and full review;
integrated acceptance remains **Pending**.

| File | Meaning |
|------|---------|
| `glance-legend-max-credits.svg` | Synthetic default-scale example with both paired families, long Claude title and complete `100% · 100% left · 999.9T credits`; this large compact credit balance is not an upper bound |
| `glance-legend-text-scale-150.svg` / `glance-legend-text-scale-200.svg` | Synthetic legend-only text scaling with wrapping, actual modeled local-position indicator at start/end, fixed review controls; generation and native acceptance Pending |
| `glance-legend-3.svg` | **Primary** — three providers, `OK` refresh enabled, Alerts disabled |
| `glance-legend-1.svg` | Single provider with credits |
| `glance-legend-pair.svg` | One Cursor pair — one row, two coloured arcs, inner-first percentages and credits once |
| `glance-legend-full.svg` | Three-row ceiling: longest `Claude plan · Sonnet weekly` plus complete credited Cursor and Codex pairs. Preserve the paired credit extreme (`100% · 75% left · 62.5K credits`) and ordinary `320 credits` pair; revised art and device fit Pending |
| `glance-legend-budget.svg` | Plan rows (with credits) + a connection budget row (family color, no credits) |
| `glance-legend-stale.svg` | `!OK` + detail `Stale`, refresh enabled, Alerts active |
| `glance-legend-cadence.svg` | Healthy `OK` but refresh **disabled** (cadence cooldown; no detail) |
| `glance-legend-rate-limit.svg` | `!OK` + detail `Rate limited`, refresh **disabled** (provider) |
| `glance-legend-empty.svg` | No rings selected; centered copy; `OK` refresh |
| `glance-legend-exhausted.svg` | All selected metrics exhausted; retained rows with grey tracks and pale-red zero percentages |
| `glance-legend-claude-zero.svg` / `glance-legend-3-claude-zero.svg` | Claude 5h zero alone and in the three-band ceiling |
| `glance-legend-pair-inner-zero.svg` / `glance-legend-pair-outer-zero.svg` / `glance-legend-pair-both-zero.svg` | Fixed paired identities with either or both known pools exhausted |
| `glance-legend-two-pairs-zero.svg` | Three rows including two exhausted pairs |
| `glance-legend-low-positive-inner.svg` | Ordinary Claude 4% remaining; Cursor Models / Other Models and Codex / Spark each 4% / 0% remaining |
| `glance-legend-low-positive-outer.svg` | Ordinary Claude true zero; Cursor Models / Other Models and Codex / Spark each 0% / 4% remaining, including dark Spark |
| `glance-legend-positive-rounds-zero.svg` | Positive arc geometry with ordinary `0%`; subpixel visibility is not asserted |
| `glance-legend-zero-credits.svg` | Red `0%`, neutral `0 credits` |
| `glance-legend-unavailable.svg` | Selected entries have no known percentage; `Ring data unavailable` |
| `glance-legend-unavailable-inner-zero-outer.svg` | Invalid inner value omitted; zero outer survivor retains `Cursor · Other Models` |

Wear only: `apps/wear_android/design/`. OpenPencil `.fig` inventory optional.

## Acceptance (locked)

```text
text legend + mini remaining arcs (not a face clone)
one row per band, at most three rows; band order matches the phone/face
paired arcs and percentages: inner first, outer second; each retains its own colour
paired title = family + " plan"; Cursor plan and Codex plan exactly
paired subtitle = "82% · 41% left · 320 credits" (omit credits suffix when unavailable)
legend target 27/23, bounded title 18–27 / subtitle 16–23 fitting; maximum centered width 360
scaled 75-unit pitch; independently rounded 37/32 line reservations and complete rows; 39-unit arc floor
supported overflow wraps completely, preserving original numeric colors and accessibility text
height overflow scrolls only the legend, ending at y=346 with six units reserved for its indicator
local vertical drag/fling isolation at both limits; outside paging and horizontal back preserved
standard local accessibility scroll actions and focused rotary scrolling; retained/clamped position
refresh/status size/style/actions unchanged, top 20; Alerts unchanged at y=372; minimum 12-unit clearance
legend begins 10 below actual header; empty-state copy/type unchanged, centered in the new region
clock absent only on summary-backed Glance, including empty selection; other-page clocks retained
ordinary default three-row/detail scene must fit fully at 27/23 without local scrolling; dated HOST record above
revised glyph/bounds and interaction proof: dated AVD results above; physical hardware still Pending
per-provider credits with explicit credits label (no footer sum)
credit balance compact, as the face strip renders it: 62.5K credits / 1K credits / 320 credits / 0 credits
a purchased balance in any unit but credits is omitted, never shown bare or relabelled
OK / !OK inside dual-arrow refresh glyph; same label font size
optional muted problem detail below the plate (never on the ring)
cadence cooldown = gray OK + disabled (no detail)
provider rate limit = gray !OK + Rate limited + disabled
phone owns allowance via summary manualRefreshAllowed / manualRefreshAvailableAt
Stale = orange !OK + Stale + enabled
Alerts: N pill; active when N > 0; disabled at 0
empty selection / unavailable data centered copy between refresh and Alerts
ordinary recognized titles: Claude plan · 5h / Weekly / Opus weekly / Sonnet weekly; Codex plan · 5h / Weekly
legacy Codex Weekly plan recognized as Weekly for presentation only; payload unchanged
unpaired Spark keeps Codex plan · Spark 5h / Spark Weekly; unavailable partner leaves actual surviving window
unknown / budget / externally composed labels preserved; Cursor Models / Other Models stay distinct
selected known zero stays a grey mini-track and a row with pale-red 0% only
one or both exhausted known halves keep paired tracks, fixed identities and both percentages
unknown/unavailable is absent, never fabricated as zero; tiny positive fractions stay ordinary
native low-positive arcs retain proportional span without a floor/dot; short ends may be flat, long ends round
native pixel regression and both-shape 4% scene proof: Pending
review art: render-wear-glance-designs.mjs → preview-glance-legend-*.png
revised SVG/PNG generation together, preview-to-board review and updated-app acceptance: Pending
2026-10-19 low-positive inner/outer Source variants: ordinary and both paired families at 4% versus true zero
low-positive renderer/variant SVG/PNG review and integrated acceptance: Pending
primary preview: preview-glance-legend-3.png
```

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app Glance (page 1) | This legend + refresh control + Alerts button |
| Wear OS app second page | Plan windows and when each comes back (`apps/wear_android/README.md`) |
| Wear OS app Watch face utility | Swipe-back setup route after all Plan windows rows, also below the no-summary sync prompt; separate from the two home pages |
| Phone | Owns PollCadence floor for Wear taps; pushes `manualRefreshAllowed` /
  `manualRefreshAvailableAt`; Settings slider drives automatic polling only |
| WFF / face | [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) — concentric remaining arcs |

## Non-goals

- Reusing face sunk strips, watermark, or full-face concentric rings on Glance.
- Large remaining-% as the aperture hero on Glance.
- Shared footer credit sum that hides which provider owns the balance.
- Credential entry or settings on Wear.
- Editing alert rules on Wear (list only).
- Wear performing provider HTTP sync itself.
- Wear inventing a local PollCadence / interval cooldown that can disagree with the phone.
- Treating cadence cooldown as `!OK` or `Rate limited`.
