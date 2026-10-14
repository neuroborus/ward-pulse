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

Read this Design Assets reference in the repository. The local site previews user
documentation; start that preview with:

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
  (phone widget review art: `apps/phone_flutter/design/` — locked with
  `docs/product/PHONE_WIDGET_DESIGN.md`).
- Exported runtime assets belong in the consuming platform's normal asset or resource directory.
- Keep only locked previews under `brand/watchface/` — no scratch placement boards.

Runtime targets are `apps/phone_flutter/assets/`,
`apps/phone_flutter/android/app/src/main/res/`, `apps/wear_android/app/src/main/res/`, and
`apps/watchface_wff/src/main/res/`.

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

- OpenAI / Codex: `#65D78A`; Codex · Spark: `#186020` (Spark revision 2026-09-01 — the plan's
  Spark limit is metered on its own, so it carries its own colour).
- Anthropic / Claude: `#E8915A`.
- Cursor · other models: `#67E8D4`; Cursor · own models: `#7E93B8` (split-band revision
  2026-08-13 — the two pools of one plan carry their own colours).
- Unresolved family: `#8A968F` — fallback only. A budget metric is drawn in the family color of
  the connection it belongs to, so the grey should not appear on a shipped surface.

Review exports: `tools/render-watch-ring-designs.mjs` → `round-*.svg`
(matching-provider strip may append remaining purchased credits, never LLM `TOK`;
remaining arcs melt clockwise from 12). The same generator rasterizes the seven
`apps/wear_android/design/preview-*.png` review renders from those boards, and the face-picker
asset `apps/watchface_wff/src/main/res/drawable/preview.png` from the Primary one. Primary
preview: `apps/wear_android/design/preview-3-plan-credits.png`.

Wear **app** Glance legend (**baseline locked 2026-07-26**, not the face):
`tools/render-wear-glance-designs.mjs` → `glance-legend-*.svg` /
`preview-glance-legend-*.png`. Primary preview:
`apps/wear_android/design/preview-glance-legend-3.png`. Variants: `3`, `1`, `pair`, `budget`,
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

Use the **color metal+ring** mark for the phone app bar and phone / Wear launchers. Its opaque
metal disc keeps the compact app-bar mark distinct in both themes; reserve the ringless mono
wordmark for quiet watermark treatments.

### Watch-face watermark (locked)

Quiet branding on WFF — not a second hero. Locked with the concentric face baseline:

- **No framing ring** — straight `WARDPULSE` wordmark above the pulse + eye.
- **Placement** — between time and sunk strips; upper aperture stays free for weather.
- **Size / mute** — a 66×66 box at (192, 227) on the 450 canvas; PartImage `alpha="95"` (37%).
  The asset carries bottom padding, so the ink stops at y 268 and the clear run down to the
  strip stack at y 283 is the dissolve's room. Ambient swaps the mark for a smaller, dimmer
  one: 54×54 at (198, 233), alpha 70.
- **Bottom dissolve** — content-relative fade toward the strip stack
  (`tools/fade-watermark-png.py` during `just export-icons`), so the pulse softens into
  the metrics instead of competing with them.
- Eye placement matches the color mark; pupil stays inside the almond rim.
- **Phone home widget** reuses the same faded mono PNG (`wardpulse_mono`), tinted for
  day/night olive chrome, quiet overlay top-end (does not reserve a header band).

Canonical preview: `apps/watchface_wff/src/main/res/drawable/preview.png`, the face's own
shipped portrait, generated.

**Preview revision 2026-10-11 — the placement preview is generated, not captured.** That image
had been written once, on 2026-07-25, and never again. Looked at on 2026-10-11 it showed a face
the product had left behind: no upper cells, which the face locked on 2026-10-09, and a legend
stack from before the current treatment. So this section was making a placement claim —
*between time and sunk strips* — against a canvas that no longer had the thing above it.

Its signature says it came from a render of the real face: the watermark is in it, and no review
board draws one. A fresh capture was therefore available and was weighed against generating the
picture. **Generating wins, and the reason is reproducibility.** A capture carries whatever the
device held at that moment — on `emulator-5554` the same day, the system picker's own render
showed one set of cell values and the running face another, with two empty wells because weather
was unavailable there. An asset whose content depends on which surface was photographed, and
when, is not canonical. And a capture is a step somebody has to remember, which is the defect
this revision exists to end, not a way to end it.

It was composed by `just export-icons` from two parts that are themselves generated: the
face-picker asset `apps/watchface_wff/src/main/res/drawable/preview.png` and the faded mono
drawable beside it. The box comes from `watchface.xml`, **read from that file at render time
rather than copied here**, so the preview cannot disagree with the face about where the mark
sits — when the face moves it, the preview moves with it, and the numbers in the bullet above
are checked against the same source. The canvas is the face's own 450 units, down from the
previous 675, so every coordinate in this section measures 1:1 against the picture. Where that
picture now lives is the next block.

What this buys and what it costs: the picture is reproducible and tied to the face's own
numbers, and it reconstructs the placement instead of witnessing it. WFF's own compositing —
how the mark actually blends on the watch — is not proved here and is not what this section
cites the preview for; that is a device capture, by hand (`docs/ANDROID_TOOLCHAIN.md`).

The revision set one condition on itself: *the picker asset does not currently draw the
watermark the face draws; if that is ever corrected, this composite becomes a duplicate of it,
and the right move is for this document to cite the face's own asset and stop keeping a brand
copy at all.*

**The condition fired the same day.** `docs/product/WATCH_RING_DESIGN.md` ruled on 2026-10-11
that the face's shipped portrait carries the mark the face carries — a portrait that drops a
locked element of the face shows a wearer a face they will not get — so
`apps/watchface_wff/src/main/res/drawable/preview.png` is now composed from the Primary board
and this same faded mono drawable, in this same box. That makes it the picture
`brand/watchface/preview-face-active-quiet.png` was, so the brand copy is **retired**: the file
is deleted, the compositing step is gone from `tools/export-icons.sh`, and this document cites
the face's asset above. One canonical picture, owned by the document that owns the face.

Two things survive the move and are this document's, not the baseline's. The **box** — 66×66 at
(192, 227), alpha 95 — is still read out of `watchface.xml` at render time rather than copied
into a generator, so the portrait cannot drift from the placement it documents. And the mark in
it is still WardPulse branding: compositing it into a shipped drawable no more places it under
Apache-2.0 than bundling the app-bar copies does.

The ordering between the two generators reverses with the move. `just export-icons` no longer
reads the picker asset; `just render-designs` now reads the faded mono drawable this script
writes. So a change to the **mark** runs `just export-icons` first and then
`just render-designs`, which is the opposite of what this revision first required.

## Source And Runtime Files

| Role | Path |
|------|------|
| Color logo (canonical SVG) | `brand/icons/wardpulse.svg` |
| Mono watermark (canonical SVG) | `brand/icons/wardpulse-mono.svg` |
| PNG previews (incl. faded mono) | `brand/icons/previews/` |
| Flutter app-bar mark (1× / 2× / 3× PNG) | `apps/phone_flutter/assets/brand/` |
| Phone / Wear launcher mipmaps | `mipmap-*/ic_launcher.png` |
| Phone adaptive foreground | `drawable-*/ic_launcher_foreground.png` |
| WFF runtime mono (faded PNG) | `apps/watchface_wff/src/main/res/drawable/wardpulse_mono.png` |
| Phone widget mono (same faded PNG) | `apps/phone_flutter/android/app/src/main/res/drawable/wardpulse_mono.png` |
| WFF face-picker preview | `apps/watchface_wff/src/main/res/drawable/preview.png` |
| WFF ring type, one per ring and period | `apps/watchface_wff/src/main/res/drawable-nodpi/ring{1,2,3}_type_{day,week,month}.png` |

Prefer regenerating exports with `just export-icons` rather than editing PNGs by hand. The mono
drawable must go through `tools/fade-watermark-png.py` (wired in `tools/export-icons.sh`).
Commit runtime exports when an application build consumes them.

The Flutter app-bar copies are bundled WardPulse branding. Moving them into the APK does not
place them under Apache-2.0 or grant downstream use of the WardPulse mark.

The last two rows are the exception: neither is a brand export. The face-picker preview is the
face's own shipped portrait, drawn from the Primary board by `tools/render-watch-ring-designs.mjs`
(`just render-designs`) with the faded mono drawable composed into it at the box above, and
named by `apps/watchface_wff/src/main/res/xml/watch_face_info.xml`; the ring type is the face's
own type, baked by `tools/render-watchface.mjs` (`just render-watchface`) alongside the XML that
names it. Regenerate each there. The mark inside the portrait stays brand: a composite is not a
licence.

ImageMagick is required; Inkscape is preferred for mono SVG→PNG when available.
`tools/fade-watermark-png.py` needs Pillow (`pip`/`apt` package `python3-pil`).
`tools/render-watch-ring-designs.mjs` and `tools/render-wear-glance-designs.mjs` need it too,
plus the Noto Sans Bold file they measure labels against: they stop on a missing font rather
than guess a width, so committed art never depends on the machine that rendered it.

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
just render-designs   # only after a mark change — composes the mono drawable into the portrait
```

The order matters in that one case: the face's shipped portrait is composed on top of the faded
mono drawable, so a change to the **mark** has to reach that drawable before the design
generator reads it. A change to the **face** needs only `just render-designs`.

Do **not** run `just export-design brand/icons/wardpulse.fig …` until the `.fig` is resynced
to the metal+ring mark — an old `.fig` would overwrite the canonical SVG.
