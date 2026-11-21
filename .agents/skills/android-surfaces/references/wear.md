# Wear OS app rules

Required for all Wear-shell work routed by [android-surfaces](../SKILL.md), including
UI, summaries, face-like previews, background sync/refresh, storage, complication
services and build work.

- **App Glance (home page)** follows `docs/product/WEAR_GLANCE_DESIGN.md` (**locked 2026-07-26**):
  text legend (not a face clone) — mini remaining arcs, tightest-first, per-provider credits.
  **2026-09-16 revision:** one row per band, at most three rows. A known pair has two
  mini-tracks with coloured arcs for positive values and inner-first percentages,
  title = `Cursor / Others` only for exact inner `allowance.cursor.cursor-plan-models`
  plus outer `allowance.cursor.cursor-plan-other`; other pairs keep family + ` plan`
  (`Codex plan`), except the exact Claude/Fable pair below,
  subtitle = `82% · 41% left · 320 credits` (credits once, omitted when unavailable).
  **2026-11-01 Fable rendering:** exact inner `allowance.claude.plan` plus outer
  `allowance.claude.claude-seven-day-fable` titles the row `Claude / Fable`.
  Keep ordinary Claude `#E8915A`, exact Fable `#FF603D` (approved warm red with an orange
  tint), fixed inner-first percentages,
  credit eligibility and known-survivor fallbacks. This Source/review-art revision is
  not native/public acceptance. Phone catalogue/admission keeps three bands and two splits,
  with explicit invalid saved choices requiring removal instead of silent trimming. Keep the
  last watch summary while correction is needed; local phone/widget updates continue.
  **2026-10-13 selected-zero revision:** known exhausted halves retain the pair, both grey
  tracks and both percentages; only true exhausted `0%` tokens use `#FFB4AB`. Titles,
  separators, credits and family identity stay unchanged; a tiny positive fraction rounded
  to `0%` stays ordinary. Unknown/unavailable (including non-finite or negative usage) remains
  absent; selected entries with no known percentage say `Ring data unavailable`.
  **2026-10-24 clock-free refinement:** supersedes the historical 20/18/62 iteration.
  Title/subtitle prefer 27/23, bounded measured fitting at 18–27/16–23, maximum centered
  width 360 and scaled 75-unit pitch. Independently round each full 37/32 line reservation,
  then the complete row including its 2-scaled interline gap and 4-scaled breathing room;
  measure every row independently of width overflow, with the unchanged 39-unit arc floor.
  Supported overflow wraps fully with original numeric coloring; keep system font scaling.
  Height overflow scrolls only the legend, ending at y=346 with six units reserved for its
  position indicator. Keep vertical drags/flings local at both limits, horizontal back,
  outside paging, accessibility page/local-scroll actions, focused rotary input and retained/
  clamped position. Start the legend 10 below the actual measured header. The unchanged
  68-unit refresh control moves to top 20; Alerts stays at top 372 with all dimensions,
  styles, actions and at least 12-unit clearance unchanged. Empty copy/type stays 16 and
  centers in the new region. Hide the shared clock only on summary-backed Glance (including
  empty selection); retain it on settled Plan windows, Alerts, Watch face utility and
  pre-summary Empty Dashboard, restoring it through navigation/back/summary/recomposition.
  Ordinary default three-row/detail content must fit fully at 27/23 without local scrolling;
  report native failure to fit. The 2026-10-25 HOST record covers Round's 32 native tests
  and 12 navigation tests each on Square and API 34, including local/Pager actions.
  Physical 466 active Glance/Face were verified while charging and securely unlocked.
  Public browser placement passed; unchanged generators produced 136 byte-matching outputs
  in a throwaway HOST checkout without canonical writes. Round Face AOD does not prove
  Glance/physical AOD; full variant/interaction remains open. The complete canonical paired
  HOST gate passed after fresh builds and renewed Wear native tests. Follow the dated
  [clock-free revision](../../../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-24--clock-free-glance-and-larger-legend).
  The 2026-10-01 injected round/notround fit readings apply only to their older builds;
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
  credits-only faces when there are no plan rings, including unset/default preferences and
  nonempty selections with unavailable ring data. An explicit empty phone `selectedIds`
  publishes no rings and `creditsGlance: null`, clearing the standalone credit row.
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

## Navigation test geometry

`AccessibilityNodeInfo` bounds can be clipped by a sibling clock; they are not the native viewport.
Follow [`WardPulseNavigationStateTest.nativeSurface`](../../../../apps/wear_android/app/src/androidTest/java/app/wardpulse/wear/ui/WardPulseNavigationStateTest.kt):
use public `ViewRootForTest` layout and standard scroll ranges for geometry and settlement,
while real accessibility actions continue to prove behavior. Calibrate ordinary touch gestures
against the measured viewport, touch slop and paging threshold, preserving real input.
Keep bounded observable-state predicates and useful diagnostics when their deadline expires;
do not substitute sleeps, repeated gestures or state resets for the required failure.
