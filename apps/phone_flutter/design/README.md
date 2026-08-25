# Phone widget review art

**Baseline locked 2026-07-27**, revised **2026-08-02** (two-line label) — see
[`docs/product/PHONE_WIDGET_DESIGN.md`](../../../docs/product/PHONE_WIDGET_DESIGN.md).

Primary preview: `widget-medium.svg` (light). Dark: `widget-dark.svg`.

```sh
xdg-open apps/phone_flutter/design/widget-medium.svg
xdg-open apps/phone_flutter/design/widget-dark.svg
```

Variants: `widget-medium`, `widget-dark`, `widget-small`, `widget-empty`, `widget-stale`.
Quiet face watermark sits top-end, or bottom-end where a badge already owns the corner.

Generated, not hand-drawn:

```sh
node tools/render-phone-widget-designs.mjs
```
