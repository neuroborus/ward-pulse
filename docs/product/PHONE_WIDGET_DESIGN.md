# Phone Widget Design

**Status: draft baseline (2026-07-27)** — visual language and size caps are proposed for
implementation of the phone **Widget** tab and the future Android App Widget. Review art and
an explicit lock date land before the home-screen surface ships.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`
(`apps/phone_flutter/design/` for review art). Do **not** copy
[`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

## Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, optional multi-metric
rows). Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring
slots.

## Metric rules

1. **One slot = one percent metric** — local budget (Today / Week / Month), provider plan window,
   or purchased meter (Extra usage, on-demand, credits %) when the provider reports a %.
2. **Claude plan** collapses to one selectable slot (tightest remaining window), same as Watchface.
3. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette (OpenAI/Codex green, Anthropic orange, Cursor teal, budget blue).
4. **Omit** unavailable and exhausted (`usedPercent >= 100`) metrics; never invent `Unknown` filler.
5. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

## Proposed size caps (not locked)

Until review art locks these numbers, the Widget tab uses the **medium** cap:

| Size | Slots | Notes |
|------|-------|--------|
| Small | 2 | denser than a watch ring, still glanceable |
| Medium | **4** | default tab / prefs cap (`phoneWidgetSlotCount`) |
| Large (optional) | 6 | only if the design lock keeps it readable |

## Composition (draft)

```text
┌─ system widget chrome ─────────────────────────┐
│  WardPulse                          stale?     │
│  ▌ 46% left · Codex 5h                         │
│  ▌ 22% left · Claude Extra                     │
│  ▌ 71% left · Today                            │
└────────────────────────────────────────────────┘
```

- Rows, not concentric arcs.
- Family accent bar (▌) optional; prefer Material system surfaces over custom card chrome.
- Tap opens the phone app (Dashboard; provider detail when practical later).

## Non-goals

```text
copying concentric watch-face arcs onto the launcher
interactive controls inside the widget
iOS widgets
burying Widget config under Settings
```

## Open before lock

- Exact small/medium/large slot counts and type scale
- Stale / empty / zero-metric empty states
- Review art under `apps/phone_flutter/design/`
