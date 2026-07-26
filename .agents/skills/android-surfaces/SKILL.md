---
name: android-surfaces
description: WardPulse Android ecosystem surface guidance. Use when implementing or reviewing the Flutter phone app, Kotlin/Compose Wear OS app, Watch Face Format package, phone-to-watch data flow, sync UI, credentials UI, charts, watch summaries, or Android build/project generation.
---

# Android Surfaces — WardPulse

Use this skill for `apps/phone_flutter/`, `apps/wear_android/`, and `apps/watchface_wff/`.

## Surface Responsibilities

- Phone app is the primary dashboard and settings surface.
- Wear OS app is a compact dashboard, not a settings or credential-entry app.
- WFF watch face is a glanceable status surface and launcher, not a full dashboard.

## Phone App

- Own provider setup, credential entry, secure storage integration, platform transport, sync scheduling, diagnostics export, and Wear Data Layer send.
- Consume dashboard snapshots from Rust.
- Show today, week, month, provider list, provider details, charts, budgets, credits, sync status, and settings.
- Phase 14 primary tabs: Dashboard → Watchface → Widget → Providers → Settings. Watchface owns
  Wear/WFF ring-slot prefs; Widget owns phone home-widget prefs. Do not keep those controls in
  Settings once the tabs land (Settings “Watch display” is transitional only).
- Do not add a phone Alerts tab. Active alerts render on the Dashboard; alert rules and budget
  thresholds belong in Settings on connection rows / a global budget card (editable even when
  Not connected). Providers consumes status; it does not own rule creation.
- Keep analytics UI dense, clear, and operational rather than marketing-like.

## Wear OS App

- **App Glance (home page)** follows `docs/product/WEAR_GLANCE_DESIGN.md` (**locked 2026-07-26**):
  text legend (not a face clone) — mini remaining arcs, tightest-first, per-provider credits.
  Refresh: `OK`/`!OK` inside dual-arrow glyph; cadence = gray `OK`+disabled; provider limit =
  gray `!OK`+`Rate limited`+disabled; `Stale` = orange `!OK`+enabled. `Alerts: N` when `N > 0`.
  Phone owns allowance (`manualRefreshAllowed` / `manualRefreshAvailableAt` on schema v7)
  from the PollCadence hard floor, not the Settings auto-poll slider. Wear must not invent
  a local cooldown. Review art: `preview-glance-legend-*.png`. Compose: `GlanceLegendPage`
  (+ watch→phone refresh message).
- **Watch face / WFF** (and any face-like complication preview) follow
  `docs/product/WATCH_RING_DESIGN.md` (**locked 2026-07-25**): outer = tightest remaining; arc =
  remaining; large time hero; sunk family strips; family colors. Future multi-profile / hatch /
  three-ring cap notes there are planning-only until a later phase.
- Prefer concentric percent layers from schema v4+ on the **face** (up to four selected metrics
  today); never invent `Unknown` filler. Unselected, unavailable, or exhausted (`>= 100%`)
  layers do not render.
- Face outer strip / `creditsGlance` may show a compact remaining-credits aggregate when reported
  and Settings shows purchased usage (not a ring; never LLM `TOK`). App Glance credits stay
  **per provider** with an explicit `credits` label.
- Keep today, week, usage, providers, alerts (active list only — no rule editing), and last sync
  as secondary detail screens.
- Store and render the latest successful watch summary.
- Make stale data explicit.
- Do not enter, display, or store provider credentials.
- Keep screens glanceable; avoid long tables and cheap floating caption stacks.

## Watch Face Format

- Keep WFF declarative and minimal; follow the same concentric language as Wear (not
  side-by-side `RING 1` / `RING 2` placeholders).
- WFF format version 2 (Wear OS 5+): concentric `RANGED_VALUE` arcs with `WeightedStroke`
  colors from Wear `ColorRamp` / `[COMPLICATION.RANGED_VALUE_COLORS]`; arc = remaining.
  Keep track/progress `endAngle` under 360° (scale onto 359.9°) — a closed circle collapses
  to a ROUND tip at 12 o'clock. Prefer simple Transform arithmetic over `clamp()`.
  `BoundingArc` clips ring-slot content to the arc band — sunk `%` / credits strips must use
  separate `BoundingBox` SHORT_TEXT slots. Outer strip TEXT = full label (`100% · 500`);
  inner strips TEXT = remaining digits with Template `%%`. Avoid `length(TITLE)` Conditions —
  they are unreliable on WFF. Draw strips after `DigitalClock` so the clock does not cover them.
- Prefer live arcs for selected layers, optional `creditsGlance` on the outer strip when present,
  large time. Never LLM `TOK` on the face.
- Support tap-to-open into the Wear OS app where possible.
- Keep ambient mode readable (dim arcs, strips off).

## Phone-To-Watch Flow

Preferred MVP flow:

```text
Phone sync worker
  -> DashboardSnapshot
  -> local phone persistence
  -> WatchSummary through Wear Data Layer
  -> Wear app local storage
  -> Wear app and WFF summary rendering
```

Do not make the watch responsible for provider sync in the MVP.

## Assets

- Keep runtime images in the owning app's standard asset or resource directory.
- Export from the owning OpenPencil source; do not make platform builds depend on design tooling.
