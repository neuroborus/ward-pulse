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
  `WorkosCursorSessionToken`; Advanced paste via «?»). Not OAuth. Platform rows stay Admin API
  keys.
- Wear OS app is a compact dashboard, not a settings or credential-entry app.
- WFF watch face is a glanceable status surface and launcher, not a full dashboard.

## Phone App

- Own provider setup, credential entry, secure storage integration, platform transport, sync scheduling, diagnostics export, and Wear Data Layer send.
- **Dashboard status marks** follow `docs/product/PHONE_DASHBOARD_DESIGN.md` (**rules locked
  2026-08-13**): `Ok` draws nothing; a rollup counts the problems rendered below it and shows a
  count where a leaf shows a glyph; family color stays
  identity; rank from `ProviderStatus::severity`, never a new list.
- Consume dashboard snapshots from Rust.
- Show today, week, month, provider plaques on Dashboard, charts, budgets, credits, sync
  status, Providers connection hub, and Settings.
- Phase 14 primary tabs: Dashboard → Watchface → Widget → Providers → Settings. Watchface owns
  Wear/WFF ring-slot prefs; Widget owns phone home-widget prefs and the Android App Widget
  (`PHONE_WIDGET_DESIGN.md` locked). Phone widget **hugs** complete rows/columns inside
  the resize cell (olive `wrap_content`; hide trailing rows and right-hand columns that
  would clip — credits → label → `%`; unused cell area is wallpaper until the user shrinks
  the span), vertical+horizontal resize (default ~3 cells), day/night chrome, overlay face
  watermark (no header band), expands Claude windows, keeps exhausted plan pools as
  `0% left`, and appends per-provider purchased credits end-aligned (label centered).
  Watchface still collapses Claude, choosing the tightest known window including zero;
  exhausted selected watch metrics remain visible after the 2026-10-13 revision. Do not keep
  those controls in Settings.
- **Providers** owns the full connection catalog (Connected / Not connected), credentials /
  auth, and **all user-configured** alert thresholds (plan/purchased per connection;
  Today/Week/Month budgets on OpenAI Platform). One threshold per meter; UI speaks
  **% left** (storage/Rust keep used% as `at`). Editable before first sync. Do not keep
  alert rules under Settings.
- **Settings** is systemic only: global polling interval, diagnostics, data deletion,
  legal, debug toggles — not connections, credentials, display surface toggles, or alerts.
- Do not add a phone Alerts tab. Active alerts render on the Dashboard. Thresholds are
  **user-configured only** — never invent alerts from hard-coded 80%/100% utilization cutoffs.
  Provider status chrome (Warning / RateLimited) is separate from the alerts list.
- Keep analytics UI dense, clear, and operational rather than marketing-like.

## Wear OS App

- **App Glance (home page)** follows `docs/product/WEAR_GLANCE_DESIGN.md` (**locked 2026-07-26**):
  text legend (not a face clone) — mini remaining arcs, tightest-first, per-provider credits.
  **2026-09-16 revision:** one row per band, at most three rows. A known pair has two
  mini-tracks with coloured arcs for positive values and inner-first percentages,
  title = family + ` plan` (`Cursor plan`),
  subtitle = `82% · 41% left · 320 credits` (credits once, omitted when unavailable).
  **2026-10-13 selected-zero revision:** known exhausted halves retain the pair, both grey
  tracks and both percentages; only true exhausted `0%` tokens use `#FFB4AB`. Titles,
  separators, credits and family identity stay unchanged; a tiny positive fraction rounded
  to `0%` stays ordinary. Unknown/unavailable (including non-finite or negative usage) remains
  absent; selected entries with no known percentage say `Ring data unavailable`. Keep typography, 54-unit row
  pitch and 12-unit Alerts clearance. Paired-row fit/clipping was verified under injected load
  on round/notround devices on 2026-10-01; a live Codex/Spark payload remains unverified.
  Refresh: `OK`/`!OK` inside dual-arrow glyph; cadence = gray `OK`+disabled; provider limit =
  gray `!OK`+`Rate limited`+disabled; `Stale` = orange `!OK`+enabled. `Alerts: N` when `N > 0`.
  Phone owns allowance (`manualRefreshAllowed` / `manualRefreshAvailableAt` on schema v7)
  from the PollCadence hard floor, not the Settings auto-poll slider. Wear must not invent
  a local cooldown. Review art: `preview-glance-legend-*.png`. Compose: `GlanceLegendPage`
  (+ watch→phone refresh message).
- **Watch face / WFF** (and any face-like complication preview) follow
  `docs/product/WATCH_RING_DESIGN.md` (**locked 2026-07-25**; later revisions are listed in the
  document header): **inner/center = tightest**
  remaining (plan `%` primary; credit request-runway secondary from internal costs — never show
  request counts); arc = remaining (clockwise melt from 12); large time hero; sunk family strips
  (equal width; first strip nearest center; stroke tuned so 3 strips clear arcs); family colors.
  Hard cap: **three** concentric plan/budget rings (`watchRingSlotCount = 3`). Purchased meters
  (Extra usage, on-demand, Codex credits) are not ring candidates — phone cards only; alerts
  only via user thresholds on Providers.
  Future multi-profile / hatch notes there are planning-only until a later phase.
- Claude plan windows (`5h` / weekly / Opus / Sonnet) collapse to one watch ring on the phone
  (`allowance.claude.plan`); Glance names the selected tightest known window, including zero.
  Phone dashboard still lists all.
- Prefer concentric percent layers from schema v4+ on the **face** (up to three selected metrics);
  never invent `Unknown` filler. Unselected or unavailable layers do not render. Selected
  known exhausted (`>= 100%`) layers keep grey tracks and legend rows, including a known pair
  with one or both halves at zero. Only exhausted `0%` numeric tokens use the existing
  phone dark-theme error role `#FFB4AB`; budget money labels, credits and family markers stay
  unchanged. Exhaustion styling does not infer alerts, thresholds or refresh state.
- Face strips show compact remaining credits per provider family from `allowances` (`% · 500`),
  same matching rule as Glance; accents use the family ColorRamp. `creditsGlance` is for
  credits-only faces when there are no plan rings.
- The app keeps two home pages: **Glance** and **Plan windows**, which says when each window
  comes back (rules in `apps/wear_android/README.md`). **Alerts** opens from the Glance pill
  (active list only — no rule editing). A **Watch face** action after all Plan windows rows,
  also below the no-summary sync prompt, opens a separate setup utility route, not another
  home page. Follow the dated baseline
  [Revision 2026-10-16 — watch-face utility entry](../../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry).
  The today, week, usage, providers, and last sync screens were removed in
  Phase 17; do not bring a currency total back to the watch.
- Store and render the latest successful watch summary.
- Make stale data explicit.
- Do not enter, display, or store provider credentials.
- Keep screens glanceable; avoid long tables and cheap floating caption stacks.

## Watch Face Format

- `watchface.xml` is written by `tools/render-watchface.mjs` (`just render-watchface`), together
  with the ring-type drawables it names (`res/drawable-nodpi/`, ImageMagick as `just
  export-icons` already uses). Change the generator, never the XML or the PNGs;
  `just check-watchface` fails on drift, and `node tools/render-watchface.mjs --check` proves
  the same drift without the network that the Gradle half of it needs — see `AGENTS.md`,
  *When a check cannot run where you are*. Geometry and canvas are both the **450**-unit design
  language `WATCH_RING_DESIGN.md` locks — the canvas is what WFF renders at before scaling to
  the screen, so raising it softens every edge on the face. Do not raise it to sharpen type:
  WFF rounds each glyph of a `TextCircular` to a whole canvas unit, and the answer to that is
  baking, not resolution.
- Keep WFF declarative and minimal; follow the same concentric language as Wear (not
  side-by-side `RING 1` / `RING 2` placeholders).
- **A scene holds at most eight `ComplicationSlot` elements** — the same in format versions 2, 4
  and 5, so raising the version buys nothing. This face has used all eight since 2026-07-25
  (since the **2026-09-16** revision: three bands, two outer-half slots, three strips).
  Slots 106/109 serve split ordinals 0/1 in payload order; both receive an outside-counted
  band index through `RingSurfaceOrder` in TITLE. A missing selected half yields `NoData`;
  a known exhausted selected half carries real zero, retaining pair identity and ordinal.
  Keep both service names and updater entries.
  An old face loses the far marker with one pair; with two, the first keeps both arcs without
  its marker, while the second loses its outer arc and slot 109 may mark another row. Updating
  the face fixes the layout. Count before designing anything that needs a new slot — the validator
  never says "too many slots": a ninth is reported as `Invalid content was found starting with element
  'ComplicationSlot'`, listing `PartText`, `PartImage`, `Condition` and friends as what it
  expected instead.
- WFF format version 2 (Wear OS 5+): concentric `RANGED_VALUE` arcs with `WeightedStroke`
  colors from Wear `ColorRamp` / `[COMPLICATION.RANGED_VALUE_COLORS]`; arc = remaining.
  Keep track spans under 360° (scale onto 359.9°) — a closed circle collapses
  to a ROUND tip. Remaining melts **clockwise from 12**: Transform `startAngle`
  with `(1 - value/max) * 359.9` and fixed `endAngle` 359.9. Prefer simple
  Transform arithmetic over `clamp()`.
  Since 2026-10-09, full-canvas `BoundingBox` band slots draw both the true 20-unit band and
  their own sunk strip; no separate strip slots are added. Keep strip wells **equal width**
  and inside the clear aperture. Every strip TEXT = full label (`46%` or `100% · 500`);
  accents use `[COMPLICATION.RANGED_VALUE_COLORS]` for the inner pool. Combined TITLE bases
  `split`, `split:cursor-other`, `split:spark` keep the outer marker's family identity;
  known zero suffixes must preserve marker selection. Cursor's marker is static `#67E8D4`,
  Spark's `#186020`, both 3x14. Marker equivalence was measured 2026-10-12; a live Codex/Spark
  payload remains a separate unverified condition. New measurements need a date and actual device; the planned target is the
  round API-36 `wardpulse_wear_round_api36_1` emulator, not shipped watch hardware.
  Avoid `length(TITLE)` Conditions — they are unreliable on WFF. Draw strips after `DigitalClock` so the clock does not cover them.
- A ring slot's TITLE carries an empty token for an ordinary positive plan, `zero` for an
  exhausted ordinary plan, or one paired base (`split`, `split:cursor-other`, `split:spark`)
  optionally suffixed with `:zero-inner`, `:zero-outer`, `:zero-both` (twelve closed paired
  spellings). Match the full closed vocabulary, not loose prefix tests. Budget period tokens
  (`D` / `7D` / `M`) remain unchanged. For a budget ring the
  face repeats it around that band as background-colour cut-out type, branching on
  `[COMPLICATION.TITLE]` equality to pick one baked image per ring and period. The type runs in
  four sweeps with a bare break on each diagonal, aligned across rings; within a sweep tokens are
  placed by rotation, and the repeat counts in `tools/render-watchface.mjs` are the fitted
  constants both that generator and the review-art one read — copy, never hand-tune.
- Prefer live arcs for selected layers, optional `creditsGlance` on the **matching provider**
  strip when present, large time. Never LLM `TOK` on the face.
- Support tap-to-open into the Wear OS app where possible.
- Keep ambient mode readable: dim the arcs, and dim the strips rather than switching them off —
  a strip's credits and budget money are carried nowhere else on the face.

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
