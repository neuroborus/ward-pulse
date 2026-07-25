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
- Keep analytics UI dense, clear, and operational rather than marketing-like.

## Wear OS App

- Prefer concentric percent layers from schema v4+ (up to four selected metrics today); never
  invent `Unknown` filler. Unselected, unavailable, or exhausted (`>= 100%`) layers do not render.
- Follow the **2026-07-25 locked baseline** in `docs/product/WATCH_RING_DESIGN.md`: outer =
  tightest remaining; arc = remaining; large time hero; sunk family strips (not bordered cards);
  family colors (OpenAI/Codex green, Anthropic orange, Cursor teal, budget blue). Future
  multi-profile / hatch / three-ring cap notes there are planning-only until a later phase.
- Show optional per-provider tokens on strips / `tokenGlance` when today tokens > 0 (not a ring).
- Keep today, week, usage, providers, alerts, and last sync as secondary detail screens.
- Store and render the latest successful watch summary.
- Make stale data explicit.
- Do not enter, display, or store provider credentials.
- Keep screens glanceable; avoid long tables and cheap floating caption stacks.

## Watch Face Format

- Keep WFF declarative and minimal; follow the same concentric language as Wear (not
  side-by-side `RING 1` / `RING 2` placeholders).
- Prefer live arcs for selected layers, optional token-glance text when present, muted time.
- Support tap-to-open into the Wear OS app where possible.
- Keep ambient mode readable.

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
