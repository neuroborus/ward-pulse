# Phone Widget Design

**Status: locked 2026-07-27** (revised **2026-07-28** — hug rows/columns, label-center /
credits-end, picker preview sample, day/night olive chrome; revised **2026-08-02** —
two-line label carrying the provider family). Review art:
`apps/phone_flutter/design/` (`widget-small.svg` / `widget-medium.svg` / `widget-dark.svg`).

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`.
Do **not** copy [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

## Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, multi-metric rows).
Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring slots.

## Metric rules

1. **One slot = one percent metric of one connection** — one connection's local budget for a
   period, a provider plan window, or a purchased meter (Extra usage, on-demand, credits %) when
   the provider reports a %. There is no summed Today / Week / Month slot: see
   `WATCH_RING_DESIGN.md` layer rule 1 for why a percentage across connections has no owner.
2. **Claude plan windows stay expanded** on the phone widget (`5h`, `Weekly`, Opus/Sonnet weekly
   when present). Watchface/Glance still collapse Claude to one tightest ring.
3. **Cursor Models and Other Models** are separate selectable rows whenever the usage-summary
   reports both pool percents.
4. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette (OpenAI/Codex green, Anthropic orange, Cursor teal). A budget row takes
   the family color of its connection; blue is a fallback for an unresolved family, not a
   product color.
5. **Purchased credits** — on **plan** rows, when that provider family reports finite purchased
   remaining credits, show Glance-style columns: `N% left` · label · `N credits` (compact
   count + `credits` unit). Same per-provider rule as Wear Glance / face strips — not a
   footer sum, not `creditsGlance`, never LLM `TOK`. Skip on purchased-meter rows (Extra
   usage / on-demand are the credit pool), budgets, and missing/unlimited balances.
6. **Omit** unavailable metrics (no percent). Exhausted plan/purchased meters (`usedPercent >= 100`)
   stay on the phone widget as **`0% left`** so sibling pools remain visible. Watch/WFF still omit
   exhausted layers.
7. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

## Size caps (locked)

| Size | Slots shown | Notes |
|------|-------------|--------|
| Short | **1–2** | fewer metrics in Widget tab (~1–2 cells) |
| Mid | **3–5** | typical place size (`targetCellHeight≈3`) |
| Tall | **6** | prefs cap (`phoneWidgetSlotCount`) |

Prefs select up to **six** metrics; the olive card shows as many **complete** resolved
rows as fit the host cell, and as many **complete** columns as fit the width
(`wrap_content` hug). Trailing rows / right-hand columns that would clip are omitted —
never half-cut text. Horizontal drop order: **credits → label → `% left`**. Vertical /
horizontal resize changes the launcher span; drag handles to the card to reclaim empty
cells. Newly placed widgets default to ~3 cells tall; **remove and re-add** if an old
tall span stays stale. Unused slots stay omitted, not filled.

Default (unset) selection prefers **plan windows** first (Claude + Cursor + Codex), then
purchased meters, then local budgets — so 5h / weekly / Cursor Models / Other Models are not
crowded out by Extra usage. A budget row only becomes selectable once its connection has a
limit for that period, so an unconfigured install defaults to plan windows.

## Composition (locked)

```text
┌─ olive card hugs complete rows + columns ──────┐
│  ▌ 22% left     Claude       80 credits   ⌇wm  │  ← tightest remaining first
│  ▌            Weekly plan                      │
│  ▌ 46% left     Claude      320 credits        │
│  ▌           5-hour session                    │
│  ▌ 71% left  Cursor Models  2.1K credits       │
└────────────────────────────────────────────────┘
┌─ mid (credits dropped) ────────────────────────┐
│  ▌ 22% left    Weekly                     ⌇wm  │
│  ▌ 46% left      5h                            │
└────────────────────────────────────────────────┘
┌─ narrow (% only) ──┐
│  ▌ 22% left   ⌇wm  │
│  ▌ 46% left        │
└────────────────────┘
     (transparent cell beyond the card if the span is larger)
```

- Rows, not concentric arcs.
- Family accent bar (▌) on each metric row.
- **Columns** — `% left` · centered label · credits (end-aligned). Width hide order:
  credits first, then label; missing credits still reserve the credits column when that
  column is shown (label stays centered).
- **Label is two lines** (revised **2026-08-02**) — family on top, pool below, never
  truncated. The provider must be readable on the launcher, where nothing else names it:
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
  reserve a header band). No dedicated header.
- Empty: short “No metrics” line (no filler rows).
- Stale: compact uppercase “STALE” overlay top-start when the last dashboard is stale.
- Tap opens the phone app (Dashboard).

## Non-goals

```text
copying concentric watch-face arcs onto the launcher
interactive controls inside the widget
iOS widgets
burying Widget config under Settings
collapsing Claude plan windows on the phone widget (Watchface only)
```

## Review art

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
| `widget-stale.svg` | stale header chrome |
