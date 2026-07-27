# Design Assets

WardPulse brand marks are generated from `tools/render-brand-icons.mjs`. OpenPencil
`.fig` sources remain optional for hand editing; runtime builds consume SVG/PNG exports.

![WardPulse app icon](../brand/icons/wardpulse.svg)

Monochrome watch-face watermark (runtime PNG includes the bottom dissolve):

![WardPulse mono watermark](../brand/icons/previews/wardpulse-mono-on-dark.png)

## Format And Viewing

For a quick visual check, open the tracked SVG or a preview PNG:

```sh
xdg-open brand/icons/wardpulse.svg
xdg-open brand/icons/previews/wardpulse-mono-on-dark.png
```

The Design Assets page is also available through the local documentation site:

```sh
just docs-dev
```

OpenPencil installation is optional. Use the [web app](https://app.openpencil.dev/) without
installing anything, or install a desktop build from the
[official releases](https://github.com/open-pencil/open-pencil/releases) for offline editing.
`brand/icons/wardpulse.fig` may lag the SVG generator until resynced by hand.

## Ownership

- Shared WardPulse identity sources belong in `brand/icons/`.
- Watch-face placement previews live under `brand/watchface/` (not a second SVG source).
- App-specific sources belong in a `design/` directory under the owning app
  (phone widget review art: `apps/phone_flutter/design/` when Phase 14 locks
  `docs/product/PHONE_WIDGET_DESIGN.md`).
- Exported runtime assets belong in the consuming platform's normal asset or resource directory.
- Keep only locked previews under `brand/watchface/` — no scratch placement boards.

Runtime targets are `apps/phone_flutter/android/app/src/main/res/`,
`apps/wear_android/app/src/main/res/`, and `apps/watchface_wff/src/main/res/`.

Do not create a repository-wide design system or duplicate a source file between owners. Files
under `brand/` remain outside the Apache-2.0 source license unless explicitly stated otherwise.

## Palette

- App mark body: metallic gray (`#8A9298` → `#2A3035` sheen).
- App mark framing ring (product metaphor): OpenAI/Codex `#65D78A`, Cursor `#67E8D4`,
  Anthropic `#E8915A` — three equal arcs around the metal disc.
- On-mark foreground: `#F4FBF8`.
- Watch-face watermark stroke: `#C5CDD1` (muted further by PartImage alpha + bottom fade).
- Dark surface: `#101412` (adaptive launcher background).
- Warning: `#E6C349`.

### Phone chrome (not provider colors)

Phone Material primary is gray-olive so Codex/OpenAI green and Cursor teal stay reserved for
metrics:

- Primary: `#5F675C` (light) / `#A7B09E` (dark).
- On-primary: `#F4FBF8` (light) / `#1A1F1A` (dark).
- Primary container: `#E4E7DF` (light) / `#3A4038` (dark).
- OK status pills use the same olive — not `#65D78A`.

Legacy performance teal/green (`#006B60` / `#67E8D4`) and “success = Codex green” are retired
from phone chrome. Legacy brand green (`#1F7A5A` sheen) stays out of new identity surfaces.

### Metric family accents

Used on Wear / WFF rings and on phone charts / plan bars / provider section accents
(see [product/WATCH_RING_DESIGN.md](product/WATCH_RING_DESIGN.md)):

- OpenAI / Codex: `#65D78A`.
- Anthropic / Claude: `#E8915A`.
- Cursor: `#67E8D4`.
- Local / platform budget: `#8AB4F8`.

Review exports: `tools/render-watch-ring-designs.mjs` → `round-*-plan-credits.svg`
(matching-provider strip may append remaining purchased credits, never LLM `TOK`;
remaining arcs melt clockwise from 12). Primary preview:
`apps/wear_android/design/preview-3-plan-credits.png`.

Wear **app** Glance legend (**baseline locked 2026-07-26**, not the face):
`tools/render-wear-glance-designs.mjs` → `glance-legend-*.svg` /
`preview-glance-legend-*.png`. Primary preview:
`apps/wear_android/design/preview-glance-legend-3.png`. Variants: `3`, `1`, `budget`,
`stale`, `cadence`, `rate-limit`, `empty`, `exhausted`.
See [`product/WEAR_GLANCE_DESIGN.md`](product/WEAR_GLANCE_DESIGN.md).

Family colors are for metric identity, not buttons, nav, or filled chrome.
**Exception:** the official app logo framing ring intentionally echoes those three families as a
product metaphor. Do not spread that tri-color chrome into buttons, cards, or other UI.

## Mark

The metal disc reads as a monitoring instrument. The framing ring ties the product to the watch
ring language. The pulse communicates activity and throughput. The small eye signals watchful,
local monitoring — keep it in the upper-right of the mark and preserve its scale relative to the
pulse.

Use the **color metal+ring** mark for phone and Wear launchers.

### Watch-face watermark (locked)

Quiet branding on WFF — not a second hero. Locked with the concentric face baseline:

- **No framing ring** — straight `WARDPULSE` wordmark above the pulse + eye.
- **Placement** — between time and sunk strips; upper aperture stays free for weather.
- **Size / mute** — about 72×72 on the 450 canvas; PartImage `alpha≈95` (~37%).
- **Bottom dissolve** — content-relative fade toward the strip stack
  (`tools/fade-watermark-png.py` during `just export-icons`), so the pulse softens into
  the metrics instead of competing with them.
- Eye placement matches the color mark; pupil stays inside the almond rim.

Canonical preview: `brand/watchface/preview-face-active-quiet.png`.

## Source And Runtime Files

| Role | Path |
|------|------|
| Color logo (canonical SVG) | `brand/icons/wardpulse.svg` |
| Mono watermark (canonical SVG) | `brand/icons/wardpulse-mono.svg` |
| PNG previews (incl. faded mono) | `brand/icons/previews/` |
| Face placement preview | `brand/watchface/preview-face-active-quiet.png` |
| Phone / Wear launcher mipmaps | `mipmap-*/ic_launcher.png` |
| Phone adaptive foreground | `drawable-*/ic_launcher_foreground.png` |
| WFF runtime mono (faded PNG) | `apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png` |

Prefer regenerating exports with `just export-icons` rather than editing PNGs by hand. The mono
drawable must go through `tools/fade-watermark-png.py` (wired in `tools/export-icons.sh`).
Commit runtime exports when an application build consumes them.

ImageMagick is required; Inkscape is preferred for mono SVG→PNG when available.
`tools/fade-watermark-png.py` needs Pillow (`pip`/`apt` package `python3-pil`).

## Setup

The repository pins the OpenPencil CLI as an npm development dependency for optional `.fig`
workflows. Install with the existing workspace toolchain:

```sh
npm ci
```

## Export

Regenerate SVGs, previews, launcher PNGs, and the faded watch-face mono drawable:

```sh
just export-icons
```

Do **not** run `just export-design brand/icons/wardpulse.fig …` until the `.fig` is resynced
to the metal+ring mark — an old `.fig` would overwrite the canonical SVG.
