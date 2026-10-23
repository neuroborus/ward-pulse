# Screenshot format and presentation

Read completely together with [capture-state.md](capture-state.md) before screenshot work
routed by [user-docs](../SKILL.md).

## Showcase and task images

Choose up to THREE showcase screenshots PER platform for the landing/README gallery.
Android phone and Wear OS count as ONE platform: its current gallery has three showcase subjects, with
both phone and watch represented. This is a showcase selection limit, not a global cap
on the screenshot library or other platforms. Reuse the approved set on the landing page
and root README. Place the gallery near the beginning, before long explanatory material;
use useful captions/alt text.

The three-subject limit applies only to the landing/README showcase. Use meaningful task
screenshots near the related steps or results to break long explanations where a picture
helps. Include real Providers connection examples, Widget selection/configuration and actual
home-screen widgets. Choose the smallest useful set; avoid decorative quotas or duplicated
walls of images. Guide images follow the same theme, clean-status-bar, privacy, size, index
and freshness rules.

## Shared application state

Screenshots of different components shown together or beside one another must depict a
shared application state. Capture the whole related group in one session from the same
live phone snapshot and its delivered watch/widget state; do not mix historical and current
captures. Check overlapping percentages, purchased credits, selected pools and windows,
history and statuses across components and both themes, allowing only the surfaces' actual
display rounding. If the underlying state changes during capture, recapture the whole
affected group. Record the shared state and capture session in the screenshot index. Apply
this rule to guide pages as well as the identical approved Overview/README gallery.

## Captions and action highlights

Prefer clear captions. Useful action highlights are optional editorial overlays authored by
Runner over clean PNGs: transparent interior, `#2563EB` outline at 2 CSS px, 4 CSS px clearance
around the confirmed glyph bounds and 8 CSS px corner radius, retained at responsive sizes.
Do not outline adjacent full touch boxes. If numbering helps, use a 20 CSS px blue circle
with a 12 CSS px bold white sans-serif digit outside the control bounds. Keep glyphs, text
and sensitive areas unobscured; never invent controls or make the decoration interactive.
Captions name the real icons/actions and remain true for clean Markdown exports; do not
claim marks are baked into the PNG. Preserve clean original-image links and PNG bytes.
Index a derivative with its source only if an actual separate annotated PNG is produced.

## Files, frames and freshness

- Store PNGs in `docs/assets/` with meaningful lower-kebab filenames.
- Phone screenshot height is 1920px with source aspect ratio preserved; record actual width.
- Watch screenshots are 500×500px PNGs with transparency outside the actual circular screen.
  Preserve all UI inside the circle; do not crop the face, distort, recolour or fabricate it.
- Frames use a 1 CSS px neutral outline (`--vocs-border-color-primary`) in both themes:
  rectangular phone with radius 0, circular Wear with radius 50%. No additional shadow or
  UI clipping. Desktop target/max width is 288 CSS px for guide previews; landing/README
  targets are 216 CSS px for phone and 200 CSS px for Wear. Responsive reductions preserve
  aspect ratio. GitHub uses its supported 1 px neutral table-border fallback, not stripped
  CSS. Keep these tokens out of public prose.
- `docs/assets/README.md` must index every screenshot with description and DATE ADDED.
  Record capture/verification dates, dimensions, known app/context, data treatment and
  locations where it is used; include a build version only if actually recorded. Do not add rows
  for planned/nonexistent screenshots as though they were captured.
- When pictured UI changes, update the affected PNGs and index in the same change set;
  review the whole set for consistency. If captures cannot run yet, record the pending work
  accurately and do not claim screenshot freshness or final acceptance. Preserve the
  existing host/device check division and Runner commit boundary.
