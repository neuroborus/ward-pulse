# Wear OS app rules

Required for all Wear-shell work routed by [android-surfaces](../SKILL.md), including
UI, summaries, face-like previews, background sync/refresh, storage, complication
services and build work.

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
  absent; selected entries with no known percentage say `Ring data unavailable`.
  **2026-10-24 readability revision:** title/subtitle target 20/18, bounded measured fitting
  at 18–20/16–18, maximum centered width 370 and scaled 62-unit pitch. Measure every row's
  complete height independently of width overflow, with the unchanged 39-unit arc floor.
  Supported overflow wraps fully with original numeric coloring; keep system font scaling.
  Height overflow scrolls only the legend, ending at y=346 with six units reserved for its
  position indicator. Keep vertical drags/flings local at both limits, horizontal back,
  outside paging, accessibility page/local-scroll actions, focused rotary input and retained/
  clamped position. Preserve fixed refresh/status and Alerts, empty-state type/placement and
  at least 12-unit Alerts clearance. New art/build/device acceptance is Pending. The
  2026-10-01 injected round/notround fit readings apply only to their older builds;
  a live Codex/Spark payload remains unverified.
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
  [Revision 2026-10-16 — watch-face utility entry](../../../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry).
  The today, week, usage, providers, and last sync screens were removed in
  Phase 17; do not bring a currency total back to the watch.
- Store and render the latest successful watch summary.
- Make stale data explicit.
- Do not enter, display, or store provider credentials.
- Keep screens glanceable; avoid long tables and cheap floating caption stacks.
