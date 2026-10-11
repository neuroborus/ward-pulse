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
the face draws, and the brand copy of that picture is retired) — accepted visual target for
Wear OS and Watch Face Format until the next explicit design revision.
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
   limit: the innermost band that renders, and the topmost strip row that renders. Outer rings
   are looser. The strip stack anchors to its bottom row, so with fewer than three rings the
   tightest strip is the topmost **occupied** row rather than the top of the well area (see
   Upper cells, rule 3).
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
  ┌──── remaining arcs (0–3 slots; hard max three) ──────────────┐
  │                                                              │
  │                       ( 18° )                                │
  │             ( Tue )              ( UV 7 )                    │  ← three cells, on an arc
  │                                                              │
  │                       10:08                                  │  ← large time (hero)
  │                   WARDPULSE watermark                        │  ← quiet mono, no ring
  │            ┌─ sunk well ──────────────┐                      │
  │            │▌ 8% · 500                │                      │  ▌ = family accent
  │            │▌ 39%                     │                      │
  │            │▌ 72%                     │                      │
  │            └──────────────────────────┘                      │
  └──────────────────────────────────────────────────────────────┘
```

Rules:

- **Time is the hero** — optically centered; not a large remaining %.
- **Upper cells** — three customizable complication cells in the band the baseline reserved for
  a weather glance until **2026-10-09**. They sit on an arc concentric with the face, so the
  middle one rides higher than the outer two and all three keep the same gap to the inner band.
  The wearer chooses what each one holds. A fresh install shows the day of the week, the
  temperature and the UV index, but only the day is a complication: the two weather readings are
  the face's own chrome, so all three cells stay free for the wearer. A cell showing nothing is
  a well with a graded rim, which is how an empty cell says it is empty (see Upper cells).
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
   unchanged in format versions 2, 4 and 5), and this face still uses exactly eight. Until
   **2026-10-09** those were three band slots, two outer-half slots and three strips; since that
   revision they are three band slots that each also draw their own strip, two outer-half slots,
   and three upper cells (see Upper cells, rule 2). Moving the marker into each strip frees slot
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

1. **Three cells of 42 units on an arc concentric with the face, not in a row.** Their centres
   lie on a circle of radius **106.8** around the face centre `225, 225`, at **−29°, 0, +29°**
   from vertical. The middle cell is the highest, because it is the one on the vertical axis.

   | Cell | Centre | Box origin, integer | Radius from face centre |
   |---|---|---|---:|
   | left | 173.22, 131.59 | `152, 111` | 106.80 |
   | middle | 225.00, 118.20 | `204, 97` | 106.80 |
   | right | 276.78, 131.59 | `256, 111` | 106.80 |

   The clearances this buys, against the clear aperture of **133.8** (the innermost band's
   outer edge at 154, less the 20.2 the band renders inward) and the `TimeText` box at `y=160`:

   | | Value |
   |---|---:|
   | Cell to inner band, all three | **6.00** |
   | Lowest cell to the clock | 7.41 |
   | Between neighbouring cells | 11.48 |
   | Middle cell above the outer two | 13.39 |

   **The equal clearance is the whole point, and it is equal by construction rather than by
   fitting.** A constant radius means a constant distance to a band that is itself a circle, so
   there is no number to tune and nothing to drift when the arc moves. Everything after it —
   the diameter of 42, the angle of 29° — is what makes the other two clearances positive at
   that radius.

   **What the straight row got wrong.** Until this revision the cells were 48 units at
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

   The square `BoundingBox` around a cell is a separate shape and it does cross the inner band —
   its far corner reaches **135.37** — but nothing is painted out there. The well is an ellipse
   inscribed in that box, reaching **127.8** at its far edge, and the text sits in a line box
   inset inside the ellipse (rule 7), whose own far corner reaches **123.71**. A bounding box is
   where taps land (rule 9), not where the cell draws.

   The coordinates above are derived from this document's own locked geometry; the layout has
   been rendered on the round AVD and approved from those captures, not measured off them glyph
   by glyph.

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
   height — 105 at `y=283`, 102 at `y=304`, 101 at `y=325` — and nothing in the markup varies
   with how many rings are active. That is sound because arc slots always fill from the outside
   (`RingSurfaceOrder` maps slot *k* counted from the outside to payload `n-1-k`), so the
   occupied rows are always contiguous and always end at `y=325`:

   | Rings | Bands drawn | Strip rows | Tightest |
   |---|---|---|---|
   | 3 | 101, 102, 105 | 283 / 304 / 325 | `y=283` |
   | 2 | 101, 102 | 304 / 325 | `y=304` |
   | 1 | 101 | 325 | `y=325` |
   | 0 | none | 325 — credits only | — |

   **The zero row is a shipped state, not an edge case.** A payload may carry purchased
   credits and no plan ring at all, and the face has always shown that as a lone strip; before
   the fold it was strip 0's job, by the branch in `stripLabel` that falls back to
   `creditsGlance` when no ring sits at that index. The row follows the rule rather than the
   old numbering: one row that is contiguous and ends at `y=325` **is** the row at `y=325`, so
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
   | `TITLE` | both — bands branch on `D` / `7D` / `M` / `split`, strips on `cursor-other` / `spark` | **collides** |

   The collision is resolved by a combined closed vocabulary, with each branch comparing against
   the full set of combinations joined by `||` — WFF has no prefix test, so a token is matched
   whole or not at all. The set is short, because only a split band carries a pool token and a
   budget ring is never shared, so no period token ever gains a suffix:

   | `TITLE` | Band | Strip |
   |---|---|---|
   | *(empty)* | a plan ring's full band | no far marker |
   | `D` / `7D` / `M` | a budget ring's band, with its type | no far marker |
   | `split` | the inner half only | no far marker — pool unknown or exhausted |
   | `split:cursor-other` | the inner half only | the Cursor pool's marker |
   | `split:spark` | the inner half only | the Spark pool's marker |
   | `credits` | **no band at all** | the lone credits row (rule 3) |

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

6. **A cell holds about four glyphs.** 42 design units is 36 px at 384 — an icon, or a short
   label such as `72%`, `$12`, `2h`, `UV 7`. This is why the budget label stays on a strip: the
   locked worst case `$999.99/999` is a strip-width number and has no reading at cell scale.
   A cell never carries a value that only makes sense at full strip width.

   The ink measurements behind "about four" were taken in the **48-unit** cell this revision
   replaced: `Tue` 23 units, `18°` 18, `UV 7` 27, against a widest label of 27 in 48. At 42 the
   same three labels were rendered on the AVD in the 37-unit line box of rule 7 and read
   cleanly, but their ink was not remeasured, so the headroom at the new size is seen rather
   than counted.

7. **A complication has no appearance of its own; the face draws all of it.** WFF gives a
   provider no say in how its data looks. What arrives is data — `TEXT`, an optional `TITLE`, an
   optional monochromatic icon, a ranged value and a colour ramp — and every visual decision is
   the face's: font, size, weight, colour, alignment, and what to draw at all. A cell cannot
   inherit a system style, and nothing stops three cells fed by three unrelated providers from
   reading as one row. `SHORT_TEXT` draws `TEXT` alone, centred on one line, in the face's own
   label voice: Bold, `#fff4fbf8`, size 14 in the 450-unit language, ellipsised. It sits in the
   same 18-unit line box the strips use, centred in the 42-unit cell at `y=12` by
   `(42 - 18) / 2`, and inset horizontally to where the well still admits that box's full
   height: a circle of radius 21 has a half-width of `sqrt(441 - 81)` = 18.97 at 9 units off its
   midline, so the box is **37 units wide at `x=2`**. Without the inset a glyph's corner would
   cross the rim, since the well is only as wide as 42 units on its midline and narrower
   everywhere else. The provider's `TITLE` and its icon are both dropped. At four glyphs there
   is no second line to put a title on, and a cell's own position is the label the wearer
   learned when they chose it; an icon beside the text would halve the text, and the value is
   what the cell was filled for. Size 14 is what the 2026-10-09 spike rendered — `Tue`, `0` and
   `UV0` all read at 384 px — not an optimum; this revision fixes the rule, and the kerned fit
   is measured when the generator changes.

   **`x=2` carries one unit of asymmetry, and it is the grid's, not a choice.** WFF coordinates
   are integers: the validator rejects a fractional one outright, `'152.2' is not a valid value
   for 'integer'`. The exact inset is `(42 - 37) / 2` = 2.5, so the box runs 2..39 inside 42 and
   sits half a unit left of the cell's own centre. An even leftover — a 36-unit box at `x=3` —
   would land exactly, but it has not been rendered, so it is recorded as where the number comes
   from rather than as a recommendation.

   **A trailing mark is not part of the number, and the box moves so the digits are centred.**
   Centring the whole string puts the *string* on the cell's axis and the digits to the left of
   it: measured 2026-10-09, `18°` sat with its string centre at 224.5 against a cell centre of
   225, while its **digits** sat at **222.5** — 2.5 units left. The degree sign drags them.
   The temperature's line box therefore shifts right by **2** (`x=4`), after which the digits
   measured **224.5**, half a unit out and below what the method can resolve.

   The rule generalises and should be read as the rule, not as a constant for `18°`: the shift
   is **half the advance of the trailing mark**, and it does not depend on how many digits
   precede it. A box centres the whole string, so the gap between the string's midpoint and the
   digit group's midpoint is always half the mark's width, whatever the digits are. `5°`, `18°`
   and `-12°` all land the same way.

8. **The other accepted types, and the two that are refused.** `MONOCHROMATIC_IMAGE` is the one
   type whose whole content is an icon. It is drawn at 21 units in the 42-unit cell and
   tinted `#fff4fbf8`, the same colour as the text, so an icon reads as face text rather than as
   a foreign mark; half the diameter leaves the well's rim clear on a round recess. Like the
   line box of rule 7 it cannot be centred exactly: 21 in 42 leaves 10.5 a side on an integer
   grid, so the icon sits at `x=10` and half a unit in from centre — the same remainder, in the
   same direction, and the grid's rather than a choice. The tint goes on a group of its own
   rather than on the slot, since tinting the slot would take the well with it. It is
   deliberately not tinted a family colour: on this face a family colour means *this ring's
   provider*, and a cell is not a ring. `RANGED_VALUE` is drawn as **text, never as an arc** —
   `TEXT` when the provider sends it, the value itself otherwise. A small arc in a cell would
   put a second arc language on a face whose arcs already mean one thing, layer rule 1's *one
   ring = one metric of one connection*, and it would say it a few units from the real ones —
   rule 1 puts every cell's far edge six units from the innermost band.
   The ramp colour goes unused for the same reason the icon tint does. What a provider that
   sends no `TEXT` renders is declared here, not measured.

   `SMALL_IMAGE` and `LONG_TEXT` are left out of `supportedTypes` on purpose, which is what
   keeps the system editor from offering a provider that supplies only one of them.
   `SMALL_IMAGE` is the provider's own picture in the provider's own colours and WFF offers no
   tint for it — a foreign colour image in a 42-unit circle, on a face whose whole palette is
   family colours over near-black, reads as a sticker on the glass. `LONG_TEXT` is sized for a
   slot several times this one and has no reading at four glyphs (rule 6).

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

    **The ring is what says a cell is occupied (revision 2026-10-10).** A stroke of 1 on a path
    of 41 — radius 20.0 to 21.0, inscribed in a well whose own edge is at 21 — in the
    face's own text colour at `0xaa`, `#aaf4fbf8`. It goes on whatever the cell is showing,
    the wearer's complication and the face's own weather reading alike, and never on an empty
    one. That is the whole of the language: **a ring means occupied, a recess means free**, and
    a cell is never both.

    **Geometry correction 2026-10-11 — the ring is inscribed, not inset.** Until today this
    paragraph read *radius 20.25 to 20.75, a quarter of a unit inside the well's edge at 21*,
    and three other places said the same: Non-goals, and the `CELL` comment in each of the two
    generators. All four were wrong the same way. A stroke is centred on its path, so one of
    thickness 1 on a path of diameter 41 runs from radius **20.0 to 21.0**; 20.25 to 20.75 is
    the span of a **half**-unit stroke. That the stroke is centred rather than inset is this
    document's own reading, not an assumption — Ring geometry measured `width=384 thickness=20`
    painting 182.5 to 202.2, the whole nominal centred on `width/2`, for an arc drawn outside a
    `BoundingArc`, which is what a cell's hairline is.

    **Nothing moves.** The markup is unchanged and the face draws what it has drawn since
    2026-10-10; this is a correction of the description, not a revision of the geometry, and the
    three captured widths that chose the shipped value are untouched. What goes with the wrong
    numbers is the reason they carried: there is no quarter-unit of well left clear outside the
    ring, because the ring's outer edge *is* the well's edge.

    The property that reasoning was reaching for survives, and it is the sharper one: the ring
    is **inscribed**. Its outer edge and the well's coincide at 21, so no part of the stroke
    falls outside the well onto the lift, and the two meet the lift on one antialiased curve
    rather than leaving a sliver of well showing beyond the line. The ring is drawn over the
    well and after it — `cellWellFlat`, then `cellRing` — so what it covers is the well's own
    outermost half-unit, which on a flat well costs nothing: the lit rim belongs to the graded
    treatment of an **empty** cell, and an empty cell wears no ring.

    It was added because a filled cell had no edge at all. The occluder is `#ff0b0e0c` on a
    lift measured at `19, 24, 22` — a step of eight to eleven levels, which reads as depth
    under a recess but leaves a filled cell as a dark disc on a dark field, so only the glyphs
    registered and the cell itself went unseen. Three widths were rendered and compared on the
    AVD: 1 unit at 40 % of the text colour, the same at 67 %, and 2 units at full strength. The
    first does not read at a glance; the last competes with the text it encloses and with the
    bands behind it. The middle one is the shipped value. Giving the weather cell the same ring
    is a decision, not a carry-over: without it the face would have three kinds of cell instead
    of two, and the wearer would have to learn which of two dark discs was theirs to fill.

    The third is a radial gradient centred on the cell at radius 21, running
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

    **The arc of rule 1 evened the lift too, which was not the point of it.** The lift is a
    radial gradient about `225, 216`, a different centre from the one the cells are arranged
    around, so a cell's distance to it is not its distance to the face centre. The straight row
    stood at 82 for the middle cell and 99.3 for the outer two, reading `20, 26, 23` against
    `19, 24, 22`. On the arc the three sit at **97.80, 99.02 and 99.02**, and all three read
    **`19, 24, 22`** — measured at screen pixels `192, 101`, `236, 112` and `148, 112`, with the
    face active, confirmed by a control of `24, 32, 28` at the screen centre, the gradient's
    first stop. So the three wells now composite to one colour, which the straight row never
    managed. It is a consequence of the constant radius, not a thing that was designed for.

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
    over each other in the same 42 units, which is exactly what rule 11 says a filled cell puts
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
    turns on a well being a darkening, and the hairline of rule 10 is the opposite: it adds
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
    exhausted ring is omitted, so a recovered one reappears. Giving the cells to the wearer does
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
| Outer edges, outer to inner | 202 / 178 / 154 / 130 |
| Gap between bands | 3.5–4.8 units |
| Strip clearance to the inner band | 8.4 units |

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
remaining capacity at the edge of the scale. The existing zero-spend/full-ring branch, band
thickness, split halves, and slots are unchanged. Review art mirrors the rule in
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

The strip stack was resized with the rings — 88x18 boxes stepping 21 units from y=283, a
stack pitch of its own that has nothing to do with the 24-unit ring pitch. The previous 96x20
stack reached radius 142.3 and would have cut into the widened inner band.

Only three strips render, matching the three-ring cap. As of **2026-09-16**, the former fourth
**ring** slot (106) carries the first split's outer half, and the former fourth **strip** slot
(109) carries the second split's outer half. Both reach all three radii and select the band by
its outside-counted `TITLE`. The far-end marker now lives inside each strip slot, selected by
its outer-pool token, with the same declared 3x14 arc and right-edge position. Nothing in the
eight-slot budget is spare now.

As of **2026-10-09** the strips no longer hold slots of their own: each one is drawn by its own
band's slot at a fixed row, and the three slots this frees are spent on upper cells under new
ids (Upper cells, rule 2). The stack geometry above is unchanged — the same 88x18 boxes at the
same 21-unit pitch from `y=283` — but which slot paints which row is now fixed rather than
following the payload index, which is why the stack anchors to its bottom row.

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
credits, ambient would light one row at `y=325` and leave two dark gaps above it. The stack is
anchored to its bottom row precisely so that it never opens a gap (Upper cells, rule 3), and
selective survival puts that gap back. The zero-ring case needs no special handling either: a
lone credits row dims like any other row.

**The level is 90, where the rest of the face uses 140.** 140 is the arcs' own proportion, worn
by the bands, by the ring type and by a cell's hairline, and taking it here would put one
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
so it has to survive ambient or two readings land in the same 42 units. And a well darkens the
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
| `round-credits-only.svg` | No plan rings — time + the lone credits strip, on the bottom row |
| `round-3-plan-cell-cleared.svg` | **Empty-cell baseline** — the left cell cleared, showing the graded recess beside two filled ones |
| `round-ambient-3.svg` | Ambient, three muted rings |
| `round-ambient-budget.svg` | Ambient with type — the band dims and takes its type with it |

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
- High-contrast bordered strip “cards” or ring-cast drop shadows as strip chrome. The hairline
  an occupied upper cell wears (Upper cells, rule 10) is the one exception, written in on
  **2026-10-10**: this refuses chrome that frames content which is already legible without it,
  and a filled cell was not — an opaque well on the lift is a step of eight to eleven levels,
  which reads as depth under a recess but leaves a filled cell edgeless, so only its glyphs
  registered. The ring is a one-unit line in the face's own text colour, inscribed in the well
  so that its outer edge meets the well's own at 21 (corrected **2026-10-11**; Upper cells,
  rule 10), carrying no fill, no shadow and no colour of its own, and it is what makes
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
language: three concentric bands, three upper cells behind their hairlines, the time hero, and
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

No preview carries a byte comparison, and that is a decision rather than a gap.
`tools/design-output.mjs:18-22` already refuses one for generated images, and says what replaces
it: "SVG is compared byte for byte because it is text the generator wrote. PNG previews are not
compared here: ImageMagick stamps metadata that changes between runs, so equal images differ as
bytes. What stands in place of a byte gate is `renderPreviews` below — every preview is
rewritten from its board on every render, so none of them can keep art the design has left
behind." That rewriting is what stands in its place here too;
the shipped asset is held twice over, because `watch_face_info.xml` names it by resource and a
missing one stops the build. The tree already holds two working ways to keep such a file from
churning in the diff: `tools/export-icons.sh:8` renders to a candidate and runs
`compare -metric AE`, replacing the committed PNG only when the pixels differ — that is how
`apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png`, a watch face drawable, is
written — and `tools/render-watchface.mjs:674` passes `-strip` so the render timestamp never
reaches the bytes. Either settles the churn. Neither is mandated here.

What the gate cannot do, it does not claim: `just check-designs` compares the boards against
their own generator and nothing else (`justfile:103`), so a preview generated from a board is
proved to match that board, never to match the face. The face is what a device capture proves,
by hand, as the acceptance for this phase already asks.

A preview draws only what the face draws, from the face's own declared sources, and never an
invented complication set. In the cells that means the weather chrome of Upper cells, rule 11,
where `WEATHER.IS_AVAILABLE` is true; the graded well of rule 10 where it is not; and a
complication where a slot is bound — the `Tue` on the primary board is a `DAY_OF_WEEK` reading
on the left cell, which rule 11 leaves with no chrome declared beneath it, not weather. It takes
no marketing chrome, no badge, no caption, and no reading a wearer could not get.

The board's `18°` and `UV 7` are therefore the weather-available state, not a universal one.
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
shipped asset omitted the quiet `WARDPULSE` watermark that Composition locks between the time
and the strips and that `watchface.xml` draws at every launch. It omitted it because it is
rasterized from a review board and review boards are mark-free. That is right for a board and
wrong for this file. A board is read by a reviewer checking ring geometry; this asset is the
face's own portrait, declared as its `Preview`, and a portrait that drops a locked element of
the face shows a wearer a face they will not get.

So the asset is **composed** rather than only rasterized: the Primary board at 450, then the
faded mono drawable `apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png` at the box
`watchface.xml` gives the mark — 66×66 at (192, 227), alpha 95 — read out of that file at
render time rather than copied into the generator, so the portrait cannot disagree with the face
about where the mark sits. The ambient mark is not drawn: this is the active portrait, and the
smaller 54×54 at alpha 70 only appears under an ambient variant (Upper cells, rule 12, and
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
