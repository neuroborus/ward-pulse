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
splitting the time) — accepted visual target for Wear OS and Watch Face Format until the next
explicit design revision.
Implementation and review art must follow this document; do not reintroduce side-by-side ring
wireframes, large remaining-% heroes, or bordered strip cards.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-watch-ring-designs.mjs`  
Canonical face generator: `tools/render-watchface.mjs` — it writes the shipped `watchface.xml`
and the ring-type drawables beside it.  
Canonical preview: `apps/wear_android/design/preview-3-plan-credits.png` (and sibling variants).

**Revision 2026-09-16 — Codex/Spark pair:** Codex plan windows collapse per limit,
then the main limit and Spark may share one band. The main limit is inside/left;
Spark is outside/right in `#186020`. Geometry and typography are unchanged. Both
pairs and far markers, Glance clipping and visual fit are **deferred until live-data
verification**; this revision records no new device measurements.

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
   Claude plan slot and resolves it to the tightest remaining window (window name lives on Glance,
   not on face strips).
   The two Cursor pools or the main Codex and Spark limits may share one band at
   **drawing** time, split lengthwise (see Split band). Each pair stays one slot.
2. **Arc = remaining** — the colored sweep is `(100 - usedPercent)`. As the limit is consumed, the
   arc shrinks (do not grow a separate “used” fill). Melt is **clockwise from 12**: usage opens a
   gap at 12 o’clock and advances like a clock hand; remaining stays anchored ending at 12.
3. **Center / inner = tightest remaining** — among selected, available, non-exhausted metrics,
   sort by plan remaining ascending (equivalently highest `usedPercent` first). When plan
   percents tie, secondary sort uses estimated remaining **request-equivalents** from that
   provider’s purchased credits (`credits /` internal credits-per-request constants — sort only,
   never shown as requests). Strips still show credits only. Payload index 0 is the critical
   limit: innermost ring and the strip nearest the center. Outer rings are looser.
4. **Omit exhausted** — `usedPercent >= 100` (or empty/unavailable) does not render.
5. **Max three** — phone **Watchface** tab chooses slots (`watchRingSlotCount = 3`); payload carries
   only the resolved surface order after omit + sort. Plan/budget percent metrics only. A split
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
Bold/700 for time and strip labels. Vertically center strip glyphs using font metrics (not a
guessed baseline fraction).

Runtime Wear/WFF may map to the closest platform sans until a bundled Noto Sans asset is wired.

## Provider / metric colors

Primary stroke / accent color is by **family**, not by status alone. Status (warn / error / auth)
may modulate toward theme tertiary/error when needed.

| Family | Stroke | Notes |
|--------|--------|--------|
| OpenAI / Codex | `#65D78A` | Green |
| Codex · Spark | `#186020` | Dark green — the Spark limit on the Codex plan |
| Anthropic / Claude | `#E8915A` | Orange (Anthropic presentation) |
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
  ┌──── remaining arcs (0–3 slots; hard max three) ─────────────┐
  │                                                              │
  │        upper aperture: weather reserve (empty)               │
  │                                                              │
  │                       10:08                                  │  ← large time (hero)
  │                   WARDPULSE watermark                        │  ← quiet mono, no ring
  │            ┌─ sunk well ──────────────┐                      │
  │            │▌ 8% · 500                │                      │  ▌ = family accent
  │            │▌ 39%                      │                      │
  │            │▌ 72%                      │                      │
  │            └──────────────────────────┘                      │
  └──────────────────────────────────────────────────────────────┘
```

Rules:

- **Time is the hero** — optically centered; not a large remaining %.
- **Upper inner rim** reserved for a future weather glance (no placeholder chrome yet).
- **Watermark** — ringless mono `WARDPULSE` + pulse/eye between time and strips; low PartImage
  alpha with a bottom dissolve into the strip stack. Same faded PNG is reused on the phone
  home widget (day/night tint). Details: `docs/DESIGN_ASSETS.md`.
- **Lower strips** — short rounded rectangles, not full-width tablets and not stadium pills:
  - sunk into the surface (dark well, no high-contrast border card);
  - thin left **family accent** bar (same ColorRamp / `ring.id` family as the matching arc);
    WFF strip slots are `RANGED_VALUE` so accents use `[COMPLICATION.RANGED_VALUE_COLORS]`;
  - **equal width** for every strip in the stack, sized for the worst-case center
    label `100% · 10.0M` (compact `K`/`M`/`B`/`T` credits) so wells stay inside the
    clear aperture and do not cover arcs;
  - measured horizontal padding so Bold labels clear the well edges;
  - strip order = tightest remaining on top (nearest center) when plan rings exist;
  - content: `%`, or `% · credits` when that strip’s provider family reports purchased remaining
    (per-provider from `allowances`, same as Glance — not gated on aggregate `creditsGlance`);
    omit unused halves / omit empty strips;
  - **budget strips are the one exception to the remaining language** — they read spend of
    limit (`$12.34/100`), because a budget ceiling is a number the wearer typed and money is
    how the product already names it everywhere else; the arc above still melts by remaining.
    Spend keeps cents, the limit is whole (rounded to nearest): cents on both halves
    (`$999.99/999.99`) are 14 % wider than the worst credits label and would force the strip
    geometry open, while the worst budget label `$999.99/999` still fits. Currency travels as
    a code in the payload and Wear spells the symbol — a `$` baked into the watch would be a
    lie the day a connection bills in something else. A currency with no one-glyph symbol on
    the watch falls back to the plain `%` label rather than a spelled code: `EUR 999.99/999`
    is 118 % of the locked width, worse than the form the rule already rejects;
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
   and Codex main/Spark limits. Everything else stays one ring, one metric.
   The Watchface tab offers each pool as its own row: **ticking both** is what shares a band —
   either alone is an ordinary, undivided ring. A pair costs one of the three slots, which is the
   whole point: a plan with two pools does not cost two.
   Codex windows collapse independently to `allowance.codex.plan` and
   `allowance.codex.spark`, choosing the tightest non-exhausted window per limit;
   ties prefer primary. Empty limits offer no ring, unavailable limits remain disabled,
   and fully exhausted limits are omitted from the face. The picker keeps `Codex plan`
   and `Codex · Spark` stable; the winning window remains in the subtitle and payload.
   Old per-window Watchface selections migrate before deduplication and the band budget;
   widget selections remain per-window. Spark window labels are `Spark 5h` / `Spark Weekly`.
2. **The order inside a pair is fixed by pool, never by usage.** Cursor own models take the
   inner half and left marker; external models take the outer half and right marker. Codex main
   takes inside/left, Spark outside/right; its darker `#186020` reads on the longer outer arc.
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
   token: `cursor-other` selects static `#67E8D4`, and `spark` selects static `#186020`.
   An empty or unknown token paints no far marker. The inner accent keeps `[COMPLICATION.RANGED_VALUE_COLORS]`; the
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
6. **An exhausted half collapses the pair.** Layer rule 4 omits an exhausted metric, and a pair
   is no exception: when one pool reaches `usedPercent >= 100`, the band goes back to being a single
   ring of the surviving pool, in that pool's colour, with one marker and one percentage on its
   strip. Cursor's external pool runs out routinely, so this is the common state, not the corner
   case — a half-empty split band would spend the scarcest space on a number that is already
   zero.
7. **One payload entry, two complications — two shared slots for outer halves.** A
   `RANGED_VALUE` complication carries one value, so two melts need two complications however the
   payload is shaped. A WFF scene holds at most eight `ComplicationSlot` elements (`maxOccurs="8"`,
   unchanged in format versions 2, 4 and 5), and this face still uses exactly eight: three band
   slots, two outer-half slots and three strips. Moving the marker into each strip frees slot
   109 for the second outer half without adding a slot.

   `RingSplitComplicationDataSourceService` selects split ordinal 0 in slot 106;
   `StripSplitComplicationDataSourceService` selects ordinal 1 in slot 109. Ordinals follow the
   payload's split entries, not all its rings. A missing or exhausted selected outer half yields
   `NoData`; an exhausted entry does not shift the next ordinal. Each slot's `BoundingArc`
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

## Ring geometry (revised 2026-08-02)

Numbers here are **measured off a device screenshot**, never read off `watchface.xml`. Two
things the file does not say:

- WFF draws a band at roughly **half the nominal `thickness`** — `thickness="25"` rendered a
  10 px band on a 384 px round watch, which is why arcs read thinner than every review board;
- `width` sets the band's **outer edge**, not its centre line, so the stroke grows inward.

Every number in this document is a **design unit**: the 450-unit language the generator is
written in, the boards are drawn in, and the shipped `watchface.xml` declares as its canvas —
one number throughout, no conversion. The canvas is also the resolution WFF renders at before
scaling to the screen, so raising it costs antialiasing on every edge of the face; see Ring
type texture for the one feature that tempted it and why it no longer does.

| | Value |
|---|---|
| Nominal `thickness` | 40 |
| Rendered band | 20.2 units (17 px at 384) |
| Ring pitch (outer edge to outer edge) | 24 units |
| Outer edges, outer to inner | 202 / 178 / 154 / 130 |
| Gap between bands | 3.5–4.8 units |
| Strip clearance to the inner band | 8.4 units |

Widening the band alone is not enough: at the original 18-unit pitch a thickness of 40 made
neighbouring bands touch, and a first attempt at pitch 21 still left a 0.8-unit hairline
because the band renders 20.2, not the 18.8 a 0.44 factor predicted. Measure after every
change — the factor is not exact.

**A `ROUND` cap reaches past the angle it is drawn to, so the melt is inset by one.** Measured
2026-08-16: a 40-unit band at radius 159 lost **6.42° per end**, half its nominal thickness laid
along the arc, so a ring at 4% used showed a 3° gap instead of 14° and read as closed. The face
now draws the melt short by one cap at each end (`capDegrees` in `tools/render-watchface.mjs`),
and the caps fill exactly what the inset freed: at 50% used the gap measures **180.3°** against
a true 179.95°, on the full band and on both halves alike. Review art carries the same inset,
which is why the boards and the watch still agree.

**The clock sits above the centre, and the number is measured, not declared.** `watchface.xml`
gives `TimeText` a box at `y=160, height=90`, whose centre is 20 units above the canvas centre;
measured 2026-08-13, WFF renders the digits **21.7** up. That is the optical centre the hero rule
asks for — the strip stack below pulls the eye down. Review art centred the clock geometrically
and disagreed with the face by that much; it now carries the measured lift (`TIME_LIFT` in
`tools/render-watch-ring-designs.mjs`), which is why the boards and the watch show the same
screen.

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

**A band that has spent nothing closes (revision 2026-08-17).** The cap inset above is what
makes a small melt visible, but at `usedPercent == 0` there is no melt to inset and the inset
leaves the ring open anyway: measured on the paired band, a seam of about **1°** at 12, four
pixels wide at that radius. A closed sweep is not available — `359.9` exists precisely because
`360` collapses the `ROUND` tip — so the face branches instead: when the complication reads its
maximum, the same arc is drawn without the start transform and the two caps close over each
other. Boards do the same (`ringArc`, `remaining >= 1`), which is why
`round-3-plan-untouched.svg` shows a closed inner half beside a spending outer one.

**A positive remainder below the two-cap cutoff stays visible (revision 2026-10-01).** The
owner reproduced a face with strips reading `2%`, `69%`, and `94%` on `emulator-5554` on
2026-09-26: the 2% strip still had data, but its ring showed only the track. The inset above
had consumed more than that ring's remaining centreline. Its cutoff is derived per ring as
`2 * capDegrees(diameter, thickness) / 359.9`, not chosen by eye:

| Ring | Diameter | Remaining cutoff |
|---|---:|---:|
| 101 Today | 404 | 3.15% |
| 102 Week | 356 | 3.58% |
| 105 Ring3 | 308 | 4.13% |

At or below its cutoff, a positive remainder keeps its proportional centreline without the
two cap insets, so the round caps meet as a visible point. Above the cutoff the measured inset
geometry is unchanged. This deliberately does not impose a minimum sweep: doing so would
overstate remaining capacity at the edge of the scale. The existing zero-spend/full-ring branch,
band thickness, split halves, and slots are unchanged. Review art mirrors the rule in
`round-3-plan-near-exhausted.svg` with the observed `2%`, `69%`, and `94%` values.

**Halves of a band, measured 2026-08-13.** A split band (see Split band) is two arcs inside one
ring slot, and the numbers that work are **centre lines at `outer − 5` and `outer − 15`, both at
`thickness="10"`** — 197 and 187 on the outermost band, 173 and 163 on the next, 149 and 139 on
the third, since a pair can land on any of them. In the markup that is `width="394"` and
`width="374"` for the outermost: **twice the centre line**, not twice the outer edge as the
whole-band rule above would suggest. Getting that translation wrong is what the first two
probes did, and it fails silently — the halves land on top of each other and read as one band. Measured on the round AVD at 384 on the
outermost: the halves paint 182.5–192.25 and 192.25–202.25, **9.75 units each** (8.3 px),
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
shipped band was fitted to; rows three and four paint the full nominal instead. The slot's
`BoundingArc` is the obvious suspect — it clips ring content to its own band — but that is a
guess, and this document does not keep guesses next to measurements.

The strip stack was resized with the rings — 88x18 boxes stepping 21 units from y=283, a
stack pitch of its own that has nothing to do with the 24-unit ring pitch. The previous 96x20
stack reached radius 142.3 and would have cut into the widened inner band.

Only three strips render, matching the three-ring cap. As of **2026-09-16**, the former fourth
**ring** slot (106) carries the first split's outer half, and the former fourth **strip** slot
(109) carries the second split's outer half. Both reach all three radii and select the band by
its outside-counted `TITLE`. The far-end marker now lives inside each strip slot, selected by
its outer-pool token, with the same declared 3x14 arc and right-edge position. Nothing in the
eight-slot budget is spare now.

The historical **2026-08-16** reading remains: the shared marker landed at x 265–268 of the
181–269 strip, on the paired row only. This is evidence for the previous rendering, not a new
measurement after the move. Marker equivalence on the updated face is **deferred until live-data
verification**. Keep the geometry constants and review art unchanged pending that check. Any new measurement must record its date and the actual device;
for the planned check this is `wardpulse_wear_round_api36_1`, a round API-36 emulator, not shipped
watch hardware.

`tools/render-watch-ring-designs.mjs` carries the same measured values, so review art shows
what the watch shows. Before that revision the generator drew the nominal 26, roughly 2.3x
the real band; it also sized each strip box to its own label until **2026-08-09**, which drew
the retired 96-unit stack in a 12pt-face world. The stack is now a constant there too, and the
generator refuses any label wider than the 78-unit text region instead of letting it overhang —
the face would ellipsize it.

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

Muted remaining arcs (when plan rings exist) and large centered time. Strips off for ambient.
Ring type dims with the band it is punched into (alpha 140, same as the arcs) — it is part of
the ring, not chrome to switch off. `round-ambient-budget.svg` shows that it survives, not at
what level: review art mutes an ambient arc to one gray, while the face keeps the family color
and dims it, so the two cannot agree on a number.

## Review variants

Regenerate with `node tools/render-watch-ring-designs.mjs`, then optional PNG previews:

```sh
convert -background none -density 144 \
  apps/wear_android/design/round-3-plan-credits.svg \
  apps/wear_android/design/preview-3-plan-credits.png
xdg-open apps/wear_android/design/preview-3-plan-credits.png
```

| File | Meaning |
|------|---------|
| `round-3-plan-credits.svg` | **Primary baseline** — three providers, plan + credits |
| `round-3-plan-split.svg` | **Split band baseline** — a Cursor plan's two pools on one band, two markers and two percents on its strip |
| `round-3-plan-two-pairs.svg` | Three bands with Cursor and Codex/Spark pairs, fixed inner/outer order and two far markers |
| `round-3-plan-untouched.svg` | A pool nobody has spent: its half closes, while the pool beside it keeps its gap |
| `round-3-plan-near-exhausted.svg` | Near-exhaustion regression — `2%`, `69%`, and `94%` remain, and the 2% ring still has a visible mark |
| `round-3-plan-budget.svg` | Two plan rings + a budget ring reading `$71.30/250`; only its band carries type |
| `round-3-budget-periods.svg` | **Ring type baseline** — one connection's three budget periods, told apart by `7D` / `M` / `D` alone |
| `round-2-plan-credits.svg` | Two providers |
| `round-1-plan.svg` | Single plan ring, `%` strip only |
| `round-1-plan-credits.svg` | Single plan + credits |
| `round-credits-only.svg` | No plan rings — time + credits strip |
| `round-ambient-3.svg` | Ambient, three muted rings |
| `round-ambient-budget.svg` | Ambient with type — the band dims and takes its type with it |

Wear: `apps/wear_android/design/`. WFF copies: `apps/watchface_wff/design/`.  
OpenPencil `rings.fig` is a frame inventory only (`.fig` write drops ellipse `arcData`).

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app Glance | **Not** this face language — locked text legend (`WEAR_GLANCE_DESIGN.md`, 2026-07-26) |
| WFF watch face | Same language with large time hero; concentric `RANGED_VALUE` arcs plus sunk `RANGED_VALUE` strips (`%` / `% · credits` / `$12.34/100` for budgets) in `watchface.xml`. Every strip TEXT is the full label (WFF `length(TITLE)` Conditions are unreliable). Inner strip accents use `[COMPLICATION.RANGED_VALUE_COLORS]` (family ColorRamp); far markers use static palette colours selected by strip `TITLE` (Split band, rule 4). Keep progress/track spans below 360° (scale onto 359.9°) — a closed circle collapses to a ROUND tip. Remaining melt is clockwise from 12: Transform `startAngle` to `(1 - value/max) * 359.9` with fixed `endAngle` 359.9. Strips need their own `BoundingBox` slots (`BoundingArc` clips content to the arc band). A scene holds **at most eight** `ComplicationSlot` elements in every format version and this face has used all eight since 2026-07-25, so a new slot has to come out of that budget (Split band, rule 7). |
| Phone Watchface tab | Slot selection + preview of next payload rings (not Settings). Rows are grouped since 2026-08-16: a heading per kind of connection, a sub-heading per connection, the same outline the Widget tab uses |

## Non-goals

- Side-by-side `RING 1` / `RING 2` wireframe complications as the target language.
- Large remaining % as the aperture hero.
- High-contrast bordered strip “cards” or ring-cast drop shadows as strip chrome.
- Time-based rotation of which metric is “on top” in the first iteration.
- Brand/marketing chrome, floating badges, or dense face captions.
- LLM token counts (`TOK`) on the face — those belong on phone history charts, not strips.

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
