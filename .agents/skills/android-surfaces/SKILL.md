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

- Prefer configurable percent rings from schema v4 (up to four); never invent `Unknown` filler.
- Keep today, week, usage, providers, alerts, and last sync as secondary detail screens.
- Store and render the latest successful watch summary.
- Make stale data explicit.
- Do not enter, display, or store provider credentials.
- Keep screens glanceable; avoid long tables.

## Watch Face Format

- Keep WFF declarative and minimal.
- Prefer `RANGED_VALUE` arcs for the first selected rings, with `SHORT_TEXT` fallback, plus status.
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
