# Phone widget review art

**Baseline locked 2026-07-27**, revised **2026-08-02** (two-line label) and **2026-10-13**
(stale clearance) — see
[`docs/product/PHONE_WIDGET_DESIGN.md`](../../../docs/product/PHONE_WIDGET_DESIGN.md).

Primary preview: `widget-medium.svg` (light). Dark: `widget-dark.svg`.

```sh
xdg-open apps/phone_flutter/design/widget-medium.svg
xdg-open apps/phone_flutter/design/widget-dark.svg
```

Variants: `widget-medium`, `widget-dark`, `widget-small`, `widget-empty`, `widget-stale`,
`widget-stale-dark`, `widget-stale-narrow`, `widget-stale-short`.
The watermark stays top-end. Stale badges sit top-start with space reserved above rows;
the short case shows `Resize widget` because no complete metric row fits. These boards use
a nominal review-scale inset; runtime measures its current 11sp bold line plus 2dp.

Generated, not hand-drawn:

```sh
node tools/render-phone-widget-designs.mjs
```
