# Wear Glance Design

**Baseline locked 2026-07-26** — accepted visual target for the Wear OS **app** home Glance
(first page after opening the tile) until the next explicit design revision. Distinct from the
watch-face baseline in [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md): this screen is a
**text legend** for face ring colors, not a face clone.

**Revision 2026-09-16 — paired bands:** one Glance row per band, with two mini arcs
and two remaining percentages for an active pair. Typography, row pitch and Alerts clearance
are unchanged. Legend-well width, absence of clipping and visual equivalence are **deferred
until live-data verification**; this revision records no new device measurements.

Do not reintroduce a face clone (large concentric stacks, sunk strips, watermark, or
time-as-hero), stacked icon-above-label refresh, or conflating cadence cooldown with
`!OK` / `Rate limited`.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-wear-glance-designs.mjs`  
Primary preview: `apps/wear_android/design/preview-glance-legend-3.png`.

## Goal

Name each selected band with its provider/family, show remaining % and optional
per-provider purchased credits, and keep one mini arc per active pool beside its row so the
user can map face colors to providers.

## Composition

```text
        9:06
      (↻ OK )                ← OK / !OK inside dual-arrow refresh glyph
      [detail]               ← optional; only for problems (Stale, Rate limited, …)

  (●)  Codex · Weekly plan   ← tightest remaining on top (same payload as face center)
       8% left · 320 credits

  (●)  Claude · 5h
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
- Mini arc = **remaining** (`100 - usedPercent`), family color from the face palette;
  same clockwise-from-12 melt as the watch face (usage gap opens at 12). Its round caps reach
  half a stroke past each end — on a 17-unit arc that is 8.4° per cap, more than a 4%-used row
  has to show — so the sweep is drawn short by one cap at each end and the caps fill it back in.
  Without that a nearly full row reads as a closed ring (`WATCH_RING_DESIGN.md`, Ring geometry,
  where the same correction is measured on the face).
- Primary line for a pair: **family name + ` plan`**, exactly `Cursor plan` for Cursor.
  The phone uses the same rule for its band label; the payload carries pool labels, not a
  separate band name. For an ordinary row: family/provider + metric label. Codex keeps
  `Weekly plan`; Cursor Pro+/Ultra
  plan pools use `Cursor Models` / `Other Models` (exhausted pools stay off the face).
  Claude’s subscription plan windows (`5h`, `Weekly`, optional Opus/Sonnet weekly) collapse to
  **one** ring on the phone; Glance shows which window is active via the short label
  (`Claude · 5h` / `Claude · Weekly`).
- Secondary line: ordinary rows keep `N% left`. A pair shows `82% · 41% left`, inner pool
  first, with one `left` applying to both remaining percentages. Append purchased credits
  once when available: `82% · 41% left · 320 credits`. Per provider only — not a footer sum,
  not face `creditsGlance`, never LLM `TOK`.
- Rows are laid out on a **54-unit pitch** with nothing added between them: the pitch already
  covers the mini arcs and both lines.
- The block keeps **12 units clear of the Alerts pill**. Three rows is the ceiling, one per
  band, regardless of how many bands are paired. Device fit and clipping remain deferred
  until live-data verification; the three-row rule is not a new measurement.
- Empty / exhausted: short copy centered between refresh and Alerts; no placeholder rings.

| Empty state | Copy |
|-------------|------|
| No rings selected | `Choose percent rings` / `in the phone app` |
| All selected metrics exhausted | `No remaining capacity` |

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
the row label, not in a color of its own. **A Cursor plan's two pools share one row**, each
with its own coloured mini arc and remaining fraction. The pair reaches the watch as one
payload entry with its second pool inside (`WATCH_RING_DESIGN.md`, Split band). When either
pool is exhausted, the survivor becomes an ordinary row with its pool label, one arc and one
percentage; when both are exhausted the row disappears. Purchased credits appear once per
row — a split face strip gives its width to the second percentage instead.

Refresh `OK` reuses Codex green as status affordance on this control only — do not spread that
into Alerts chrome or general Wear buttons. Surface / track / label match face review art
(`#101412` / `#2E3632` / `#F4FBF8`). Font: Noto Sans Bold in review art.

## Review variants

```sh
node tools/render-wear-glance-designs.mjs

convert -background none -density 144 \
  apps/wear_android/design/glance-legend-3.svg \
  apps/wear_android/design/preview-glance-legend-3.png
xdg-open apps/wear_android/design/preview-glance-legend-3.png
```

| File | Meaning |
|------|---------|
| `glance-legend-3.svg` | **Primary** — three providers, `OK` refresh enabled, Alerts disabled |
| `glance-legend-1.svg` | Single provider with credits |
| `glance-legend-pair.svg` | One Cursor pair — one row, two coloured arcs, inner-first percentages and credits once |
| `glance-legend-full.svg` | Three rows — the ceiling: three bands, currently one paired; device fit remains deferred |
| `glance-legend-budget.svg` | Plan rows (with credits) + a connection budget row (family color, no credits) |
| `glance-legend-stale.svg` | `!OK` + detail `Stale`, refresh enabled, Alerts active |
| `glance-legend-cadence.svg` | Healthy `OK` but refresh **disabled** (cadence cooldown; no detail) |
| `glance-legend-rate-limit.svg` | `!OK` + detail `Rate limited`, refresh **disabled** (provider) |
| `glance-legend-empty.svg` | No rings selected; centered copy; `OK` refresh |
| `glance-legend-exhausted.svg` | All selected metrics exhausted; centered copy; Alerts active |

Wear only: `apps/wear_android/design/`. OpenPencil `.fig` inventory optional.

## Acceptance (locked)

```text
text legend + mini remaining arcs (not a face clone)
one row per band, at most three rows; band order matches the phone/face
paired arcs and percentages: inner first, outer second; each retains its own colour
paired title = family + " plan"; Cursor plan exactly
paired subtitle = "82% · 41% left · 320 credits" (omit credits suffix when unavailable)
54-unit row pitch; 12-unit Alerts clearance; device width/clipping checks deferred
per-provider credits with explicit credits label (no footer sum)
OK / !OK inside dual-arrow refresh glyph; same label font size
optional muted problem detail below the plate (never on the ring)
cadence cooldown = gray OK + disabled (no detail)
provider rate limit = gray !OK + Rate limited + disabled
phone owns allowance via summary manualRefreshAllowed / manualRefreshAvailableAt
Stale = orange !OK + Stale + enabled
Alerts: N pill; active when N > 0; disabled at 0
empty / exhausted centered copy between refresh and Alerts
ordinary metric labels unchanged (Codex Weekly plan; Cursor Models / Other Models)
one exhausted half restores an ordinary row; both exhausted remove the row
review art: render-wear-glance-designs.mjs → preview-glance-legend-*.png
primary preview: preview-glance-legend-3.png
```

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app Glance (page 1) | This legend + refresh control + Alerts button |
| Wear OS app second page | Plan windows and when each comes back (`apps/wear_android/README.md`) |
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
