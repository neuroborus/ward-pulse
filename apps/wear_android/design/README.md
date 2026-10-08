# Wear OS design review art

## Watch face rings (locked)

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

Variants: `round-3-plan-credits`, `round-3-plan-split`, `round-3-plan-budget`,
`round-2-plan-credits`, `round-1-plan`, `round-1-plan-credits`, `round-credits-only`,
`round-ambient-3`.

## App Glance legend (locked)

**Baseline locked 2026-07-26** — accepted; see
[`docs/product/WEAR_GLANCE_DESIGN.md`](../../../docs/product/WEAR_GLANCE_DESIGN.md).

Text legend for face ring colors; not a face clone. Refresh pulse (`OK` / `!OK`) is
independent of enabled/disabled (cadence cooldown stays `OK` + gray). Primary preview:
`preview-glance-legend-3.png`.

```sh
node tools/render-wear-glance-designs.mjs

convert -background none -density 144 \
  apps/wear_android/design/glance-legend-3.svg \
  apps/wear_android/design/preview-glance-legend-3.png
xdg-open apps/wear_android/design/preview-glance-legend-3.png
```

Variants: `glance-legend-3`, `glance-legend-1`, `glance-legend-pair`,
`glance-legend-budget`, `glance-legend-stale`, `glance-legend-cadence`,
`glance-legend-rate-limit`, `glance-legend-empty`, `glance-legend-exhausted`.
