# Watch Ring Design

**Baseline locked 2026-07-25** — accepted visual target for Wear OS and Watch Face Format until
the next explicit design revision. Implementation and review art must follow this document;
do not reintroduce side-by-side ring wireframes, large remaining-% heroes, or bordered strip cards.

Phase context: `docs/DEVELOPMENT_PLAN.md` (Phase 13). Asset ownership: `docs/DESIGN_ASSETS.md`.

Canonical review generator: `tools/render-watch-ring-designs.mjs`  
Canonical preview: `apps/wear_android/design/preview-3-plan-tokens.png` (and sibling variants).

## Goal

Glanceable **remaining** capacity for up to four user-selected percent metrics, with optional
per-provider token strips. Not “always show every provider,” and never invent `Unknown` filler.

## Layer rules

1. **One ring = one metric** — provider plan/allowance window with a %, or a local budget %.
2. **Arc = remaining** — the colored sweep is `(100 - usedPercent)`. As the limit is consumed, the
   arc shrinks. Do not grow a “used” fill toward a full circle.
3. **Outer = tightest remaining** — among selected, available, non-exhausted metrics, sort by
   remaining ascending (equivalently highest `usedPercent` first). The critical limit is outermost.
4. **Omit exhausted** — `usedPercent >= 100` (or empty/unavailable) does not render.
5. **Max four** — phone **Watchface** tab chooses slots (transitional UI may still live under
   Settings “Watch display” until Phase 14 nav lands); payload carries only the resolved
   surface order after omit + sort.

## Typography

**Noto Sans Bold** (SIL Open Font License 1.1 — free for any use, no field-of-use restrictions).
Bold/700 for time and strip labels. Vertically center strip glyphs using font metrics (not a
guessed baseline fraction).

Runtime Wear/WFF may map to the closest platform sans until a bundled Noto Sans asset is wired.

## Provider / metric colors

Primary stroke / accent color is by **family**, not by status alone. Status (warn / error / auth)
may modulate toward theme tertiary/error when needed.

| Family | Stroke | Notes |
|--------|--------|--------|
| OpenAI / Codex | `#65D78A` | Green |
| Anthropic / Claude | `#E8915A` | Orange (Anthropic presentation) |
| Cursor | `#67E8D4` | Teal |
| Local budget (Today / Week / Month) | `#8AB4F8` | Blue |

Track (empty portion of the ring): muted graphite on dark surface (`#2E3632` in review art;
theme `outlineVariant` at runtime).

## Composition (active)

```text
  ┌──── remaining arcs (0–3 typical in review; max 4 slots) ────┐
  │                                                              │
  │        upper aperture: weather reserve (empty)               │
  │                                                              │
  │                       10:08                                  │  ← large time (hero)
  │                   WARDPULSE watermark                        │  ← quiet mono, no ring
  │            ┌─ sunk well ──────────────┐                      │
  │            │▌ 8% · 12M                │                      │  ▌ = family accent
  │            │▌ 39% · 4.1M               │                      │
  │            │▌ 72% · 890K               │                      │
  │            └──────────────────────────┘                      │
  └──────────────────────────────────────────────────────────────┘
```

Rules:

- **Time is the hero** — optically centered; not a large remaining %.
- **Upper inner rim** reserved for a future weather glance (no placeholder chrome yet).
- **Watermark** — ringless mono `WARDPULSE` + pulse/eye between time and strips; low PartImage
  alpha with a bottom dissolve into the strip stack. Details: `docs/DESIGN_ASSETS.md`.
- **Lower strips** — short rounded rectangles, not full-width tablets and not stadium pills:
  - sunk into the surface (dark well, no high-contrast border card);
  - thin left **family accent** bar (color = ring family);
  - measured horizontal padding so Bold labels clear the well edges;
  - strip order = smallest amount on top (plan: smallest remaining `%`; tokens-only: smallest TOK);
  - content: `%`, tokens, or `% · tokens`; omit unused halves / omit empty strips.
- **Tokens-only**: thin framing track, large time, token strips only — no percent arcs.
- No orphan captions (`Codex left`, floating `TOK`) outside the strip row.
- Review art focuses on 1–3 provider families. A local **budget** metric may still occupy a product
  ring slot; do not ship a “4 providers” face variant in review art.

## Ambient

Muted remaining arcs (when plan rings exist) and large centered time. Strips off for ambient.

## Review variants

Regenerate with `node tools/render-watch-ring-designs.mjs`, then optional PNG previews:

```sh
convert -background none -density 144 \
  apps/wear_android/design/round-3-plan-tokens.svg \
  apps/wear_android/design/preview-3-plan-tokens.png
xdg-open apps/wear_android/design/preview-3-plan-tokens.png
```

| File | Meaning |
|------|---------|
| `round-3-plan-tokens.svg` | **Primary baseline** — three providers, plan + tokens |
| `round-2-plan-tokens.svg` | Two providers |
| `round-1-plan.svg` | Single plan ring, `%` strip only |
| `round-1-plan-tokens.svg` | Single plan + tokens |
| `round-tokens-only.svg` | No plan rings — time + token strips |
| `round-ambient-3.svg` | Ambient, three muted rings |

Wear: `apps/wear_android/design/`. WFF copies: `apps/watchface_wff/design/`.  
OpenPencil `rings.fig` is a frame inventory only (`.fig` write drops ellipse `arcData`).

## Surfaces

| Surface | Role |
|---------|------|
| Wear OS app | Compose remaining arcs + sunk strips; system time on the watch chrome |
| WFF watch face | Same language with large time hero; concentric `RANGED_VALUE` arcs in `watchface.xml` |
| Phone Watchface tab | Slot selection + preview of next payload rings (not Settings) |

## Non-goals

- Side-by-side `RING 1` / `RING 2` wireframe complications as the target language.
- Large remaining % as the aperture hero.
- High-contrast bordered strip “cards” or ring-cast drop shadows as strip chrome.
- Time-based rotation of which metric is “on top” in the first iteration.
- Brand/marketing chrome, floating badges, or dense face captions.

## Future direction (not locked baseline)

Recorded for planning only. **Do not change today’s Max four rule** until an explicit later
phase updates this document, `watchRingSlotCount`, and Phase 13 acceptance together.

- **Multi-profile per provider** — up to three profiles/accounts of the same provider may
  eventually share a device. Same-family rings on one face must then differ by
  **hatch/pattern** as well as family color (color alone is not enough for two Codex or two
  Claude windows).
- **Tighten face cap to three rings** — when multi-profile lands, drop the watch-face hard
  cap from four slots to **three** concentric plan/budget rings so the composition stays
  glanceable. Until that phase, Watchface prefs and payload remain at four.
