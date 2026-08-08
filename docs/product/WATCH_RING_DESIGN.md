# Watch Ring Design

**Baseline locked 2026-07-25**; melt / strip-accent revision **2026-07-27**; ring-cap /
purchased-meter revision **2026-07-27** (max three plan/budget rings; Extra usage and other
purchased meters are not rings); band-width revision **2026-08-02** (see Ring geometry);
per-connection budget revision **2026-08-08** (budget rings belong to one connection and take
its family color; the summed Today / Week / Month rings are retired) —
accepted visual target for Wear OS and Watch Face Format until the next explicit design
revision.
Implementation and review art must follow this document; do not reintroduce side-by-side ring
wireframes, large remaining-% heroes, or bordered strip cards.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-watch-ring-designs.mjs`  
Canonical preview: `apps/wear_android/design/preview-3-plan-credits.png` (and sibling variants).

## Goal

Glanceable **remaining** capacity for up to **three** user-selected percent metrics, with
remaining purchased **credits** on each strip for that provider family when reported (same
per-provider source as Glance). Purchased meters (Claude Extra usage, Cursor on-demand, Codex
credits) are **not** ring candidates — they stay on the phone dashboard and may appear as
alerts only when the user configures thresholds for those meters on **Providers**.
Not “always show every provider,” and never invent `Unknown` filler. Strip secondary values are
credits — never LLM `TOK` / token counts.

## Layer rules

1. **One ring = one metric of one connection** — a provider plan/allowance window with a %, or
   one connection's local budget % for one period. There is no ring for a sum across
   connections: spend is reported by whichever connections report it, while a limit exists only
   where the user set one, so a summed percentage divides one set by another. Aggregate **money**
   is still true and stays on the phone dashboard cards and the Wear app period sections — it is
   the aggregate *percentage* that has no owner and no meaning.
   Claude subscription plan windows are an exception at **selection** time: the phone exposes one
   Claude plan slot and resolves it to the tightest remaining window (window name lives on Glance,
   not on face strips).
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
   only the resolved surface order after omit + sort. Plan/budget percent metrics only.
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
| Anthropic / Claude | `#E8915A` | Orange (Anthropic presentation) |
| Cursor | `#67E8D4` | Teal |
| Unresolved family | `#8AB4F8` | Blue — fallback only, never a product color |

A local budget ring takes the family color of the connection it belongs to, exactly like that
connection's allowance rings; period is carried by the ring label, not by a color of its own.
Blue is what remains when a ring id resolves to no family, which should not happen for a ring
the product ships.

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
  - credits text is compact (`500`, `1.2K`) — never a `TOK` suffix;
  - ring band **18.8 units** on the 450 WFF canvas so arcs read clearer while a **3-strip**
    stack still clears the aperture (see Ring geometry for why that is not the nominal 25).
- **Credits-only**: thin framing track, large time, credits strip only — no percent arcs.
- No orphan captions (`Codex left`, floating unit labels) outside the strip row.
- Review art focuses on 1–3 provider families. A local **budget** metric may still occupy a product
  ring slot, drawn in its connection's family color; do not ship a “4 providers” face variant in
  review art.

## Ring geometry (revised 2026-08-02)

Numbers here are **measured off a device screenshot**, never read off `watchface.xml`. Two
things the file does not say:

- WFF draws a band at roughly **half the nominal `thickness`** — `thickness="25"` rendered a
  10 px band on a 384 px round watch, which is why arcs read thinner than every review board;
- `width` sets the band's **outer edge**, not its centre line, so the stroke grows inward.

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

The strip stack was resized with the rings — 88x18 boxes stepping 21 units from y=283, a
stack pitch of its own that has nothing to do with the 24-unit ring pitch. The previous 96x20
stack reached radius 142.3 and would have cut into the widened inner band.

Only three strips render, matching the three-ring cap. A fourth slot exists in the markup for
both rings and strips; neither is drawn, and the fourth strip's geometry is not kept clear of
the third band.

`tools/render-watch-ring-designs.mjs` carries the same measured values, so review art shows
what the watch shows. Before that revision the generator drew the nominal 26, roughly 2.3x
the real band.

## Ambient

Muted remaining arcs (when plan rings exist) and large centered time. Strips off for ambient.

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
| `round-2-plan-credits.svg` | Two providers |
| `round-1-plan.svg` | Single plan ring, `%` strip only |
| `round-1-plan-credits.svg` | Single plan + credits |
| `round-credits-only.svg` | No plan rings — time + credits strip |
| `round-ambient-3.svg` | Ambient, three muted rings |

Wear: `apps/wear_android/design/`. WFF copies: `apps/watchface_wff/design/`.  
OpenPencil `rings.fig` is a frame inventory only (`.fig` write drops ellipse `arcData`).

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app Glance | **Not** this face language — locked text legend (`WEAR_GLANCE_DESIGN.md`, 2026-07-26) |
| WFF watch face | Same language with large time hero; concentric `RANGED_VALUE` arcs plus sunk `RANGED_VALUE` strips (`%` / `% · credits`) in `watchface.xml`. Every strip TEXT is the full label (WFF `length(TITLE)` Conditions are unreliable). Strip accents use `[COMPLICATION.RANGED_VALUE_COLORS]` (family ColorRamp). Keep progress/track spans below 360° (scale onto 359.9°) — a closed circle collapses to a ROUND tip. Remaining melt is clockwise from 12: Transform `startAngle` to `(1 - value/max) * 359.9` with fixed `endAngle` 359.9. Strips need their own `BoundingBox` slots (`BoundingArc` clips content to the arc band). |
| Phone Watchface tab | Slot selection + preview of next payload rings (not Settings) |

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
  eventually share a device. Same-family rings on one face must then differ by
  **hatch/pattern** as well as family color (color alone is not enough for two Codex or two
  Claude windows).
