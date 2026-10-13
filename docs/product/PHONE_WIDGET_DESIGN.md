# Phone Widget Design

**Status: locked 2026-07-27** (revised **2026-07-28** — hug rows/columns, label-center /
credits-end, picker preview sample, day/night olive chrome; revised **2026-08-02** —
two-line label carrying the provider family; revised **2026-10-13** — stale badge clearance
and reliable Dashboard navigation). Review art:
`apps/phone_flutter/design/` (`widget-small.svg` / `widget-medium.svg` / `widget-dark.svg`).

**Revision 2026-09-16 — Codex windows:** Codex and Spark remain per-window metrics on
the widget, with existing selections preserved. Their Watchface collapse/pairing does not
change widget behavior or geometry.

**Revision 2026-10-13 — stale clearance and widget navigation.** On the canonical phone
AVD `wardpulse_phone_play_api36`, launcher widget instance **2** showed genuine retained
failed-refresh data. `STALE` occupied **[93,562][188,601]**, intersecting the first
percentage at **[122,581][306,624]** and its accent. A warm widget tap from Settings also
returned to **Settings**, rather than Dashboard. These are observed defects; the fresh-only
2026-10-11 acceptance below did not cover either state.

The approved correction reserves space above the rows **only while stale**: the current
**11sp bold** badge line, including font padding, plus **2dp**. Runtime measures that line
with the current display/font metrics and uses the **same pixel inset** for row padding and
complete-row fitting. Fresh geometry and launcher-owned spans/options remain unchanged.
If resolved metrics exist but no complete row fits, show **`Resize widget`**; an empty or
unavailable payload still says **`No metrics`**. The watermark remains top-end. A widget tap
carries an explicit Dashboard action with a separate native/Dart readiness handshake, so
cold and warm delivery select Dashboard without adding a provider-refresh action. An explicit
widget tap first cancels active in-app forms and pushed routes with normal Cancel/back
semantics; ordinary app opens and watch-requested refresh preserve those routes.

**Device acceptance 2026-10-13.** The final Android x64 APK on this canonical phone kept
widget instance **2** in **[67,546][1013,1449]**, a 903px-high launcher frame. Genuine retained
failed-refresh data at normal font scale in light mode had a **39px** badge ending at
`y=601`; the first label began at `y=606`,
leaving **5px** clearance with a **44px** content inset. After a real app refresh at system
font scale **1.5** in dark mode, the badge measured **58px**, ending at `y=620`; the first
label began at `y=625`, again **5px** clear, with a **63px** inset. Both fresh and stale
placement were checked. These measurements establish badge clearance in this tall frame;
the fixed 12sp columns still ellipsize some labels and percentages at scale 1.5, as before.

An actual narrower frame **[67,546][519,1449]** removed label and credits columns while
retaining percentages. Its stale first percentage began at `y=606`, **5px** below the badge.
The original **four-column × three-row** placement was then restored to its exact bounds.
Warm taps from Settings and an open Budget dialog visibly opened Dashboard, canceling the
dialog. A settled background process was confirmed dead before the cold widget tap started
a different process; loading completed with three providers and data updated at **17:35:48**.
Host format/analyze and all **391** Flutter tests passed, including the navigation regressions;
the native widget harness passed **28** assertions. The existing 31dp body-row estimate
remains unchanged. Very short hosts, the `Resize widget` fallback on a launcher and text
scales above 1.5 remain separate device-fit checks; no hardware-device coverage is claimed.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 14). Asset ownership: `docs/DESIGN_ASSETS.md`.
Do **not** copy [`WATCH_RING_DESIGN.md`](WATCH_RING_DESIGN.md) layouts onto the phone launcher.

## Goal

A rectangular, glanceable **remaining** summary on the Android home screen — the same pulse
question as Wear/WFF, with a **phone-native** composition (system theming, multi-metric rows).
Configuration lives on the phone **Widget** tab and is **independent** of Watchface ring slots.

## Metric rules

1. **One slot = one percent metric of one connection** — one connection's local budget for a
   period, a provider plan window, or a purchased meter (Extra usage, on-demand, credits %) when
   the provider reports a %. There is no summed Today / Week / Month slot: see
   `WATCH_RING_DESIGN.md` layer rule 1 for why a percentage across connections has no owner.
2. **Claude and Codex plan windows stay expanded** on the phone widget: Claude `5h`,
   `Weekly`, Opus/Sonnet weekly when present; Codex main and Spark primary/secondary
   windows when reported, including `Spark 5h` / `Spark Weekly`. Existing per-window
   selections survive unchanged. Watchface/Glance collapse Claude to one ring and Codex
   independently to one main-limit ring and one Spark ring before pairing.
3. **Cursor Models and Other Models** are separate selectable rows whenever the usage-summary
   reports both pool percents.
4. **Remaining language** — display `(100 - usedPercent)` for percent metrics; family colors match
   the product palette in `WATCH_RING_DESIGN.md`, where a Cursor plan's two pools carry their own
   colors since 2026-08-13. A budget row takes the family color of its connection; the neutral
   grey is a fallback for an unresolved family, not a product color.
5. **Purchased credits** — on **plan** rows, when that provider family reports finite purchased
   remaining credits, show Glance-style columns: `N% left` · label · `N credits` (compact
   count + `credits` unit). Same per-provider rule as Wear Glance / face strips — not a
   footer sum, not `creditsGlance`, never LLM `TOK`. Skip on purchased-meter rows (Extra
   usage / on-demand are the credit pool), budgets, and missing/unlimited balances.
6. **Omit** unavailable metrics (no percent). Exhausted plan/purchased meters (`usedPercent >= 100`)
   stay on the phone widget as **`0% left`** so sibling pools remain visible. Watch/WFF likewise
   retain known selected exhausted metrics under their 2026-10-13 revision. The Widget tab
   states unavailability rather than hiding it: a metric with no
   percentage lists as unselectable under its own reason — *This allowance has no percentage to
   show*, seen on `Purchased credits` 2026-10-11 — so the rule is legible to whoever is choosing.
7. **No credentials**, account ids, or raw provider payloads on the widget or in widget logs.

## Size caps (locked)

| Size | Slots shown | Notes |
|------|-------------|--------|
| Short | **1–2** | fewer metrics in Widget tab (~1–2 cells) |
| Mid | **3–5** | typical place size (`targetCellHeight≈3`) |
| Tall | **6** | prefs cap (`phoneWidgetSlotCount`) |

Prefs select up to **six** metrics; the olive card shows as many **complete** resolved
rows as fit the host cell, and as many **complete** columns as fit the width
(`wrap_content` hug). Trailing rows / right-hand columns that would clip are omitted —
never half-cut text. Horizontal drop order: **credits → label → `% left`**. Vertical /
horizontal resize changes the launcher span; drag handles to the card to reclaim empty
cells. Newly placed widgets default to ~3 cells tall; **remove and re-add** if an old
tall span stays stale. Unused slots stay omitted, not filled.

Default (unset) selection prefers **plan windows** first (Claude + Cursor + Codex), then
purchased meters, then local budgets — so 5h / weekly / Cursor Models / Other Models are not
crowded out by Extra usage. A budget row only becomes selectable once its connection has a
limit for that period, so an unconfigured install defaults to plan windows.

## Composition (locked)

```text
┌─ olive card hugs complete rows + columns ──────┐
│  ▌ 22% left     Claude       80 credits   ⌇wm  │  ← tightest remaining first
│  ▌            Weekly plan                      │
│  ▌ 46% left     Claude      320 credits        │
│  ▌           5-hour session                    │
│  ▌ 71% left  Cursor Models  2.1K credits       │
└────────────────────────────────────────────────┘
┌─ mid (credits dropped) ────────────────────────┐
│  ▌ 22% left    Weekly                     ⌇wm  │
│  ▌ 46% left      5h                            │
└────────────────────────────────────────────────┘
┌─ narrow (% only) ──┐
│  ▌ 22% left   ⌇wm  │
│  ▌ 46% left        │
└────────────────────┘
     (transparent cell beyond the card if the span is larger)
```

- Rows, not concentric arcs.
- Family accent bar (▌) on each metric row.
- **Columns** — `% left` · centered label · credits (end-aligned). Width hide order:
  credits first, then label; missing credits still reserve the credits column when that
  column is shown (label stays centered).
- **Label is two lines** (revised **2026-08-02**) — family on top, pool below. The provider
  must be readable at the baseline text scale; larger scales can ellipsize the fixed-width
  columns, as measured at 1.5 in the 2026-10-13 acceptance above. Nothing else names it:
  colour alone cannot tell one `Weekly plan` from another. The column keeps its fixed
  width, so the cost is height, not width: rows are `ROW_CONTENT_DP` 31 instead of 17 and
  the card hugs taller. Every row reserves both lines (`android:lines="2"`), so a label
  that already carries its family — `Cursor Models` — leaves the second line empty rather
  than making rows uneven.
- **Day / night** — olive phone chrome (`#F2F4F1` / `#101412` via `values` /
  `values-night`), not provider fills. Soft 20dp card + hairline outline; runtime card
  **hugs** complete content so unused cell area is wallpaper. Widget-picker preview uses a
  dedicated sample layout (`ward_pulse_app_widget_preview`) that hugs the sample rows
  (no empty olive band under them) and follows the same day/night colors when the system
  theme is dark.
- **Resize** — `horizontal|vertical` with **no** tight `maxResizeHeight` (a span taller than
  the max makes Pixel drop vertical handles). Height / width decide how many **complete**
  rows / columns fit. Newly placed widgets use `targetCellHeight≈3`; **remove and re-add**
  after metric-count changes if the launcher keeps a stale tall span.
- **Watermark** — same faded mono as the watch face, ~36dp overlay top-end (does not
  reserve a header band). Fresh widgets have no dedicated header.
- Empty: short “No metrics” line (no filler rows).
- Too short for a complete resolved metric: “Resize widget”, with no clipped metric rows.
- Stale: compact uppercase “STALE” top-start when the last dashboard is stale. Reserve its
  measured padded line plus 2dp above content and subtract that same space when fitting rows;
  remove the inset when fresh.
- Tap opens the phone app (Dashboard).

**Verified on a device 2026-10-11 — the baseline holds.** Locked since 2026-07-27 and revised
three times, this composition had never been read off a launcher. It was, on the canonical phone
AVD `wardpulse_phone_play_api36` at `fad6bb9`, paired live with the round Wear AVD so the payload
was the one the watch was drawing. Nothing measured contradicted a rule above.

Five selected metrics, placed from the picker — whose entry declares **3 × 3** and whose preview
hugs its three sample rows with no empty olive band beneath them:

```text
40% left    Claude / 5-hour session     ← tightest remaining first
68% left    Cursor / Other Models
72% left    Claude / Weekly plan
92% left    Codex  / Weekly plan
100% left   Cursor Models               ← second label line empty, rows stay even
```

**That order held under a live change.** Later the same session a Claude window crossed its own
threshold unprompted, with nothing staged and the phone untouched, and the placed widget
followed by itself: the top row became `13% left · Claude / 5-hour session` and the list
re-sorted to `13 / 67 / 68 / 92 / 100`. No reinstall, no re-placement, no visit to the Widget
tab. Tightest first is a rule the surface keeps as the numbers move, not an arrangement that
happened to be true at the moment it was first read.

**Hug and drop order**, taken from the view hierarchy rather than from a screenshot:

| Span | Launcher cell | Olive card | Credits column |
|------|---------------|------------|----------------|
| as placed | 699 × 903 px | 544 × 489 px | dropped |
| widened | 946 × 903 px | 791 × 489 px | **shown** |

The card hugged 544 px inside a 699 px cell and omitted credits; widening the span to 946 px
brought them back as `62.5K credits`, end-aligned on the Codex `Weekly plan` row, with the four
rows carrying none still reserving the column and keeping their labels centred. Compact is metric
rule 5 and agrees with the face strip and the Glance row — the Dashboard spells the same balance
`62,479.3 credits` (`PHONE_DASHBOARD_DESIGN.md`, Balances), because compaction belongs to a
glance and that screen is not one.

**Chrome sampled from the live card:**

| Theme | Sampled | Declared |
|-------|---------|----------|
| light | `#F2F4F1` | `ward_pulse_widget_surface` in `values/colors_widget.xml` |
| night | `#101412` | the same name in `values-night` |

Exact both times. Switching the system theme swapped surface, text, accents and watermark
together and left the composition alone.

Also confirmed: accent bars in the product palette (Claude orange, Cursor Other Models teal,
Cursor Models periwinkle, Codex green); the watermark top-end with no header band reserved; a tap
opening `app.wardpulse/.MainActivity`; and the empty state hugging one `No metrics` line with no
filler rows, its watermark overlapping that line exactly as `widget-empty.svg` draws it.

**Not reached: the `STALE` overlay.** The payload on the device was fresh, so nothing was observed
of it and nothing here claims otherwise. One AVD, one build, one launcher.

## Non-goals

```text
copying concentric watch-face arcs onto the launcher
interactive controls inside the widget
iOS widgets
burying Widget config under Settings
collapsing Claude plan windows on the phone widget (Watchface only)
```

## Review art

Canonical review generator: `tools/render-phone-widget-designs.mjs` — it reads the accent and
chrome colours straight from `res/values{,-night}/colors_widget.xml`, so the boards cannot drift
from the app without the resource moving too.

```sh
node tools/render-phone-widget-designs.mjs
```

| File | Role |
|------|------|
| `widget-medium.svg` | light mid preview (credits + watermark) |
| `widget-dark.svg` | dark mid preview (same composition) |
| `widget-small.svg` | short (2 rows); default place size ≈ 2×2 |
| `widget-empty.svg` | empty selection |
| `widget-stale.svg` / `widget-stale-dark.svg` | stale-only badge clearance in day/night chrome |
| `widget-stale-narrow.svg` | stale badge with only the complete percentage column |
| `widget-stale-short.svg` | known metrics cannot fit a complete row; `Resize widget` |
