# Wear OS ring layouts

**Baseline locked 2026-07-25** — see
[`docs/product/WATCH_RING_DESIGN.md`](../../../docs/product/WATCH_RING_DESIGN.md).

Primary preview: `preview-3-plan-credits.png`.

```sh
node tools/render-watch-ring-designs.mjs

convert -background none -density 144 \
  apps/wear_android/design/round-3-plan-credits.svg \
  apps/wear_android/design/preview-3-plan-credits.png
xdg-open apps/wear_android/design/preview-3-plan-credits.png
```

Variants: `round-3-plan-credits`, `round-2-plan-credits`, `round-1-plan`,
`round-1-plan-credits`, `round-credits-only`, `round-ambient-3`.
