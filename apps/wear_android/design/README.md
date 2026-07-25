# Wear OS ring layouts

**Baseline locked 2026-07-25** — see
[`docs/product/WATCH_RING_DESIGN.md`](../../../docs/product/WATCH_RING_DESIGN.md).

Primary preview: `preview-3-plan-tokens.png`.

```sh
node tools/render-watch-ring-designs.mjs

convert -background none -density 144 \
  apps/wear_android/design/round-3-plan-tokens.svg \
  apps/wear_android/design/preview-3-plan-tokens.png
xdg-open apps/wear_android/design/preview-3-plan-tokens.png
```

Variants: `round-3-plan-tokens`, `round-2-plan-tokens`, `round-1-plan`,
`round-1-plan-tokens`, `round-tokens-only`, `round-ambient-3`.
