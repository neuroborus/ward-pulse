# Phone Widget Design

**Status: locked 2026-07-27** (revised **2026-07-27** — expanded Claude windows,
six-slot prefs, exhausted plan pools stay visible as `0% left`). Review art:
`apps/phone_flutter/design/` (`widget-small.svg` / legacy `widget-medium.svg`).

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`.
Do **not** copy [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

## Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, multi-metric rows).
Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring slots.

## Metric rules

1. **One slot = one percent metric** — local budget (Today / Week / Month), provider plan window,
   or purchased meter (Extra usage, on-demand, credits %) when the provider reports a %.
2. **Claude plan windows stay expanded** on the phone widget (`5h`, `Weekly`, Opus/Sonnet weekly
   when present). Watchface/Glance still collapse Claude to one tightest ring.
3. **Cursor Models and Other Models** are separate selectable rows whenever the usage-summary
   reports both pool percents.
4. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette (OpenAI/Codex green, Anthropic orange, Cursor teal, budget blue).
5. **Omit** unavailable metrics (no percent). Exhausted plan/purchased meters (`usedPercent >= 100`)
   stay on the phone widget as **`0% left`** so sibling pools remain visible. Watch/WFF still omit
   exhausted layers.
6. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

## Size caps (locked)

| Size | Slots shown | Notes |
|------|-------------|--------|
| Small | **2** | short resize (minHeight under ~100dp) |
| Default / tall | **6** | prefs cap (`phoneWidgetSlotCount`); no medium-4 cutoff |

Prefs select up to **six** metrics. The home-screen surface shows the first *N*
resolved metrics for the current widget height (2 or 6). Unused rows are omitted,
not filled.

Default (unset) selection prefers **plan windows** first (Claude + Cursor + Codex), then
purchased meters, then local budgets — so 5h / weekly / Cursor Models / Other Models are not
crowded out by Extra usage.

## Composition (locked)

```text
┌─ system widget chrome ─────────────────────────┐
│  WardPulse                          Stale      │
│  ▌ 46% left · 5h                               │
│  ▌ 22% left · Weekly                           │
│  ▌ 0% left · Cursor Models                     │
│  ▌ 71% left · Other Models                     │
└────────────────────────────────────────────────┘
```

- Rows, not concentric arcs.
- Family accent bar (▌) on each metric row.
- Prefer Material / system widget surfaces over custom card chrome.
- Empty: title + short “No metrics” line (no filler rows).
- Stale: show a compact “Stale” label in the header when the last dashboard is stale.
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

| File | Role |
|------|------|
| `widget-medium.svg` | historical 4-row preview (runtime default is tall/6) |
| `widget-small.svg` | small (2 rows) |
| `widget-empty.svg` | empty selection |
| `widget-stale.svg` | stale header chrome |
