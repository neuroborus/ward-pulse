# Phone widget review art

**Visual baseline approved 2026-11-01; replacement native acceptance pending.** See
[`PHONE_WIDGET_DESIGN.md`](../../../docs/product/PHONE_WIDGET_DESIGN.md) for the current
contract and explicitly dated former-renderer evidence.

`widget-medium` (light) and `widget-dark` show six complete rows in a nominal 360×344
allocation. `widget-small` shows three labeled rows at 266×184; `widget-narrow` shows
three percentage-only rows at 150×184. These examples are not universal native thresholds.
The full card keeps compact complete content, two-line family/pool labels and the
30/26/18/16/11 hierarchy. All values/dates are synthetic illustrations, never live payloads.

Each SVG has a matching PNG. Additional variants are `widget-empty`, `widget-stale`,
`widget-stale-dark`, `widget-stale-narrow` and `widget-stale-short`. Stale examples reserve
font padding plus the 2-unit gap; empty/no-fit messages use 12 Regular. Android measures
its own glyphs and requires separate native verification.

The owning generator reads the exact bundled Noto Regular/Bold files and their pinned
hashes. Glyph images are embedded in SVGs too, preventing a viewer's font substitution.
It uses the existing Pillow design dependency, and owns the matching PNGs, light/dark
picker image resources, preview layout and preview accessibility description. Normal
generation rewrites these raster exports; the read-only drift gate compares text exports.

```sh
node tools/render-phone-widget-designs.mjs
```

The original optional approved board and metadata remain unchanged as private approval
provenance. Their historical filename/status does not override the later exact-image
approval and does not establish runtime/native acceptance. Necessary public native captures
are separate POST-RUN HOST work; these review PNGs do not replace them.
