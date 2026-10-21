# Wear Glance Design

**Baseline locked 2026-07-26** — accepted visual target for the Wear OS **app** home Glance
(first page after opening the tile) until the next explicit design revision. Distinct from the
watch-face baseline in [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md): this screen is a
**text legend** for face ring colors, not a face clone.

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
Typography, mini-arcs, 54-unit row pitch, 12-unit Alerts clearance and the three-row ceiling
stay fixed; no font shrink, Clip workaround or geometry change is accepted.

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

## Goal

Name each selected band with its provider/family, show remaining % and optional
per-provider purchased credits, and keep one mini-track per known pool beside its row so the
user can map face colors to providers.

## Composition

```text
        9:06
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
- Rows are laid out on a **54-unit pitch** with nothing added between them: the pitch already
  covers the mini arcs and both lines.
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
pairs and preview-to-board review for the 2026-10-17 titles are **Pending**; existing art and
historical device readings do not establish acceptance of the revised titles.

**2026-10-19 renderer correspondence:** `miniArc` now follows the native proportional
Butt/compensated Round cap policy above, including track-only zero. The two low-positive
Source variants use 96% used for 4% remaining and 100% used for true zero. Their normal PNG
companions and all affected SVG/PNG pairs await external regeneration and full review;
integrated acceptance remains **Pending**.

| File | Meaning |
|------|---------|
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
fixed typography and mini-arcs; 54-unit row pitch; 12-unit Alerts clearance; no font shrink or Clip workaround
revised-title glyph/bounds proof with build/date on round 384 / notround 360: Pending
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
