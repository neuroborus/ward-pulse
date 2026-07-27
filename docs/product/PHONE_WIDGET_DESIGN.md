# Phone Widget Design

**Status: locked 2026-07-27** — baseline for the phone **Widget** tab and Android App
Widget. Review art: `apps/phone_flutter/design/` (`widget-medium.svg` primary).

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`.
Do **not** copy [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

## Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, multi-metric rows).
Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring slots.

## Metric rules

1. **One slot = one percent metric** — local budget (Today / Week / Month), provider plan window,
   or purchased meter (Extra usage, on-demand, credits %) when the provider reports a %.
2. **Claude plan** collapses to one selectable slot (tightest remaining window), same as Watchface.
3. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette (OpenAI/Codex green, Anthropic orange, Cursor teal, budget blue).
4. **Omit** unavailable and exhausted (`usedPercent >= 100`) metrics; never invent `Unknown` filler.
5. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

## Size caps (locked)

| Size | Slots shown | Notes |
|------|-------------|--------|
| Small | **2** | denser than a watch ring, still glanceable |
| Medium | **4** | default; Widget tab prefs cap (`phoneWidgetSlotCount`) |
| Large | deferred | optional later; do not expand prefs until review art lands |

Prefs select up to **four** metrics. The home-screen surface shows the first *N* resolved
metrics for the current widget size (2 or 4). Unused rows are omitted, not filled.

## Composition (locked)

```text
┌─ system widget chrome ─────────────────────────┐
│  WardPulse                          Stale      │
│  ▌ 46% left · Codex 5h                         │
│  ▌ 22% left · Claude Extra                     │
│  ▌ 71% left · Today                            │
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
shipping large (6-slot) size before a separate design lock
```

## Review art

| File | Role |
|------|------|
| `widget-medium.svg` | primary medium (4 rows) |
| `widget-small.svg` | small (2 rows) |
| `widget-empty.svg` | empty selection |
| `widget-stale.svg` | stale header chrome |
