---
name: android-surfaces
description: WardPulse Android ecosystem surface guidance. Use when implementing or reviewing the Flutter phone app, Kotlin/Compose Wear OS app, Watch Face Format package, phone-to-watch data flow, sync UI, credentials UI, charts, watch summaries, or Android build/project generation.
---

# Android Surfaces — WardPulse

Use this skill for `apps/phone_flutter/`, `apps/wear_android/`, and `apps/watchface_wff/`.

## Surface Responsibilities

- Phone app is the primary dashboard and settings surface.
- Plan auth: Codex = device-code OAuth; Claude = Claude Code PKCE (browser + pasted
  `CODE#STATE`); Cursor plan = in-app WebView dashboard sign-in (captures
  `WorkosCursorSessionToken`; Advanced paste via «?»). Not OAuth. Reporting rows use
  provider-appropriate keys with reporting access: OpenAI organization Admin, Anthropic
  qualifying non-workspace-scoped key, Cursor team key. Keep these separate from plan auth.
- Wear OS app is a compact dashboard, not a settings or credential-entry app.
- WFF watch face is a glanceable status surface and launcher, not a full dashboard.

## Phone App

Before implementing or reviewing any phone-shell work, read the complete
[phone rules](references/phone.md). This includes UI, widgets, credentials, settings,
repositories, Rust snapshot consumption, background sync, transport, storage,
diagnostics and build work. They map ownership and behaviour to their locked baselines.

## Wear OS App

Before implementing or reviewing any Wear-shell work, read the complete
[Wear rules](references/wear.md). This includes UI, summaries, face-like previews,
background sync/refresh, storage, complication services and build work. They preserve
Glance, ring ordering, known-zero, refresh ownership, credits and navigation contracts.
Face changes also require the WFF rules.

## Watch Face Format

Before changing or reviewing WFF, its generator/resources, complication metadata or face-like
previews, read the complete [WFF rules](references/watch-face.md) and the locked
`docs/product/WATCH_RING_DESIGN.md`. They own generator authority, geometry, slot budget,
closed TITLE vocabulary, split compatibility, textures and ambient rendering.

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
