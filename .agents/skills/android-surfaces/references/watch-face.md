# Watch Face Format rules

Read for WFF, its generator/resources, complication metadata or face-like previews routed by
[android-surfaces](../SKILL.md), together with the [Wear rules](wear.md) and locked design.

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
